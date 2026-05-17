import AppKit

/// Wraps NSSplitView. AppKit's NSSplitView with `isVertical = true` draws
/// a vertical divider and arranges children horizontally; we expose this
/// at the wire level as the `vertical` property with the same semantics.
///
/// Properties: vertical (bool), dividerStyle ('thin'|'thick'|'paneSplitter'),
/// dividerPositions ([Number] -- applied on next runloop tick).
/// Child role: arrangedSubview (many; preserves insertion order).
final class SplitViewFactory: WidgetFactory {
    let typeName = "NSSplitView"

    func create() -> AnyObject {
        let split = NSSplitView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        split.dividerStyle = .thin
        split.isVertical = false
        return split
    }

    func setProperty(_ name: String, value: JSONValue, on object: AnyObject) throws {
        guard let split = object as? NSSplitView else {
            throw WidgetError.internalError("expected NSSplitView")
        }
        switch name {
        case "vertical":
            split.isVertical = value.asBool ?? false
        case "dividerStyle":
            split.dividerStyle = parseDividerStyle(value.asString ?? "thin")
        case "dividerPositions":
            guard let array = value.asArray else {
                throw WidgetError.badRequest("dividerPositions expects array of numbers")
            }
            let positions = array.compactMap { $0.asDouble }
            // Defer to the next runloop tick so the split view has been
            // laid out and the divider count matches.
            DispatchQueue.main.async {
                for (i, pos) in positions.enumerated() where i < split.arrangedSubviews.count - 1 {
                    split.setPosition(CGFloat(pos), ofDividerAt: i)
                }
            }
        case "frame":
            split.frame = try WidgetProps.parseFrame(value)
        case "autoresizingMask":
            split.autoresizingMask = WidgetProps.parseAutoresizingMask(value)
        default:
            throw WidgetError.unknownProperty(name)
        }
    }

    func addChild(_ child: AnyObject, role: String, to parent: AnyObject) throws {
        guard let split = parent as? NSSplitView else {
            throw WidgetError.internalError("expected NSSplitView parent")
        }
        guard let view = child as? NSView else {
            throw WidgetError.badRequest("NSSplitView children must be NSView, got \(type(of: child))")
        }
        switch role {
        case "arrangedSubview", "subview":
            split.addArrangedSubview(view)
        default:
            throw WidgetError.badRequest("NSSplitView does not accept child role '\(role)'")
        }
    }

    func tearDown(_ object: AnyObject) {
        guard let split = object as? NSSplitView else { return }
        split.removeFromSuperview()
    }

    private func parseDividerStyle(_ s: String) -> NSSplitView.DividerStyle {
        switch s {
        case "thick": return .thick
        case "paneSplitter": return .paneSplitter
        default: return .thin
        }
    }
}
