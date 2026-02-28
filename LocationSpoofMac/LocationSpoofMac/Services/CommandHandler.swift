import Foundation

@Observable
final class CommandHandler {
    var isSpoofing = false
    var currentLat: Double?
    var currentLng: Double?
    var lastError: String?
    var deviceName: String = ""

    private let deviceService: DeviceService
    let server: BonjourServer

    init(deviceService: DeviceService = DeviceService(), server: BonjourServer = BonjourServer()) {
        self.deviceService = deviceService
        self.server = server

        self.server.onMessageReceived = { [weak self] message in
            guard let self = self else { return }
            Task { await self.handle(message) }
        }
    }

    var isReady: Bool {
        deviceService.isAvailable
    }

    func start() {
        server.start()
    }

    func stop() {
        server.stop()
    }

    @MainActor
    private func handle(_ message: SpoofMessage) async {
        lastError = nil

        switch message.action {
        case .set:
            guard let lat = message.lat, let lng = message.lng else {
                server.send(response: .error("Missing lat/lng"))
                return
            }
            do {
                try await deviceService.setLocation(lat: lat, lng: lng)
                isSpoofing = true
                currentLat = lat
                currentLng = lng
                server.send(response: .ok(spoofing: true, lat: lat, lng: lng))
            } catch {
                lastError = error.localizedDescription
                server.send(response: .error(error.localizedDescription))
            }

        case .clear:
            do {
                try await deviceService.clearLocation()
                isSpoofing = false
                currentLat = nil
                currentLng = nil
                server.send(response: .ok(spoofing: false))
            } catch {
                lastError = error.localizedDescription
                server.send(response: .error(error.localizedDescription))
            }

        case .ping:
            server.send(response: .pong(device: deviceName, spoofing: isSpoofing))
        }
    }

    @MainActor
    func clearFromUI() async {
        do {
            try await deviceService.clearLocation()
            isSpoofing = false
            currentLat = nil
            currentLng = nil
            server.send(response: .ok(spoofing: false))
        } catch {
            lastError = error.localizedDescription
        }
    }
}
