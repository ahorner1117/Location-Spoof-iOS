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
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let searchPaths = [
            "/opt/homebrew/bin/pymobiledevice3",
            "/usr/local/bin/pymobiledevice3",
            "\(home)/.local/bin/pymobiledevice3",
            "\(home)/Library/Python/3.11/bin/pymobiledevice3",
            "\(home)/Library/Python/3.12/bin/pymobiledevice3",
            "\(home)/Library/Python/3.13/bin/pymobiledevice3",
            "\(home)/Library/Python/3.14/bin/pymobiledevice3",
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

    /// Tracks the running simulate-location process so we can kill it on clear/new set
    private var runningProcess: Process?

    private func runPymobiledevice(arguments: [String]) async throws -> String {
        guard isAvailable else {
            throw DeviceError.commandNotFound(pymobiledevicePath)
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let output = try self.runProcessWithTimeout(self.pymobiledevicePath, arguments: arguments, timeout: 10)
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Runs a process with a timeout. pymobiledevice3 simulate-location often hangs
    /// after successfully setting the location, so we treat a timeout as success
    /// (the location was set) and kill the lingering process.
    private func runProcessWithTimeout(_ command: String, arguments: [String], timeout: TimeInterval) throws -> String {
        // Kill any previous lingering process
        if let prev = runningProcess, prev.isRunning {
            prev.terminate()
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin"]
        if let existingPath = env["PATH"] {
            env["PATH"] = extraPaths.joined(separator: ":") + ":" + existingPath
        }
        process.environment = env

        try process.run()
        runningProcess = process

        // Wait with timeout — pymobiledevice3 hangs after success
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }

        if process.isRunning {
            // Process is still running after timeout — this is expected behavior
            // for pymobiledevice3 simulate-location (it hangs after setting location).
            // The location WAS set successfully. Leave process running in background.
            return ""
        }

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

    static func runProcess(_ command: String, arguments: [String] = []) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin"]
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
