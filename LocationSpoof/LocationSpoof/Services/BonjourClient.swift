import Foundation
import Network

final class BonjourClient: ObservableObject {
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "BonjourClient")
    private var receiveBuffer = Data()
    private var reconnectTimer: DispatchSourceTimer?
    private var shouldReconnect = false

    @Published var isConnected = false
    @Published var discoveredServiceName: String?

    var onResponseReceived: ((SpoofResponse) -> Void)?

    func startBrowsing() {
        shouldReconnect = true

        browser = NWBrowser(
            for: .bonjour(type: "_locspoof._tcp", domain: nil),
            using: NWParameters()
        )

        browser?.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("Browser failed: \(error)")
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            for result in results {
                if case .service(let name, _, _, _) = result.endpoint {
                    DispatchQueue.main.async {
                        self.discoveredServiceName = name
                    }
                    if self.connection == nil {
                        self.connect(to: result.endpoint)
                    }
                    break
                }
            }
        }

        browser?.start(queue: queue)
    }

    func stopBrowsing() {
        shouldReconnect = false
        reconnectTimer?.cancel()
        reconnectTimer = nil
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
    }

    private func connect(to endpoint: NWEndpoint) {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveInterval = 5
        let params = NWParameters(tls: nil, tcp: tcp)

        let conn = NWConnection(to: endpoint, using: params)
        connection = conn
        receiveBuffer = Data()

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async { self.isConnected = true }
                self.startReceiving(on: conn)
            case .failed, .cancelled:
                self.handleDisconnect()
            default:
                break
            }
        }

        conn.start(queue: queue)
    }

    private func handleDisconnect() {
        connection = nil
        receiveBuffer = Data()
        DispatchQueue.main.async { self.isConnected = false }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        reconnectTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.connection == nil else { return }
            self.browser?.cancel()
            self.browser = nil
            self.startBrowsing()
        }
        timer.resume()
        reconnectTimer = timer
    }

    private func startReceiving(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBuffer()
            }
            if isComplete { connection.cancel(); return }
            if error != nil { connection.cancel(); return }
            self.startReceiving(on: connection)
        }
    }

    private func processBuffer() {
        let newline = UInt8(ascii: "\n")
        while let idx = receiveBuffer.firstIndex(of: newline) {
            let lineData = receiveBuffer[receiveBuffer.startIndex..<idx]
            receiveBuffer = Data(receiveBuffer[(idx + 1)...])

            guard !lineData.isEmpty,
                  let resp = try? JSONDecoder().decode(SpoofResponse.self, from: lineData)
            else { continue }

            DispatchQueue.main.async {
                self.onResponseReceived?(resp)
            }
        }
    }

    func send(_ message: SpoofMessage) {
        guard let connection = connection,
              let data = try? JSONEncoder().encode(message),
              var payload = String(data: data, encoding: .utf8)
        else { return }

        payload.append("\n")
        connection.send(content: Data(payload.utf8), completion: .contentProcessed { _ in })
    }
}
