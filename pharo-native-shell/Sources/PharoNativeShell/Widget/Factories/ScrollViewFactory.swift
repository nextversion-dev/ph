import AppKit

/// Wraps NSScrollView. The single supported child role is `documentView`,
/// which assigns the child as the scroll view's document. When the child
/// is an NSTableView we also configure standard table-in-scroll-view
/// autoresizing so widening the scroll view widens the table.
///
/// v1 properties: hasVerticalScroller, hasHorizontalScroller, borderType, frame.
final class ScrollViewFactory: WidgetFactory {
    let typeName = "NSScrollView"

    func create() -> AnyObject {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        return scroll
    }

    func setProperty(_ name: String, value: JSONValue, on object: AnyObject) throws {
        guard let scroll = object as? NSScrollView else {
            throw WidgetError.internalError("expected NSScrollView")
        }
        switch name {
        case "hasVerticalScroller":
            scroll.hasVerticalScroller = value.asBool ?? true
        case "hasHorizontalScroller":
            scroll.hasHorizontalScroller = value.asBool ?? false
        case "borderType":
            scroll.borderType = parseBorderType(value.asString ?? "none")
        case "frame":
            scroll.frame = try WidgetProps.parseFrame(value)
        case "autoresizingMask":
            scroll.autoresizingMask = WidgetProps.parseAutoresizingMask(value)
        default:
            throw WidgetError.unknownProperty(name)
        }
    }

    func addChild(_ child: AnyObject, role: String, to parent: AnyObject) throws {
        guard let scroll = parent as? NSScrollView else {
            throw WidgetError.internalError("expected NSScrollView parent")
        }
        switch role {
        case "documentView":
            guard let view = child as? NSView else {
                throw WidgetError.badRequest("documentView must be NSView, got \(type(of: child))")
            }
            scroll.documentView = view
            // Standard NSTableView-in-NSScrollView ergonomics: let the
            // table widen with the scroll view, keep its own height.
            if let table = view as? NSTableView {
                table.frame = NSRect(origin: .zero, size: scroll.contentSize)
                table.autoresizingMask = [.width]
                table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
            }
        default:
            throw WidgetError.badRequest("NSScrollView does not accept child role '\(role)'")
        }
    }

    func tearDown(_ object: AnyObject) {
        guard let scroll = object as? NSScrollView else { return }
        scroll.documentView = nil
        scroll.removeFromSuperview()
    }

    private func parseBorderType(_ s: String) -> NSBorderType {
        switch s {
        case "line": return .lineBorder
        case "bezel": return .bezelBorder
        case "groove": return .grooveBorder
        default: return .noBorder
        }
    }
}
