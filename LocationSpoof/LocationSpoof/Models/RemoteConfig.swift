import Foundation

enum RemoteConfig {
    static let remoteMacAPIURLKey = "remoteMacAPIURL"

    static var remoteMacAPIURL: String? {
        get {
            UserDefaults.standard.string(forKey: remoteMacAPIURLKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }
        set {
            let value = newValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            UserDefaults.standard.set(value, forKey: remoteMacAPIURLKey)
            NotificationCenter.default.post(name: .remoteMacAPIURLDidChange, object: nil)
        }
    }

    static func remoteBaseURL() -> URL? {
        guard let raw = remoteMacAPIURL else { return nil }
        var str = raw
        if !str.contains("://") { str = "http://" + str }
        return URL(string: str)
    }
}

extension String {
    fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension Notification.Name {
    static let remoteMacAPIURLDidChange = Notification.Name("remoteMacAPIURLDidChange")
}
