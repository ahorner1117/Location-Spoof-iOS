import Foundation
import Combine

final class SpoofService: ObservableObject {
    let client = BonjourClient()

    @Published var isSpoofing = false
    @Published var spoofedLat: Double?
    @Published var spoofedLng: Double?
    @Published var deviceName: String?
    @Published var lastError: String?
    @Published var isConnected = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        client.onResponseReceived = { [weak self] response in
            self?.handleResponse(response)
        }

        client.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$isConnected)
    }

    func start() {
        client.startBrowsing()
    }

    func stop() {
        client.stopBrowsing()
    }

    func setLocation(lat: Double, lng: Double) {
        lastError = nil
        client.send(.set(lat: lat, lng: lng))
    }

    func clearLocation() {
        lastError = nil
        client.send(.clear)
    }

    func ping() {
        client.send(.ping)
    }

    private func handleResponse(_ response: SpoofResponse) {
        switch response.status {
        case "ok":
            isSpoofing = response.spoofing ?? false
            spoofedLat = response.lat
            spoofedLng = response.lng
            lastError = nil
        case "error":
            lastError = response.message ?? "Unknown error"
        case "pong":
            deviceName = response.device
            isSpoofing = response.spoofing ?? false
        default:
            break
        }
    }
}
