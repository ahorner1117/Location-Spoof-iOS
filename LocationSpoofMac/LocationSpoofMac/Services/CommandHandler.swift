import Foundation

@Observable
final class CommandHandler {
    var isSpoofing = false
    var currentLat: Double?
    var currentLng: Double?
    var lastError: String?
    var deviceName: String = ""

    /// Whether the user *intends* to be spoofing. This persists across
    /// connection drops and app relaunches. `isSpoofing` reflects whether the
    /// device-side spoof was actually applied on the most recent attempt.
    private(set) var desiredSpoofing = false

    private let deviceService: DeviceService
    let server: BonjourServer

    /// Re-applies the simulated location on a timer so the spoof survives
    /// transient drops of the pymobiledevice3 / RemoteXPC session (the spoof is
    /// session-bound and is lost the moment that session dies).
    private var keepaliveTimer: Timer?
    private let keepaliveInterval: TimeInterval = 30

    private enum Keys {
        static let desired = "mac.desiredSpoofing"
        static let lat = "mac.spoofLat"
        static let lng = "mac.spoofLng"
    }

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

    @MainActor
    func stop() {
        stopKeepalive()
        server.stop()
    }

    // MARK: - Core apply / clear (single source of truth)

    @MainActor
    private func applySet(lat: Double, lng: Double) async -> SpoofResponse {
        lastError = nil
        desiredSpoofing = true
        currentLat = lat
        currentLng = lng
        persistState()
        startKeepalive()
        do {
            try await deviceService.setLocation(lat: lat, lng: lng)
            isSpoofing = true
            return .ok(spoofing: true, lat: lat, lng: lng)
        } catch {
            // Keep the intent alive: the keepalive loop will retry, so the spoof
            // re-applies automatically once the device is reachable again.
            isSpoofing = false
            lastError = error.localizedDescription
            return .error(error.localizedDescription)
        }
    }

    @MainActor
    private func applyClear() async -> SpoofResponse {
        lastError = nil
        desiredSpoofing = false
        persistState()
        stopKeepalive()
        do {
            try await deviceService.clearLocation()
            isSpoofing = false
            currentLat = nil
            currentLng = nil
            return .ok(spoofing: false)
        } catch {
            isSpoofing = false
            currentLat = nil
            currentLng = nil
            lastError = error.localizedDescription
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Bonjour message handling

    @MainActor
    private func handle(_ message: SpoofMessage) async {
        switch message.action {
        case .set:
            guard let lat = message.lat, let lng = message.lng else {
                server.send(response: .error("Missing lat/lng"))
                return
            }
            let response = await applySet(lat: lat, lng: lng)
            server.send(response: response)

        case .clear:
            let response = await applyClear()
            server.send(response: response)

        case .ping:
            server.send(response: statusResponse())
        }
    }

    /// Manual clear from the macOS menu bar UI.
    @MainActor
    func clearFromUI() async {
        let response = await applyClear()
        server.send(response: response)
    }

    // MARK: - HTTP API (returns response for remote clients)

    @MainActor
    func setLocationAPI(lat: Double, lng: Double) async -> SpoofResponse {
        let response = await applySet(lat: lat, lng: lng)
        server.send(response: response)
        return response
    }

    @MainActor
    func clearLocationAPI() async -> SpoofResponse {
        let response = await applyClear()
        server.send(response: response)
        return response
    }

    /// Current status, including the coordinates so a reconnecting remote client
    /// can restore its map pin and decide whether it needs to re-assert.
    func statusResponse() -> SpoofResponse {
        .pong(device: deviceName, spoofing: isSpoofing, lat: currentLat, lng: currentLng)
    }

    // MARK: - Keepalive

    @MainActor
    private func startKeepalive() {
        keepaliveTimer?.invalidate()
        let timer = Timer(timeInterval: keepaliveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.keepaliveTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        keepaliveTimer = timer
    }

    @MainActor
    private func stopKeepalive() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
    }

    @MainActor
    private func keepaliveTick() async {
        guard desiredSpoofing, let lat = currentLat, let lng = currentLng else { return }
        do {
            try await deviceService.setLocation(lat: lat, lng: lng)
            isSpoofing = true
            lastError = nil
        } catch {
            isSpoofing = false
            lastError = "Keepalive failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Persistence / restore

    @MainActor
    private func persistState() {
        let d = UserDefaults.standard
        d.set(desiredSpoofing, forKey: Keys.desired)
        if let lat = currentLat, let lng = currentLng {
            d.set(lat, forKey: Keys.lat)
            d.set(lng, forKey: Keys.lng)
        }
    }

    /// Re-applies a previously active spoof after the Mac app relaunches.
    /// Safe to call once at startup; if no spoof was active it does nothing.
    @MainActor
    func restoreIfNeeded() async {
        let d = UserDefaults.standard
        guard d.bool(forKey: Keys.desired),
              d.object(forKey: Keys.lat) != nil,
              d.object(forKey: Keys.lng) != nil else { return }
        let lat = d.double(forKey: Keys.lat)
        let lng = d.double(forKey: Keys.lng)
        _ = await applySet(lat: lat, lng: lng)
    }
}
