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

    private var cancellables = Set<AnyCancellable>()
    private var remoteConnectionCancellable: AnyCancellable?

    init() {
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
        if let remote = remoteClient {
            remote.send(.set(lat: lat, lng: lng))
        } else {
            client.send(.set(lat: lat, lng: lng))
        }
    }

    func clearLocation() {
        lastError = nil
        isLoading = true
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
        default:
            break
        }
    }
}
