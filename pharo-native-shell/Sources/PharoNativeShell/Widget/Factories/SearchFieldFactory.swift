import AppKit

/// Wraps NSSearchField. Same family as NSTextField but with native
/// search-field styling and the cancel button. Emits `textChanged`
/// continuously as the user types (via NSControl.controlTextDidChange).
///
/// Properties:
///   stringValue       String
///   placeholder       String -- the greyed-out hint shown when empty
///   frame             Rect
///   autoresizingMask
///
/// Events:
///   textChanged -> { text: String }
final class SearchFieldFactory: WidgetFactory {
    let typeName = "NSSearchField"

    private var targets: [ObjectIdentifier: SearchFieldTarget] = [:]

    func create() -> AnyObject {
        let field = NSSearchField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.sendsSearchStringImmediately = false
        field.sendsWholeSearchString = false
        return field
    }

    func setProperty(_ name: String, value: JSONValue, on object: AnyObject) throws {
        guard let field = object as? NSSearchField else {
            throw WidgetError.internalError("expected NSSearchField")
        }
        switch name {
        case "stringValue":
            field.stringValue = value.asString ?? ""
        case "placeholder":
            field.placeholderString = value.asString ?? ""
        case "frame":
            field.frame = try WidgetProps.parseFrame(value)
        case "autoresizingMask":
            field.autoresizingMask = WidgetProps.parseAutoresizingMask(value)
        default:
            throw WidgetError.unknownProperty(name)
        }
    }

    func getProperty(_ name: String, on object: AnyObject) throws -> JSONValue {
        guard let field = object as? NSSearchField else {
            throw WidgetError.internalError("expected NSSearchField")
        }
        switch name {
        case "stringValue":
            return .string(field.stringValue)
        default:
            throw WidgetError.unknownProperty(name)
        }
    }

    func subscribe(_ event: String,
                   on object: AnyObject,
                   widgetId: String,
                   emit: @escaping (String, JSONValue) -> Void) throws {
        guard let field = object as? NSSearchField else {
            throw WidgetError.internalError("expected NSSearchField")
        }
        switch event {
        case "textChanged":
            let target = SearchFieldTarget { text in
                emit("textChanged", .object(["text": .string(text)]))
            }
            targets[ObjectIdentifier(field)] = target
            field.target = target
            field.action = #selector(SearchFieldTarget.fire(_:))
            // sendsSearchStringImmediately=false + sendsWholeSearchString=false
            // means action fires after a short pause / on Return; we also
            // hook NSControl's continuous text-change notification so the
            // event fires per keystroke for live filter feel.
            NotificationCenter.default.addObserver(
                target,
                selector: #selector(SearchFieldTarget.controlTextDidChange(_:)),
                name: NSControl.textDidChangeNotification,
                object: field)
        default:
            throw WidgetError.unknownEvent(event)
        }
    }

    func tearDown(_ object: AnyObject) {
        guard let field = object as? NSSearchField else { return }
        if let target = targets.removeValue(forKey: ObjectIdentifier(field)) {
            NotificationCenter.default.removeObserver(target)
        }
        field.target = nil
        field.action = nil
        field.removeFromSuperview()
    }
}

/// Trampoline that bridges NSSearchField's target/action + text-change
/// notifications into a Swift closure.
private final class SearchFieldTarget: NSObject {
    private let callback: (String) -> Void

    init(_ callback: @escaping (String) -> Void) {
        self.callback = callback
        super.init()
    }

    @objc func fire(_ sender: Any?) {
        if let field = sender as? NSSearchField {
            callback(field.stringValue)
        }
    }

    @objc func controlTextDidChange(_ notification: Notification) {
        if let field = notification.object as? NSSearchField {
            callback(field.stringValue)
        }
    }
}
