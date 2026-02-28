import Foundation

enum DeviceError: LocalizedError {
    case commandNotFound(String)
    case commandFailed(String)
    case deviceNotConnected

    var errorDescription: String? {
        switch self {
        case .commandNotFound(let cmd):
            return "Command not found: \(cmd). Please install pymobiledevice3."
        case .commandFailed(let output):
            return "Command failed: \(output)"
        case .deviceNotConnected:
            return "No iOS device connected."
        }
    }
}

final class DeviceService {
    private let pymobiledevicePath: String

    init(pymobiledevicePath: String? = nil) {
        self.pymobiledevicePath = pymobiledevicePath ?? Self.findPymobiledevice()
    }

    private static func findPymobiledevice() -> String {
        let searchPaths = [
            "/opt/homebrew/bin/pymobiledevice3",
            "/usr/local/bin/pymobiledevice3",
            "\(NSHomeDirectory())/.local/bin/pymobiledevice3",
            "\(NSHomeDirectory())/Library/Python/3.11/bin/pymobiledevice3",
            "\(NSHomeDirectory())/Library/Python/3.12/bin/pymobiledevice3",
            "\(NSHomeDirectory())/Library/Python/3.13/bin/pymobiledevice3",
        ]
        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        if let path = try? runProcess("/usr/bin/which", arguments: ["pymobiledevice3"]),
           !path.isEmpty {
            return path
        }
        return "pymobiledevice3"
    }

    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: pymobiledevicePath)
    }

    func setLocation(lat: Double, lng: Double) async throws {
        let output = try await runPymobiledevice(
            arguments: ["developer", "dvt", "simulate-location", "set", "--", String(lat), String(lng)]
        )
        if output.lowercased().contains("error") || output.lowercased().contains("failed") {
            throw DeviceError.commandFailed(output)
        }
    }

    func clearLocation() async throws {
        let output = try await runPymobiledevice(
            arguments: ["developer", "dvt", "simulate-location", "clear"]
        )
        if output.lowercased().contains("error") || output.lowercased().contains("failed") {
            throw DeviceError.commandFailed(output)
        }
    }

    private func runPymobiledevice(arguments: [String]) async throws -> String {
        guard isAvailable else {
            throw DeviceError.commandNotFound(pymobiledevicePath)
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let output = try Self.runProcess(self.pymobiledevicePath, arguments: arguments)
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func runProcess(_ command: String, arguments: [String] = []) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin"]
        if let existingPath = env["PATH"] {
            env["PATH"] = extraPaths.joined(separator: ":") + ":" + existingPath
        }
        process.environment = env

        try process.run()
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outStr = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            let combined = [outStr, errStr].filter { !$0.isEmpty }.joined(separator: "\n")
            throw DeviceError.commandFailed(combined)
        }

        return outStr
    }
}
