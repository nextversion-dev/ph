import AppKit

/// Wraps NSTextView, configured for code display. The text view is
/// embeddable inside an NSScrollView (its standard idiom) -- the
/// ScrollViewFactory's `documentView` role handles the parenting.
///
/// Properties:
///   string         -- replace contents (plain text)
///   attributedRuns -- apply colored runs after `string` is set
///   editable       -- bool; false in v2
///   font           -- { family: String, size: Number }
///   frame          -- Rect
///
/// `attributedRuns` is `[ { location, length, foreground } ]`. The
/// `foreground` field is a named color: "red", "green", "blue",
/// "purple", "teal", "orange", "label" (default).
final class TextViewFactory: WidgetFactory {
    let typeName = "NSTextView"

    func create() -> AnyObject {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = false
        tv.allowsUndo = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.usesFindBar = true
        tv.textColor = .labelColor
        return tv
    }

    func setProperty(_ name: String, value: JSONValue, on object: AnyObject) throws {
        guard let tv = object as? NSTextView else {
            throw WidgetError.internalError("expected NSTextView")
        }
        switch name {
        case "string":
            let s = value.asString ?? ""
            let attributes: [NSAttributedString.Key: Any] = [
                .font: tv.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
            let attributed = NSAttributedString(string: s, attributes: attributes)
            tv.textStorage?.setAttributedString(attributed)
        case "attributedRuns":
            guard let array = value.asArray else {
                throw WidgetError.badRequest("attributedRuns expects an array of run objects")
            }
            guard let storage = tv.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            // Reset existing color to the base label color before applying runs.
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
            for item in array {
                guard let dict = item.asObject,
                      let location = dict["location"]?.asInt,
                      let length = dict["length"]?.asInt else {
                    continue
                }
                let range = NSRange(location: location, length: length)
                guard range.location >= 0,
                      range.length >= 0,
                      range.location + range.length <= storage.length else {
                    continue
                }
                let colorName = dict["foreground"]?.asString ?? "label"
                storage.addAttribute(.foregroundColor, value: TextViewFactory.color(named: colorName), range: range)
            }
            storage.endEditing()
        case "editable":
            tv.isEditable = value.asBool ?? false
        case "font":
            guard let dict = value.asObject else {
                throw WidgetError.badRequest("font expects { family, size }")
            }
            let family = dict["family"]?.asString ?? "Menlo"
            let size = dict["size"]?.asDouble ?? 13
            tv.font = NSFont(name: family, size: CGFloat(size))
                ?? NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
        case "frame":
            tv.frame = try WidgetProps.parseFrame(value)
        case "autoresizingMask":
            tv.autoresizingMask = WidgetProps.parseAutoresizingMask(value)
        default:
            throw WidgetError.unknownProperty(name)
        }
    }

    func getProperty(_ name: String, on object: AnyObject) throws -> JSONValue {
        guard let tv = object as? NSTextView else {
            throw WidgetError.internalError("expected NSTextView")
        }
        switch name {
        case "string":
            return .string(tv.string)
        case "editable":
            return .bool(tv.isEditable)
        default:
            throw WidgetError.unknownProperty(name)
        }
    }

    func tearDown(_ object: AnyObject) {
        guard let tv = object as? NSTextView else { return }
        tv.removeFromSuperview()
    }

    static func color(named name: String) -> NSColor {
        switch name {
        case "red": return .systemRed
        case "green": return .systemGreen
        case "blue": return .systemBlue
        case "purple": return .systemPurple
        case "teal": return .systemTeal
        case "orange": return .systemOrange
        case "yellow": return .systemYellow
        case "pink": return .systemPink
        case "gray": return .secondaryLabelColor
        default: return .labelColor
        }
    }
}
