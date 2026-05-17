import AppKit

/// Wraps NSSegmentedControl in "select one" mode (radio-button row).
/// Pharo sets the labels via `segments` and reads / writes the active
/// index via `selectedSegment`.
///
/// Properties:
///   segments         [String] -- replace labels
///   selectedSegment  Int      -- index, -1 to clear
///   frame, autoresizingMask
///
/// Events:
///   selectionChanged -> { index: Int, label: String }
final class SegmentedControlFactory: WidgetFactory {
    let typeName = "NSSegmentedControl"

    private var targets: [ObjectIdentifier: SegmentedTarget] = [:]

    func create() -> AnyObject {
        let ctl = NSSegmentedControl(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        ctl.segmentStyle = .rounded
        ctl.trackingMode = .selectOne
        ctl.segmentCount = 0
        return ctl
    }

    func setProperty(_ name: String, value: JSONValue, on object: AnyObject) throws {
        guard let ctl = object as? NSSegmentedControl else {
            throw WidgetError.internalError("expected NSSegmentedControl")
        }
        switch name {
        case "segments":
            guard let array = value.asArray else {
                throw WidgetError.badRequest("segments expects an array")
            }
            let labels = array.compactMap { $0.asString }
            ctl.segmentCount = labels.count
            for (i, label) in labels.enumerated() {
                ctl.setLabel(label, forSegment: i)
                ctl.setWidth(0, forSegment: i)
            }
        case "selectedSegment":
            let idx = value.asInt ?? -1
            if idx >= 0, idx < ctl.segmentCount {
                ctl.selectedSegment = idx
            } else {
                ctl.selectedSegment = -1
            }
        case "frame":
            ctl.frame = try WidgetProps.parseFrame(value)
        case "autoresizingMask":
            ctl.autoresizingMask = WidgetProps.parseAutoresizingMask(value)
        default:
            throw WidgetError.unknownProperty(name)
        }
    }

    func getProperty(_ name: String, on object: AnyObject) throws -> JSONValue {
        guard let ctl = object as? NSSegmentedControl else {
            throw WidgetError.internalError("expected NSSegmentedControl")
        }
        switch name {
        case "selectedSegment":
            return .int(ctl.selectedSegment)
        default:
            throw WidgetError.unknownProperty(name)
        }
    }

    func subscribe(_ event: String,
                   on object: AnyObject,
                   widgetId: String,
                   emit: @escaping (String, JSONValue) -> Void) throws {
        guard let ctl = object as? NSSegmentedControl else {
            throw WidgetError.internalError("expected NSSegmentedControl")
        }
        switch event {
        case "selectionChanged":
            let target = SegmentedTarget { [weak ctl] in
                guard let ctl else { return }
                let idx = ctl.selectedSegment
                let label = (idx >= 0 && idx < ctl.segmentCount)
                    ? (ctl.label(forSegment: idx) ?? "")
                    : ""
                emit("selectionChanged", .object([
                    "index": .int(idx),
                    "label": .string(label)
                ]))
            }
            targets[ObjectIdentifier(ctl)] = target
            ctl.target = target
            ctl.action = #selector(SegmentedTarget.fire(_:))
        default:
            throw WidgetError.unknownEvent(event)
        }
    }

    func tearDown(_ object: AnyObject) {
        guard let ctl = object as? NSSegmentedControl else { return }
        targets.removeValue(forKey: ObjectIdentifier(ctl))
        ctl.removeFromSuperview()
    }
}

private final class SegmentedTarget: NSObject {
    private let callback: () -> Void

    init(_ callback: @escaping () -> Void) {
        self.callback = callback
        super.init()
    }

    @objc func fire(_ sender: Any?) {
        callback()
    }
}
