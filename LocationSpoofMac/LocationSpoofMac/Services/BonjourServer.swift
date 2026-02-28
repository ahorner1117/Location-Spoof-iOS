import Foundation
import Network

final class BonjourServer: ObservableObject {
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private let queue = DispatchQueue(label: "BonjourServer")
    private var receiveBuffer = Data()

    @Published var isClientConnected = false

    var onMessageReceived: ((SpoofMessage) -> Void)?

    func start() {
        do {
            listener = try NWListener(using: .tcp)
        } catch {
            print("Failed to create NWListener: \(error)")
            return
        }

        listener?.service = NWListener.Service(name: nil, type: "_locspoof._tcp")

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = self?.listener?.port {
                    print("Server ready on port \(port)")
                }
            case .failed(let error):
                print("Listener failed: \(error)")
                self?.listener?.cancel()
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] newConnection in
            guard let self = self else { return }
            if self.activeConnection != nil {
                newConnection.cancel()
                return
            }
            self.setupConnection(newConnection)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        activeConnection?.cancel()
        activeConnection = nil
        listener?.cancel()
        listener = nil
    }

    private func setupConnection(_ connection: NWConnection) {
        activeConnection = connection
        receiveBuffer = Data()

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                DispatchQueue.main.async { self?.isClientConnected = true }
                self?.startReceiving(on: connection)
            case .failed, .cancelled:
                self?.cleanupConnection(connection)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func cleanupConnection(_ connection: NWConnection) {
        if activeConnection === connection {
            activeConnection = nil
            receiveBuffer = Data()
            DispatchQueue.main.async { self.isClientConnected = false }
        }
    }

    private func startReceiving(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBuffer()
            }
            if isComplete {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }
            self.startReceiving(on: connection)
        }
    }

    private func processBuffer() {
        let newline = UInt8(ascii: "\n")
        while let idx = receiveBuffer.firstIndex(of: newline) {
            let lineData = receiveBuffer[receiveBuffer.startIndex..<idx]
            receiveBuffer = Data(receiveBuffer[(idx + 1)...])

            guard !lineData.isEmpty,
                  let msg = try? JSONDecoder().decode(SpoofMessage.self, from: lineData)
            else { continue }

            DispatchQueue.main.async {
                self.onMessageReceived?(msg)
            }
        }
    }

    func send(response: SpoofResponse) {
        guard let connection = activeConnection,
              let data = try? JSONEncoder().encode(response),
              var payload = String(data: data, encoding: .utf8)
        else { return }

        payload.append("\n")
        connection.send(content: Data(payload.utf8), completion: .contentProcessed { error in
            if let error = error {
                print("Send error: \(error)")
            }
        })
    }
}
