import Foundation
import Network

/// Minimal HTTP server that exposes the same set/clear/status actions as Bonjour
/// so the iOS app can control location spoofing over the internet (e.g. via Tailscale or Cloudflare Tunnel).
@Observable
final class HTTPServer {
    private var listener: NWListener?
    private let port: UInt16
    private let queue = DispatchQueue(label: "HTTPServer")
    private weak var handler: CommandHandler?

    private(set) var isRunning = false
    private(set) var boundPort: UInt16?

    static let defaultPort: UInt16 = 8765

    init(port: UInt16 = HTTPServer.defaultPort) {
        self.port = port
    }

    func start(handler: CommandHandler) {
        self.handler = handler
        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            print("HTTPServer: failed to create listener: \(error)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = self?.listener?.port?.rawValue {
                    DispatchQueue.main.async {
                        self?.isRunning = true
                        self?.boundPort = port
                    }
                    print("HTTPServer: listening on port \(port)")
                }
            case .failed(let error):
                print("HTTPServer: failed \(error)")
                DispatchQueue.main.async { self?.isRunning = false; self?.boundPort = nil }
            case .cancelled:
                DispatchQueue.main.async { self?.isRunning = false; self?.boundPort = nil }
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isRunning = false
            self.boundPort = nil
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.readRequest(connection: connection)
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func readRequest(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                connection.cancel()
                return
            }
            guard let data = data, !data.isEmpty else {
                if isComplete { connection.cancel() }
                return
            }

            guard let request = String(data: data, encoding: .utf8) else {
                self.sendResponse(connection: connection, status: "400 Bad Request", body: "Bad request")
                return
            }

            let (method, path, body) = self.parseRequest(request)
            self.dispatch(method: method, path: path, body: body) { response in
                self.sendResponse(connection: connection, status: "200 OK", body: response)
                connection.cancel()
            }
        }
    }

    private func parseRequest(_ raw: String) -> (method: String, path: String, body: String?) {
        var method = "GET"
        var path = "/"
        var body: String?

        let lines = raw.components(separatedBy: "\r\n")
        if let first = lines.first {
            let parts = first.split(separator: " ", maxSplits: 2)
            if parts.count >= 2 {
                method = String(parts[0]).uppercased()
                path = String(parts[1]).split(separator: "?").first.map(String.init) ?? "/"
            }
        }

        if let idx = lines.firstIndex(where: { $0.isEmpty }),
           idx + 1 < lines.count {
            body = lines[(idx + 1)...].joined(separator: "\r\n")
        }

        return (method, path, body)
    }

    private func dispatch(method: String, path: String, body: String?, completion: @escaping (String) -> Void) {
        var pathNorm = path.hasSuffix("/") ? String(path.dropLast()) : path
        if pathNorm.isEmpty { pathNorm = "/" }

        switch (method, pathNorm) {
        case ("GET", "/"), ("GET", "/status"):
            guard let handler = handler else {
                completion(encodeJSON(["status": "error", "message": "Not ready"]))
                return
            }
            let response = handler.statusResponse()
            completion(encodeResponse(response))

        case ("POST", "/set"):
            guard let handler = handler else {
                completion(encodeJSON(["status": "error", "message": "Not ready"]))
                return
            }
            guard let body = body,
                  let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lat = json["lat"] as? Double,
                  let lng = json["lng"] as? Double else {
                completion(encodeJSON(["status": "error", "message": "Missing lat/lng in JSON body"]))
                return
            }
            var responseBody: String?
            let sem = DispatchSemaphore(value: 0)
            Task { @MainActor in
                let response = await handler.setLocationAPI(lat: lat, lng: lng)
                responseBody = encodeResponse(response)
                sem.signal()
            }
            sem.wait()
            completion(responseBody ?? "{}")

        case ("POST", "/clear"):
            guard let handler = handler else {
                completion(encodeJSON(["status": "error", "message": "Not ready"]))
                return
            }
            var responseBody: String?
            let sem = DispatchSemaphore(value: 0)
            Task { @MainActor in
                let response = await handler.clearLocationAPI()
                responseBody = encodeResponse(response)
                sem.signal()
            }
            sem.wait()
            completion(responseBody ?? "{}")

        default:
            completion(encodeJSON([
                "status": "error",
                "message": "Not found. Use GET /status, POST /set {\"lat\",\"lng\"}, POST /clear"
            ]))
        }
    }

    private func encodeResponse(_ r: SpoofResponse) -> String {
        var dict: [String: Any] = ["status": r.status]
        if let s = r.spoofing { dict["spoofing"] = s }
        if let lat = r.lat { dict["lat"] = lat }
        if let lng = r.lng { dict["lng"] = lng }
        if let m = r.message { dict["message"] = m }
        if let d = r.device { dict["device"] = d }
        return encodeJSON(dict)
    }

    private func encodeJSON(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"status\":\"error\",\"message\":\"Encoding error\"}"
        }
        return str
    }

    private func sendResponse(connection: NWConnection, status: String, body: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
    }
}
