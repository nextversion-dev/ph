import AppKit

/// Maps widget ids (allocated by Pharo) to live AppKit objects, and
/// dispatches `widget.*` JSON-RPC requests from the server.
///
/// All public methods must be called on the main thread. The server
/// guarantees this by hopping to `DispatchQueue.main.async` before any
/// call. We do not annotate `@MainActor` because the server itself runs
/// on a background queue and constructs the host from there.
final class WidgetHost {

    /// Closure the server installs so the host can push event notifications
    /// to the connected Pharo client. Invoked on the main thread.
    var eventEmitter: ((JSONRPCNotification) -> Void)?

    private struct Entry {
        let typeName: String
        let object: AnyObject
        let factory: WidgetFactory
    }

    private var registry: [String: Entry] = [:]
    private var factories: [String: WidgetFactory] = [:]
    private var defaultsRegistered = false

    func reset() {
        // Tear down everything; called when the connection closes so a
        // reconnecting Pharo image starts from a clean slate.
        for (_, entry) in registry {
            entry.factory.tearDown(entry.object)
        }
        registry.removeAll()
    }

    func handle(method: String, params: JSONValue?) throws -> JSONValue {
        if !defaultsRegistered {
            registerDefaults()
            defaultsRegistered = true
        }
        switch method {
        case "widget.create":   return try handleCreate(params: params)
        case "widget.setProp":  return try handleSetProp(params: params)
        case "widget.getProp":  return try handleGetProp(params: params)
        case "widget.addChild": return try handleAddChild(params: params)
        case "widget.invoke":   return try handleInvoke(params: params)
        case "widget.subscribe":return try handleSubscribe(params: params)
        case "widget.destroy":  return try handleDestroy(params: params)
        case "shell.ping":      return .object(["ok": .bool(true)])
        default: throw WidgetError.badRequest("unknown method: \(method)")
        }
    }

    // MARK: handlers

    private func handleCreate(params: JSONValue?) throws -> JSONValue {
        guard let dict = params?.asObject,
              let id = dict["id"]?.asString,
              let type = dict["type"]?.asString else {
            throw WidgetError.badRequest("widget.create requires id and type")
        }
        if registry[id] != nil {
            throw WidgetError.badRequest("widget id already exists: \(id)")
        }
        guard let factory = factories[type] else {
            throw WidgetError.unknownType(type)
        }
        let object = factory.create()
        registry[id] = Entry(typeName: type, object: object, factory: factory)

        if let props = dict["props"]?.asObject {
            for (name, value) in props {
                try factory.setProperty(name, value: value, on: object)
            }
        }
        return .object(["ok": .bool(true)])
    }

    private func handleSetProp(params: JSONValue?) throws -> JSONValue {
        guard let dict = params?.asObject,
              let id = dict["id"]?.asString,
              let name = dict["name"]?.asString else {
            throw WidgetError.badRequest("widget.setProp requires id and name")
        }
        let entry = try lookup(id)
        try entry.factory.setProperty(name, value: dict["value"] ?? .null, on: entry.object)
        return .object(["ok": .bool(true)])
    }

    private func handleGetProp(params: JSONValue?) throws -> JSONValue {
        guard let dict = params?.asObject,
              let id = dict["id"]?.asString,
              let name = dict["name"]?.asString else {
            throw WidgetError.badRequest("widget.getProp requires id and name")
        }
        let entry = try lookup(id)
        let value = try entry.factory.getProperty(name, on: entry.object)
        return .object(["value": value])
    }

    private func handleAddChild(params: JSONValue?) throws -> JSONValue {
        guard let dict = params?.asObject,
              let parentId = dict["parentId"]?.asString,
              let childId = dict["childId"]?.asString,
              let role = dict["role"]?.asString else {
            throw WidgetError.badRequest("widget.addChild requires parentId, childId, role")
        }
        let parent = try lookup(parentId)
        let child = try lookup(childId)
        try parent.factory.addChild(child.object, role: role, to: parent.object)
        return .object(["ok": .bool(true)])
    }

    private func handleInvoke(params: JSONValue?) throws -> JSONValue {
        guard let dict = params?.asObject,
              let id = dict["id"]?.asString,
              let selector = dict["selector"]?.asString else {
            throw WidgetError.badRequest("widget.invoke requires id and selector")
        }
        let args = dict["args"]?.asArray ?? []
        let entry = try lookup(id)
        let result = try entry.factory.invoke(selector, args: args, on: entry.object)
        return .object(["result": result])
    }

    private func handleSubscribe(params: JSONValue?) throws -> JSONValue {
        guard let dict = params?.asObject,
              let id = dict["id"]?.asString,
              let event = dict["event"]?.asString else {
            throw WidgetError.badRequest("widget.subscribe requires id and event")
        }
        let entry = try lookup(id)
        let widgetId = id
        try entry.factory.subscribe(event, on: entry.object, widgetId: widgetId) { [weak self] eventName, payload in
            guard let self else { return }
            let params: JSONValue = .object([
                "id": .string(widgetId),
                "event": .string(eventName),
                "payload": payload
            ])
            self.eventEmitter?(JSONRPCNotification(method: "event", params: params))
        }
        return .object(["ok": .bool(true)])
    }

    private func handleDestroy(params: JSONValue?) throws -> JSONValue {
        guard let dict = params?.asObject,
              let id = dict["id"]?.asString else {
            throw WidgetError.badRequest("widget.destroy requires id")
        }
        guard let entry = registry.removeValue(forKey: id) else {
            throw WidgetError.unknownWidget(id)
        }
        entry.factory.tearDown(entry.object)
        return .object(["ok": .bool(true)])
    }

    // MARK: registry

    private func lookup(_ id: String) throws -> Entry {
        guard let entry = registry[id] else {
            throw WidgetError.unknownWidget(id)
        }
        return entry
    }

    func register(factory: WidgetFactory) {
        factories[factory.typeName] = factory
    }

    private func registerDefaults() {
        register(factory: WindowFactory())
        register(factory: ViewFactory())
        register(factory: ButtonFactory())
        register(factory: TextFieldFactory())
        register(factory: ScrollViewFactory())
        register(factory: SplitViewFactory())
        register(factory: TableViewFactory())
        register(factory: TextViewFactory())
        register(factory: OutlineViewFactory())
        register(factory: SearchFieldFactory())
        register(factory: SegmentedControlFactory())
        register(factory: TabViewFactory())
    }
}
