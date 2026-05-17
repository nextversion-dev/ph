import Foundation

enum JSONRPCError: Error, CustomStringConvertible {
    case transport(String)
    case decoding(String)
    case remote(code: Int, message: String)
    case cancelled

    var description: String {
        switch self {
        case .transport(let m): return "transport error: \(m)"
        case .decoding(let m): return "decoding error: \(m)"
        case .remote(let c, let m): return "remote error \(c): \(m)"
        case .cancelled: return "request cancelled"
        }
    }
}

struct JSONRPCRequest: Encodable {
    let jsonrpc: String
    let id: Int
    let method: String
    let params: [String: AnyEncodable]?

    init(id: Int, method: String, params: [String: AnyEncodable]? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

struct JSONRPCError_Response: Decodable {
    let code: Int
    let message: String
}

struct JSONRPCResponse: Decodable {
    let jsonrpc: String?
    let id: Int?
    let result: AnyDecodable?
    let error: JSONRPCError_Response?
}

struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) {
        _encode = value.encode
    }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}

struct AnyDecodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let b = try? container.decode(Bool.self) {
            value = b
        } else if let i = try? container.decode(Int.self) {
            value = i
        } else if let d = try? container.decode(Double.self) {
            value = d
        } else if let s = try? container.decode(String.self) {
            value = s
        } else if let arr = try? container.decode([AnyDecodable].self) {
            value = arr.map(\.value)
        } else if let obj = try? container.decode([String: AnyDecodable].self) {
            value = obj.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON type")
        }
    }
}
