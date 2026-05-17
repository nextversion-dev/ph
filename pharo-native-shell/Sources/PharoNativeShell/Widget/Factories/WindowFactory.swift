import AppKit

/// Wraps NSWindow. Children with role "contentView" replace
/// `contentView`. v1 properties: title, contentSize, frame.
/// v1 selectors: makeKeyAndOrderFront, close, center.
/// v1 events: willClose.
final class WindowFactory: NSObject, WidgetFactory {
    let typeName = "NSWindow"

    /// Stored per-window so we can detach the observer in tearDown.
    private var observers: [ObjectIdentifier: NSObjectProtocol] = [:]

    func create() -> AnyObject {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: window.contentLayoutRect)
        window.center()
        return window
    }

    func setProperty(_ name: String, value: JSONValue, on object: AnyObject) throws {
        guard let window = object as? NSWindow else {
            throw WidgetError.internalError("expected NSWindow")
        }
        switch name {
        case "title":
            window.title = value.asString ?? ""
        case "contentSize":
            let size = try WidgetProps.parseSize(value)
            window.setContentSize(size)
            window.center()
        case "frame":
            let rect = try WidgetProps.parseFrame(value)
            window.setFrame(rect, display: true)
        default:
            throw WidgetError.unknownProperty(name)
        }
    }

    func addChild(_ child: AnyObject, role: String, to parent: AnyObject) throws {
        guard let window = parent as? NSWindow else {
            throw WidgetError.internalError("expected NSWindow parent")
        }
        guard let view = child as? NSView else {
            throw WidgetError.badRequest("NSWindow children must be NSView, got \(type(of: child))")
        }
        switch role {
        case "contentView":
            window.contentView = view
        default:
            throw WidgetError.badRequest("NSWindow does not accept child role '\(role)'")
        }
    }

    func invoke(_ selector: String, args: [JSONValue], on object: AnyObject) throws -> JSONValue {
        guard let window = object as? NSWindow else {
            throw WidgetError.internalError("expected NSWindow")
        }
        switch selector {
        case "makeKeyAndOrderFront":
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return .null
        case "close":
            window.close()
            return .null
        case "center":
            window.center()
            return .null
        default:
            throw WidgetError.unknownSelector(selector)
        }
    }

    func subscribe(_ event: String,
                   on object: AnyObject,
                   widgetId: String,
                   emit: @escaping (String, JSONValue) -> Void) throws {
        guard let window = object as? NSWindow else {
            throw WidgetError.internalError("expected NSWindow")
        }
        switch event {
        case "willClose":
            let token = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                emit("willClose", .object([:]))
            }
            observers[ObjectIdentifier(window)] = token
        default:
            throw WidgetError.unknownEvent(event)
        }
    }

    func tearDown(_ object: AnyObject) {
        guard let window = object as? NSWindow else { return }
        if let token = observers.removeValue(forKey: ObjectIdentifier(window)) {
            NotificationCenter.default.removeObserver(token)
        }
        window.close()
    }
}
