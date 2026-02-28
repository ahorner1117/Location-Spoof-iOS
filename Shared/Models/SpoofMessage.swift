import Foundation

enum SpoofAction: String, Codable {
    case set
    case clear
    case ping
}

struct SpoofMessage: Codable {
    let action: SpoofAction
    let lat: Double?
    let lng: Double?

    static func set(lat: Double, lng: Double) -> SpoofMessage {
        SpoofMessage(action: .set, lat: lat, lng: lng)
    }

    static var clear: SpoofMessage {
        SpoofMessage(action: .clear, lat: nil, lng: nil)
    }

    static var ping: SpoofMessage {
        SpoofMessage(action: .ping, lat: nil, lng: nil)
    }
}
