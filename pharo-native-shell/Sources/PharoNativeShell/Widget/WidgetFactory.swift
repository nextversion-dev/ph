import AppKit

/// A widget factory knows how to instantiate one AppKit class, apply
/// a set of named properties to it, dispatch named "invoke" calls (Swift
/// equivalents of Smalltalk message sends), accept named child relations,
/// and wire named events to emit JSON-RPC notifications.
///
/// One factory is registered per widget `type` string. The widget host
/// looks the factory up by type when handling `widget.create`.
protocol WidgetFactory {
    /// Wire-level type name, e.g. "NSWindow".
    var typeName: String { get }

    /// Create the underlying AppKit object. Must be called on the main thread.
    func create() -> AnyObject

    /// Apply a single named property. May be called many times per widget,
    /// both at create time (from the `props` blob) and via setProp later.
    func setProperty(_ name: String, value: JSONValue, on object: AnyObject) throws

    /// Add a child object under a named relationship role.
    func addChild(_ child: AnyObject, role: String, to parent: AnyObject) throws

    /// Invoke a behavioural verb (e.g. "makeKeyAndOrderFront", "close").
    /// `args` is an array of decoded JSON values.
    func invoke(_ selector: String, args: [JSONValue], on object: AnyObject) throws -> JSONValue

    /// Subscribe to a named event source. The factory should wire whatever
    /// AppKit hook is necessary so that when the event fires, `emit` is
    /// called with the event name and an optional JSON payload object.
    func subscribe(_ event: String,
                   on object: AnyObject,
                   widgetId: String,
                   emit: @escaping (String, JSONValue) -> Void) throws

    /// Tear down anything the factory installed (e.g. close windows,
    /// remove observers). The host removes the entry from its registry
    /// after this returns.
    func tearDown(_ object: AnyObject)
}

/// Default no-op implementations so individual factories only override what
/// they need.
extension WidgetFactory {
    func addChild(_ child: AnyObject, role: String, to parent: AnyObject) throws {
        throw WidgetError.badRequest("\(typeName) does not accept children with role '\(role)'")
    }

    func invoke(_ selector: String, args: [JSONValue], on object: AnyObject) throws -> JSONValue {
        throw WidgetError.unknownSelector("\(typeName) cannot invoke '\(selector)'")
    }

    func subscribe(_ event: String,
                   on object: AnyObject,
                   widgetId: String,
                   emit: @escaping (String, JSONValue) -> Void) throws {
        throw WidgetError.unknownEvent("\(typeName) does not emit '\(event)'")
    }

    func tearDown(_ object: AnyObject) {
        // Default: nothing. Specific factories (e.g. NSWindow) override.
    }
}

/// Shared helpers used by multiple factories.
enum WidgetProps {
    /// Parses { x: Number, y: Number, w: Number, h: Number } into NSRect.
    static func parseFrame(_ value: JSONValue) throws -> NSRect {
        guard let dict = value.asObject,
              let x = dict["x"]?.asDouble,
              let y = dict["y"]?.asDouble,
              let w = dict["w"]?.asDouble,
              let h = dict["h"]?.asDouble else {
            throw WidgetError.badRequest("expected frame object { x, y, w, h }")
        }
        return NSRect(x: x, y: y, width: w, height: h)
    }

    /// Parses { w: Number, h: Number } into NSSize.
    static func parseSize(_ value: JSONValue) throws -> NSSize {
        guard let dict = value.asObject,
              let w = dict["w"]?.asDouble,
              let h = dict["h"]?.asDouble else {
            throw WidgetError.badRequest("expected size object { w, h }")
        }
        return NSSize(width: w, height: h)
    }

    /// Parses an array of strings into an NSView.AutoresizingMask.
    /// Recognised tokens: width, height, minX, maxX, minY, maxY.
    static func parseAutoresizingMask(_ value: JSONValue) -> NSView.AutoresizingMask {
        guard let array = value.asArray else { return [] }
        var mask: NSView.AutoresizingMask = []
        for v in array {
            switch v.asString {
            case "width": mask.insert(.width)
            case "height": mask.insert(.height)
            case "minX": mask.insert(.minXMargin)
            case "maxX": mask.insert(.maxXMargin)
            case "minY": mask.insert(.minYMargin)
            case "maxY": mask.insert(.maxYMargin)
            default: break
            }
        }
        return mask
    }
}
