import AppKit

/// Wraps NSButton (push button style). v1 properties: title, frame, enabled.
/// v1 events: clicked.
final class ButtonFactory: WidgetFactory {
    let typeName = "NSButton"

    /// Per-button action target retained on the heap so the button keeps
    /// it alive (NSControl.target is held weakly).
    private var targets: [ObjectIdentifier: ButtonTarget] = [:]

    func create() -> AnyObject {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 100, height: 32))
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.title = "Button"
        return button
    }

    func setProperty(_ name: String, value: JSONValue, on object: AnyObject) throws {
        guard let button = object as? NSButton else {
            throw WidgetError.internalError("expected NSButton")
        }
        switch name {
        case "title":
            button.title = value.asString ?? ""
        case "enabled":
            button.isEnabled = value.asBool ?? true
        case "frame":
            button.frame = try WidgetProps.parseFrame(value)
        case "autoresizingMask":
            button.autoresizingMask = WidgetProps.parseAutoresizingMask(value)
        default:
            throw WidgetError.unknownProperty(name)
        }
    }

    func subscribe(_ event: String,
                   on object: AnyObject,
                   widgetId: String,
                   emit: @escaping (String, JSONValue) -> Void) throws {
        guard let button = object as? NSButton else {
            throw WidgetError.internalError("expected NSButton")
        }
        switch event {
        case "clicked":
            let target = ButtonTarget { emit("clicked", .object([:])) }
            targets[ObjectIdentifier(button)] = target
            button.target = target
            button.action = #selector(ButtonTarget.fire(_:))
        default:
            throw WidgetError.unknownEvent(event)
        }
    }

    func tearDown(_ object: AnyObject) {
        guard let button = object as? NSButton else { return }
        targets.removeValue(forKey: ObjectIdentifier(button))
        button.removeFromSuperview()
    }
}

/// Trampoline class so NSButton's target/action mechanism can call back into
/// a Swift closure. We can't use a bare closure because NSControl needs
/// an Objective-C selector and an NSObject target.
private final class ButtonTarget: NSObject {
    private let callback: () -> Void

    init(_ callback: @escaping () -> Void) {
        self.callback = callback
        super.init()
    }

    @objc func fire(_ sender: Any?) {
        callback()
    }
}
