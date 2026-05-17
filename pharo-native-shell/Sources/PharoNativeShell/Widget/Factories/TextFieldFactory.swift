import AppKit

/// Wraps NSTextField. Default appearance is a non-editable, non-bordered
/// label (matches the common "label" idiom). Use the `editable` and
/// `bordered` props to make it behave like a text input.
///
/// v1 properties: stringValue, editable, bordered, frame.
/// v1 events: none in this iteration (text input editing arrives later
/// with the NSText edit cycle work).
final class TextFieldFactory: WidgetFactory {
    let typeName = "NSTextField"

    func create() -> AnyObject {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        field.isEditable = false
        field.isSelectable = true
        field.isBordered = false
        field.drawsBackground = false
        field.stringValue = ""
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func setProperty(_ name: String, value: JSONValue, on object: AnyObject) throws {
        guard let field = object as? NSTextField else {
            throw WidgetError.internalError("expected NSTextField")
        }
        switch name {
        case "stringValue":
            field.stringValue = value.asString ?? ""
        case "editable":
            let editable = value.asBool ?? false
            field.isEditable = editable
            field.drawsBackground = editable || field.isBordered
        case "bordered":
            let bordered = value.asBool ?? false
            field.isBordered = bordered
            field.drawsBackground = bordered || field.isEditable
        case "frame":
            field.frame = try WidgetProps.parseFrame(value)
        default:
            throw WidgetError.unknownProperty(name)
        }
    }

    func tearDown(_ object: AnyObject) {
        guard let field = object as? NSTextField else { return }
        field.removeFromSuperview()
    }
}
