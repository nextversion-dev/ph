import Foundation
import Network
import AppKit

/// TCP listener that accepts a single Pharo client connection at a time,
/// reads newline-delimited JSON requests, dispatches them to the WidgetHost
/// on the main thread, and writes responses and event notifications back.
///
/// v1 supports a single active connection. If a second client connects we
/// reset the host and replace the connection.
final class WidgetServer {
    private let port: UInt16
    private var listener: NWListener?
    private var connection: NWConnection?
    private var readBuffer = Data()
    private var host: WidgetHost
    private let queue = DispatchQueue(label: "org.pharo.native-shell.server")

    init(port: UInt16) {
        self.port = port
        self.host = WidgetHost()
    }

    static let portFilePath = "/tmp/pharo-native-shell.port"

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Bind only to loopback. Pharo connects to 127.0.0.1.
        params.requiredInterfaceType = .loopback

        let nwPort = NWEndpoint.Port(rawValue: port)!
        let listener = try NWListener(using: params, on: nwPort)
        self.listener = listener
        host.eventEmitter = { [weak self] notification in
            self?.send(notification: notification)
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection: connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            NSLog("PharoNativeShell: listener state %@", String(describing: state))
            if case .ready = state {
                self?.writePortFile()
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        connection?.cancel()
        listener?.cancel()
        // Best-effort cleanup so a stale port file doesn't make the next
        // Pharo image try to connect to a dead listener.
        try? FileManager.default.removeItem(atPath: WidgetServer.portFilePath)
    }

    private func writePortFile() {
        // Publish the actual listening port so a Pharo image can find us
        // even when launched separately (or auto-restored by macOS).
        do {
            try String(port).write(toFile: WidgetServer.portFilePath, atomically: true, encoding: .utf8)
        } catch {
            NSLog("PharoNativeShell: failed to write port file: %@", error.localizedDescription)
        }
    }

    // MARK: connection lifecycle

    private func accept(connection newConnection: NWConnection) {
        if let existing = connection {
            NSLog("PharoNativeShell: replacing existing connection")
            existing.cancel()
            DispatchQueue.main.async { [weak self] in
                self?.host.reset()
            }
        }
        self.connection = newConnection
        self.readBuffer = Data()
        newConnection.stateUpdateHandler = { [weak self] state in
            NSLog("PharoNativeShell: connection state %@", String(describing: state))
            if case .failed = state { self?.connection = nil }
            if case .cancelled = state { self?.connection = nil }
        }
        newConnection.start(queue: queue)
        scheduleReceive()
    }

    private func scheduleReceive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                NSLog("PharoNativeShell: receive error %@", error.localizedDescription)
                return
            }
            if let data, !data.isEmpty {
                self.readBuffer.append(data)
                self.drainLines()
            }
            if isComplete {
                NSLog("PharoNativeShell: connection closed by peer")
                self.connection?.cancel()
                self.connection = nil
                DispatchQueue.main.async { [weak self] in
                    self?.host.reset()
                }
                return
            }
            self.scheduleReceive()
        }
    }

    private func drainLines() {
        let lf: UInt8 = 0x0A
        while let idx = readBuffer.firstIndex(of: lf) {
            let lineData = readBuffer.subdata(in: 0..<idx)
            readBuffer.removeSubrange(0...idx)
            handleLine(lineData)
        }
    }

    private func handleLine(_ data: Data) {
        let decoder = JSONDecoder()
        let request: JSONRPCRequest
        do {
            request = try decoder.decode(JSONRPCRequest.self, from: data)
        } catch {
            NSLog("PharoNativeShell: decode error %@", error.localizedDescription)
            return
        }
        let id = request.id ?? .null
        // AppKit work must happen on the main thread; hop there for the
        // entire dispatch so widget mutations are linearizable.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            do {
                let result = try self.host.handle(method: request.method, params: request.params)
                self.send(response: .success(id: id, result: result))
            } catch let widgetError as WidgetError {
                self.send(response: .failure(id: id, code: widgetError.code, message: widgetError.errorDescription ?? "error"))
            } catch {
                self.send(response: .failure(id: id, code: -32603, message: error.localizedDescription))
            }
        }
    }

    // MARK: send

    private func send(response: JSONRPCResponse) {
        guard let connection else { return }
        do {
            let body = try JSONEncoder().encode(response)
            var line = body
            line.append(0x0A)
            connection.send(content: line, completion: .contentProcessed { _ in })
        } catch {
            NSLog("PharoNativeShell: encode response error %@", error.localizedDescription)
        }
    }

    private func send(notification: JSONRPCNotification) {
        guard let connection else { return }
        do {
            let body = try JSONEncoder().encode(notification)
            var line = body
            line.append(0x0A)
            connection.send(content: line, completion: .contentProcessed { _ in })
        } catch {
            NSLog("PharoNativeShell: encode notification error %@", error.localizedDescription)
        }
    }
}
