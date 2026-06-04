import Foundation
import Combine

final class SpoofService: ObservableObject {
    let client = BonjourClient()
    private var remoteClient: RemoteSpoofClient?

    @Published var isSpoofing = false
    @Published var spoofedLat: Double?
    @Published var spoofedLng: Double?
    @Published var deviceName: String?
    @Published var lastError: String?
    @Published var isConnected = false
    @Published var isLoading = false
    @Published var isRemoteMode = false

    /// Whether the user *intends* to be spoofing. Persisted so the app can
    /// re-assert the spoof to the Mac after a reconnect (e.g. the phone left and
    /// rejoined the network, or the Mac's tunnel to the device briefly dropped).
    private(set) var desiredSpoofing = false
    private var lastLat: Double?
    private var lastLng: Double?
    private var lastReassert = Date.distantPast

    private enum Keys {
        static let desired = "ios.desiredSpoofing"
        static let lat = "ios.spoofLat"
        static let lng = "ios.spoofLng"
    }

    private var cancellables = Set<AnyCancellable>()
    private var remoteConnectionCancellable: AnyCancellable?

    init() {
        loadDesiredState()

        client.onResponseReceived = { [weak self] response in
            self?.handleResponse(response)
        }

        client.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard self?.remoteClient == nil else { return }
                self?.isConnected = connected
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .remoteMacAPIURLDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.restartConnection()
            }
            .store(in: &cancellables)
    }

    func start() {
        restartConnection()
    }

    func stop() {
        if remoteClient != nil {
            remoteClient?.stopBrowsing()
            remoteClient = nil
            isRemoteMode = false
            isConnected = false
        } else {
            client.stopBrowsing()
        }
    }

    private func restartConnection() {
        if let url = RemoteConfig.remoteBaseURL() {
            client.stopBrowsing()
            remoteClient?.stopBrowsing()
            let remote = RemoteSpoofClient(baseURL: url)
            remote.onResponseReceived = { [weak self] response in
                self?.handleResponse(response)
            }
            remoteConnectionCancellable = remote.$isConnected
                .receive(on: DispatchQueue.main)
                .sink { [weak self] connected in
                    self?.isConnected = connected
                }
            remoteClient = remote
            isRemoteMode = true
            remote.startBrowsing()
        } else {
            remoteConnectionCancellable = nil
            remoteClient?.stopBrowsing()
            remoteClient = nil
            isRemoteMode = false
            client.startBrowsing()
        }
    }

    func setLocation(lat: Double, lng: Double) {
        lastError = nil
        isLoading = true
        desiredSpoofing = true
        lastLat = lat
        lastLng = lng
        persistDesiredState()
        sendSet(lat: lat, lng: lng)
    }

    func clearLocation() {
        lastError = nil
        isLoading = true
        desiredSpoofing = false
        persistDesiredState()
        if let remote = remoteClient {
            remote.send(.clear)
        } else {
            client.send(.clear)
        }
    }

    func ping() {
        if let remote = remoteClient {
            remote.send(.ping)
        } else {
            client.send(.ping)
        }
    }

    /// Low-level set that does not toggle the loading UI — used for silent
    /// re-assertion as well as the user-initiated `setLocation`.
    private func sendSet(lat: Double, lng: Double) {
        if let remote = remoteClient {
            remote.send(.set(lat: lat, lng: lng))
        } else {
            client.send(.set(lat: lat, lng: lng))
        }
    }

    /// If the user wants to be spoofing but the Mac reports it isn't, re-send the
    /// last location. Throttled so polling can't spam the Mac.
    private func maybeReassert(macSpoofing: Bool) {
        guard desiredSpoofing, !macSpoofing,
              let lat = lastLat, let lng = lastLng else { return }
        guard Date().timeIntervalSince(lastReassert) > 8 else { return }
        lastReassert = Date()
        sendSet(lat: lat, lng: lng)
    }

    private func handleResponse(_ response: SpoofResponse) {
        isLoading = false
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
            if let lat = response.lat, let lng = response.lng {
                spoofedLat = lat
                spoofedLng = lng
            }
            maybeReassert(macSpoofing: isSpoofing)
        default:
            break
        }
    }

    // MARK: - Persistence

    private func loadDesiredState() {
        let d = UserDefaults.standard
        desiredSpoofing = d.bool(forKey: Keys.desired)
        if d.object(forKey: Keys.lat) != nil, d.object(forKey: Keys.lng) != nil {
            lastLat = d.double(forKey: Keys.lat)
            lastLng = d.double(forKey: Keys.lng)
        }
    }

    private func persistDesiredState() {
        let d = UserDefaults.standard
        d.set(desiredSpoofing, forKey: Keys.desired)
        if let lat = lastLat, let lng = lastLng {
            d.set(lat, forKey: Keys.lat)
            d.set(lng, forKey: Keys.lng)
        }
    }
}
