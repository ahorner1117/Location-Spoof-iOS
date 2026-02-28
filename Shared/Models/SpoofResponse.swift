import Foundation

struct SpoofResponse: Codable {
    let status: String
    let spoofing: Bool?
    let lat: Double?
    let lng: Double?
    let message: String?
    let device: String?

    static func ok(spoofing: Bool, lat: Double? = nil, lng: Double? = nil) -> SpoofResponse {
        SpoofResponse(status: "ok", spoofing: spoofing, lat: lat, lng: lng, message: nil, device: nil)
    }

    static func error(_ message: String) -> SpoofResponse {
        SpoofResponse(status: "error", spoofing: nil, lat: nil, lng: nil, message: message, device: nil)
    }

    static func pong(device: String, spoofing: Bool) -> SpoofResponse {
        SpoofResponse(status: "pong", spoofing: spoofing, lat: nil, lng: nil, message: nil, device: device)
    }
}
