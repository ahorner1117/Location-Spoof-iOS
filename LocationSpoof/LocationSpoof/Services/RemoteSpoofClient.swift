import Foundation

/// HTTP client for the Mac's Remote API. Use when the iOS app is not on the same network
/// (e.g. connected via Tailscale or Cloudflare Tunnel).
final class RemoteSpoofClient: ObservableObject {
    private let baseURL: URL
    private let session: URLSession

    @Published private(set) var isConnected = false
    @Published var discoveredServiceName: String? = "Remote Mac"

    var onResponseReceived: ((SpoofResponse) -> Void)?

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    func startBrowsing() {
        // No discovery; verify connection with a ping
        performPing()
    }

    func stopBrowsing() {
        isConnected = false
    }

    func send(_ message: SpoofMessage) {
        switch message.action {
        case .set:
            if let lat = message.lat, let lng = message.lng {
                performSet(lat: lat, lng: lng)
            }
        case .clear:
            performClear()
        case .ping:
            performPing()
        }
    }

    private func performPing() {
        let url = baseURL.appendingPathComponent("status")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        session.dataTask(with: request) { [weak self] data, response, error in
            self?.handleResponse(data: data, response: response, error: error) { resp in
                DispatchQueue.main.async {
                    self?.isConnected = true
                    self?.onResponseReceived?(resp)
                }
            }
        }.resume()
    }

    private func performSet(lat: Double, lng: Double) {
        let url = baseURL.appendingPathComponent("set")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["lat": lat, "lng": lng])

        session.dataTask(with: request) { [weak self] data, response, error in
            self?.handleResponse(data: data, response: response, error: error) { resp in
                DispatchQueue.main.async {
                    self?.isConnected = resp.status == "ok"
                    self?.onResponseReceived?(resp)
                }
            }
        }.resume()
    }

    private func performClear() {
        let url = baseURL.appendingPathComponent("clear")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        session.dataTask(with: request) { [weak self] data, response, error in
            self?.handleResponse(data: data, response: response, error: error) { resp in
                DispatchQueue.main.async {
                    self?.isConnected = resp.status == "ok"
                    self?.onResponseReceived?(resp)
                }
            }
        }.resume()
    }

    private func handleResponse(data: Data?, response: URLResponse?, error: Error?, completion: (SpoofResponse) -> Void) {
        if let error = error {
            DispatchQueue.main.async { [weak self] in self?.isConnected = false }
            completion(.error(error.localizedDescription))
            return
        }

        guard let data = data,
              let resp = try? JSONDecoder().decode(SpoofResponse.self, from: data) else {
            completion(.error("Invalid response from Mac"))
            return
        }
        completion(resp)
    }
}
