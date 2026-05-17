import Foundation
import Network

/// Async JSON-RPC client over a single TCP connection.
///
/// Newline-delimited JSON: each request is encoded as one JSON line and
/// each response arrives as one JSON line. Concurrent requests are
/// supported via id-based correlation.
actor BridgeClient {
    private let host: String
    private let port: UInt16
    private var connection: NWConnection?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var nextId: Int = 1
    private var pending: [Int: CheckedContinuation<Any, Error>] = [:]
    private var readBuffer = Data()
    private var didConnect = false

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    deinit {
        connection?.cancel()
    }

    // MARK: typed API

    func listPackages() async throws -> [PackageInfo] {
        let result = try await call("system.listPackages", params: [:])
        return parseObjectArray(result) { dict in
            PackageInfo(
                name: stringValue(dict["name"]) ?? "",
                classCount: intValue(dict["classCount"]) ?? 0
            )
        }
    }

    func listClasses(package: String) async throws -> [ClassInfo] {
        let result = try await call("package.listClasses", params: [
            "package": AnyEncodable(package)
        ])
        return parseObjectArray(result) { dict in
            ClassInfo(
                name: stringValue(dict["name"]) ?? "",
                side: stringValue(dict["side"]) ?? "instance",
                superclassName: stringValue(dict["superclass"]) ?? ""
            )
        }
    }

    func listProtocols(class className: String, side: String) async throws -> [ProtocolInfo] {
        let result = try await call("class.listProtocols", params: [
            "class": AnyEncodable(className),
            "side": AnyEncodable(side)
        ])
        return parseObjectArray(result) { dict in
            ProtocolInfo(
                name: stringValue(dict["name"]) ?? "",
                methodCount: intValue(dict["methodCount"]) ?? 0
            )
        }
    }

    func listMethods(class className: String, side: String, protocolName: String?) async throws -> [String] {
        var params: [String: AnyEncodable] = [
            "class": AnyEncodable(className),
            "side": AnyEncodable(side)
        ]
        if let protocolName {
            params["protocol"] = AnyEncodable(protocolName)
        }
        let result = try await call("protocol.listMethods", params: params)
        guard let arr = result as? [Any] else { return [] }
        return arr.compactMap { stringValue($0) }
    }

    func getSource(class className: String, side: String, selector: String) async throws -> MethodSource {
        let result = try await call("method.getSource", params: [
            "class": AnyEncodable(className),
            "side": AnyEncodable(side),
            "selector": AnyEncodable(selector)
        ])
        guard let dict = result as? [String: Any] else {
            throw JSONRPCError.decoding("method.getSource: expected object")
        }
        return MethodSource(
            source: stringValue(dict["source"]) ?? "",
            category: stringValue(dict["category"]) ?? "",
            author: stringValue(dict["author"]) ?? "",
            timestamp: stringValue(dict["timestamp"]) ?? ""
        )
    }

    // MARK: low-level call

    private func call(_ method: String, params: [String: AnyEncodable]) async throws -> Any {
        try await ensureConnected()
        let id = nextId
        nextId += 1
        let request = JSONRPCRequest(id: id, method: method, params: params)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let body = try encoder.encode(request)
        var line = body
        line.append(0x0A) // LF
        do {
            return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Any, Error>) in
                pending[id] = cont
                connection?.send(content: line, completion: .contentProcessed { sendError in
                    if let sendError {
                        Task { await self.failPending(id: id, error: .transport(sendError.localizedDescription)) }
                    }
                })
            }
        } catch {
            pending.removeValue(forKey: id)
            throw error
        }
    }

    // MARK: connect / read loop

    private func ensureConnected() async throws {
        if didConnect, connection?.state == .ready { return }
        if connection == nil {
            connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port) ?? .any,
                using: .tcp
            )
        }
        guard let connection else { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connectContinuation = cont
            connection.stateUpdateHandler = { [weak self] state in
                Task { await self?.handleStateUpdate(state) }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
        didConnect = true
        startReceiving()
    }

    private func handleStateUpdate(_ state: NWConnection.State) {
        switch state {
        case .ready:
            connectContinuation?.resume()
            connectContinuation = nil
        case .failed(let error), .waiting(let error):
            connectContinuation?.resume(throwing: JSONRPCError.transport(error.localizedDescription))
            connectContinuation = nil
            failAllPending(error: .transport(error.localizedDescription))
        case .cancelled:
            connectContinuation?.resume(throwing: JSONRPCError.cancelled)
            connectContinuation = nil
            failAllPending(error: .cancelled)
        default:
            break
        }
    }

    private func startReceiving() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { await self.handleReceive(data: data, isComplete: isComplete, error: error) }
        }
    }

    private func handleReceive(data: Data?, isComplete: Bool, error: NWError?) {
        if let error {
            failAllPending(error: .transport(error.localizedDescription))
            return
        }
        if let data, !data.isEmpty {
            readBuffer.append(data)
            consumeLines()
        }
        if isComplete {
            failAllPending(error: .transport("connection closed"))
            return
        }
        if connection?.state == .ready {
            startReceiving()
        }
    }

    private func consumeLines() {
        let lf: UInt8 = 0x0A
        while let idx = readBuffer.firstIndex(of: lf) {
            let lineData = readBuffer.subdata(in: 0..<idx)
            readBuffer.removeSubrange(0...idx)
            handleLine(lineData)
        }
    }

    private func handleLine(_ data: Data) {
        let decoder = JSONDecoder()
        let resp: JSONRPCResponse
        do {
            resp = try decoder.decode(JSONRPCResponse.self, from: data)
        } catch {
            let str = String(data: data, encoding: .utf8) ?? "<binary>"
            NSLog("BridgeClient: failed to decode response: %@ (%@)", error.localizedDescription, str)
            return
        }
        guard let id = resp.id else { return }
        guard let cont = pending.removeValue(forKey: id) else { return }
        if let err = resp.error {
            cont.resume(throwing: JSONRPCError.remote(code: err.code, message: err.message))
        } else {
            cont.resume(returning: resp.result?.value ?? NSNull())
        }
    }

    private func failPending(id: Int, error: JSONRPCError) {
        if let cont = pending.removeValue(forKey: id) {
            cont.resume(throwing: error)
        }
    }

    private func failAllPending(error: JSONRPCError) {
        for cont in pending.values {
            cont.resume(throwing: error)
        }
        pending.removeAll()
    }

    // MARK: helpers

    private nonisolated func parseObjectArray<T>(_ raw: Any, transform: ([String: Any]) -> T) -> [T] {
        guard let arr = raw as? [Any] else { return [] }
        return arr.compactMap { item -> T? in
            if let dict = item as? [String: Any] {
                return transform(dict)
            }
            return nil
        }
    }

    private nonisolated func stringValue(_ raw: Any?) -> String? {
        if let s = raw as? String { return s }
        return nil
    }

    private nonisolated func intValue(_ raw: Any?) -> Int? {
        if let i = raw as? Int { return i }
        if let d = raw as? Double { return Int(d) }
        return nil
    }
}

struct PackageInfo: Hashable {
    let name: String
    let classCount: Int
}

struct ClassInfo: Hashable {
    let name: String
    let side: String   // "instance" or "class"
    let superclassName: String

    var displayName: String {
        side == "class" ? "\(name) class" : name
    }
}

struct ProtocolInfo: Hashable {
    let name: String
    let methodCount: Int
}

struct MethodSource: Hashable {
    let source: String
    let category: String
    let author: String
    let timestamp: String
}
