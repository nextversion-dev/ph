import AppKit

/// Wraps NSView, used as a content view or container for subviews in v1.
/// Children with role "subview" are added via addSubview:.
final class ViewFactory: WidgetFactory {
    let typeName = "NSView"

    func create() -> AnyObject {
        return NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    }

    func setProperty(_ name: String, value: JSONValue, on object: AnyObject) throws {
        guard let view = object as? NSView else {
            throw WidgetError.internalError("expected NSView")
        }
        switch name {
        case "frame":
            view.frame = try WidgetProps.parseFrame(value)
        case "autoresizingMask":
            view.autoresizingMask = WidgetProps.parseAutoresizingMask(value)
        default:
            throw WidgetError.unknownProperty(name)
        }
    }

    func addChild(_ child: AnyObject, role: String, to parent: AnyObject) throws {
        guard let parentView = parent as? NSView else {
            throw WidgetError.internalError("expected NSView parent")
        }
        guard let childView = child as? NSView else {
            throw WidgetError.badRequest("NSView children must be NSView, got \(type(of: child))")
        }
        switch role {
        case "subview":
            parentView.addSubview(childView)
        default:
            throw WidgetError.badRequest("NSView does not accept child role '\(role)'")
        }
    }
}
