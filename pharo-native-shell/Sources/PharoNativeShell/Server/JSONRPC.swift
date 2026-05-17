import Foundation

/// Generic JSON-RPC types used by both directions of the widget protocol.
///
/// A line on the wire is either:
///   - a request   (has `id` and `method`) -> the shell answers with a response
///   - a response  (has `id`, plus `result` xor `error`)
///   - a notification (has `method`, no `id`) -> no response expected
///
/// On the shell we only receive requests (Pharo -> shell) and send back
/// responses; we also push events as notifications. So this file is mostly
/// concerned with parsing requests and emitting both responses and
/// notifications.

enum JSONValue: Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    var asString: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var asInt: Int? {
        if case .int(let i) = self { return i }
        if case .double(let d) = self { return Int(d) }
        return nil
    }

    var asDouble: Double? {
        if case .double(let d) = self { return d }
        if case .int(let i) = self { return Double(i) }
        return nil
    }

    var asBool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var asObject: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    var asArray: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
}

struct JSONRPCRequest: Decodable {
    let jsonrpc: String?
    let id: JSONValue?           // can be int or string per the spec; we keep both shapes
    let method: String
    let params: JSONValue?
}

struct JSONRPCErrorPayload: Encodable {
    let code: Int
    let message: String
}

struct JSONRPCResponse: Encodable {
    let jsonrpc: String
    let id: JSONValue
    let result: JSONValue?
    let error: JSONRPCErrorPayload?

    static func success(id: JSONValue, result: JSONValue) -> JSONRPCResponse {
        return JSONRPCResponse(jsonrpc: "2.0", id: id, result: result, error: nil)
    }

    static func failure(id: JSONValue, code: Int, message: String) -> JSONRPCResponse {
        return JSONRPCResponse(jsonrpc: "2.0", id: id, result: nil, error: JSONRPCErrorPayload(code: code, message: message))
    }
}

struct JSONRPCNotification: Encodable {
    let jsonrpc: String
    let method: String
    let params: JSONValue?

    init(method: String, params: JSONValue?) {
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
    }
}

enum WidgetError: Error, LocalizedError {
    case badRequest(String)
    case unknownWidget(String)
    case unknownType(String)
    case unknownEvent(String)
    case unknownSelector(String)
    case unknownProperty(String)
    case internalError(String)

    var errorDescription: String? {
        switch self {
        case .badRequest(let m): return "bad request: \(m)"
        case .unknownWidget(let id): return "unknown widget: \(id)"
        case .unknownType(let t): return "unknown widget type: \(t)"
        case .unknownEvent(let e): return "unknown event: \(e)"
        case .unknownSelector(let s): return "unknown selector: \(s)"
        case .unknownProperty(let p): return "unknown property: \(p)"
        case .internalError(let m): return "internal error: \(m)"
        }
    }

    var code: Int {
        switch self {
        case .badRequest: return -32602
        case .unknownWidget: return -32001
        case .unknownType: return -32002
        case .unknownEvent: return -32003
        case .unknownSelector: return -32004
        case .unknownProperty: return -32005
        case .internalError: return -32603
        }
    }
}
