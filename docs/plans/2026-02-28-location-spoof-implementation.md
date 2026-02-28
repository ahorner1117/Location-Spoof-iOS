# Location Spoof Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a two-app system (iOS + macOS menu bar) that spoofs device-wide GPS location using pymobiledevice3.

**Architecture:** iOS SwiftUI app with MapKit for location selection communicates over Bonjour/TCP with a macOS menu bar app that invokes pymobiledevice3 CLI to set simulated GPS coordinates on the connected iPhone.

**Tech Stack:** SwiftUI, MapKit, CoreData, Network framework (Bonjour), pymobiledevice3 CLI, xcodegen

---

### Task 1: Project Scaffolding

**Files:**
- Create: `LocationSpoof/project.yml` (xcodegen spec for iOS app)
- Create: `LocationSpoofMac/project.yml` (xcodegen spec for macOS app)
- Create: `Shared/Models/SpoofMessage.swift`
- Create: `Shared/Models/SpoofResponse.swift`

**Step 1: Install xcodegen if needed**

Run: `brew install xcodegen`
Expected: xcodegen available at command line

**Step 2: Create directory structure**

```bash
mkdir -p LocationSpoof/LocationSpoof/{App,Views,Models,Services,Resources}
mkdir -p LocationSpoof/LocationSpoofTests
mkdir -p LocationSpoofMac/LocationSpoofMac/{App,Views,Services,Resources}
mkdir -p LocationSpoofMac/LocationSpoofMacTests
mkdir -p Shared/Models
```

**Step 3: Create shared protocol types**

`Shared/Models/SpoofMessage.swift`:
```swift
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
```

`Shared/Models/SpoofResponse.swift`:
```swift
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
```

**Step 4: Create xcodegen spec for iOS app**

`LocationSpoof/project.yml`:
```yaml
name: LocationSpoof
options:
  bundleIdPrefix: com.locspoof
  deploymentTarget:
    iOS: "16.0"
  xcodeVersion: "15.0"
  createIntermediateGroups: true

targets:
  LocationSpoof:
    type: application
    platform: iOS
    sources:
      - LocationSpoof
      - path: ../Shared
        group: Shared
    settings:
      base:
        INFOPLIST_FILE: LocationSpoof/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.locspoof.LocationSpoof
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "1"
        DEVELOPMENT_TEAM: ""
    info:
      path: LocationSpoof/Info.plist
      properties:
        CFBundleName: Location Spoof
        CFBundleDisplayName: Location Spoof
        UILaunchScreen: {}
        NSLocalNetworkUsageDescription: "Location Spoof needs local network access to communicate with the macOS companion app."
        NSBonjourServices:
          - _locspoof._tcp
        NSLocationWhenInUseUsageDescription: "Location Spoof uses your location to show your current position on the map."

  LocationSpoofTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - LocationSpoofTests
      - path: ../Shared
        group: Shared
    dependencies:
      - target: LocationSpoof
    settings:
      base:
        INFOPLIST_FILE: LocationSpoofTests/Info.plist
```

**Step 5: Create xcodegen spec for macOS app**

`LocationSpoofMac/project.yml`:
```yaml
name: LocationSpoofMac
options:
  bundleIdPrefix: com.locspoof
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "15.0"
  createIntermediateGroups: true

targets:
  LocationSpoofMac:
    type: application
    platform: macOS
    sources:
      - LocationSpoofMac
      - path: ../Shared
        group: Shared
    settings:
      base:
        INFOPLIST_FILE: LocationSpoofMac/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.locspoof.LocationSpoofMac
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "1"
        DEVELOPMENT_TEAM: ""
    info:
      path: LocationSpoofMac/Info.plist
      properties:
        CFBundleName: Location Spoof
        CFBundleDisplayName: Location Spoof
        LSUIElement: true
    entitlements:
      path: LocationSpoofMac/LocationSpoofMac.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.network.server: true
        com.apple.security.network.client: true

  LocationSpoofMacTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - LocationSpoofMacTests
      - path: ../Shared
        group: Shared
    dependencies:
      - target: LocationSpoofMac
    settings:
      base:
        INFOPLIST_FILE: LocationSpoofMacTests/Info.plist
```

**Step 6: Generate Xcode projects**

```bash
cd LocationSpoof && xcodegen generate && cd ..
cd LocationSpoofMac && xcodegen generate && cd ..
```

Expected: `LocationSpoof.xcodeproj` and `LocationSpoofMac.xcodeproj` created

**Step 7: Commit**

```bash
git add -A
git commit -m "Scaffold project structure with xcodegen"
```

---

### Task 2: Shared Message Encoding Tests

**Files:**
- Create: `LocationSpoof/LocationSpoofTests/SpoofMessageTests.swift`

**Step 1: Write tests for message encoding/decoding**

```swift
import XCTest
@testable import LocationSpoof

final class SpoofMessageTests: XCTestCase {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    func testSetMessageEncodesCorrectly() throws {
        let msg = SpoofMessage.set(lat: 35.6762, lng: 139.6503)
        let data = try encoder.encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["action"] as? String, "set")
        XCTAssertEqual(json["lat"] as? Double, 35.6762)
        XCTAssertEqual(json["lng"] as? Double, 139.6503)
    }

    func testClearMessageEncodesCorrectly() throws {
        let msg = SpoofMessage.clear
        let data = try encoder.encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["action"] as? String, "clear")
        XCTAssertNil(json["lat"])
        XCTAssertNil(json["lng"])
    }

    func testPingMessageEncodesCorrectly() throws {
        let msg = SpoofMessage.ping
        let data = try encoder.encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["action"] as? String, "ping")
    }

    func testMessageRoundTrips() throws {
        let original = SpoofMessage.set(lat: -33.8688, lng: 151.2093)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SpoofMessage.self, from: data)

        XCTAssertEqual(decoded.action, .set)
        XCTAssertEqual(decoded.lat, -33.8688)
        XCTAssertEqual(decoded.lng, 151.2093)
    }

    func testResponseOkEncodesCorrectly() throws {
        let resp = SpoofResponse.ok(spoofing: true, lat: 40.7128, lng: -74.0060)
        let data = try encoder.encode(resp)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["status"] as? String, "ok")
        XCTAssertEqual(json["spoofing"] as? Bool, true)
        XCTAssertEqual(json["lat"] as? Double, 40.7128)
    }

    func testResponseErrorEncodesCorrectly() throws {
        let resp = SpoofResponse.error("Device not connected")
        let data = try encoder.encode(resp)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["status"] as? String, "error")
        XCTAssertEqual(json["message"] as? String, "Device not connected")
    }

    func testResponsePongEncodesCorrectly() throws {
        let resp = SpoofResponse.pong(device: "Anthony's iPhone", spoofing: false)
        let data = try encoder.encode(resp)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["status"] as? String, "pong")
        XCTAssertEqual(json["device"] as? String, "Anthony's iPhone")
        XCTAssertEqual(json["spoofing"] as? Bool, false)
    }
}
```

**Step 2: Run tests**

```bash
cd LocationSpoof && xcodebuild test -scheme LocationSpoof -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```

Expected: All 7 tests pass

**Step 3: Commit**

```bash
git add -A
git commit -m "Add shared message types with encoding tests"
```

---

### Task 3: macOS — DeviceService (pymobiledevice3 wrapper)

**Files:**
- Create: `LocationSpoofMac/LocationSpoofMac/Services/DeviceService.swift`
- Create: `LocationSpoofMac/LocationSpoofMacTests/DeviceServiceTests.swift`

**Step 1: Write DeviceService**

```swift
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

    /// Locate pymobiledevice3 binary
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
        // Fallback: try which
        if let path = try? runProcess("/usr/bin/which", arguments: ["pymobiledevice3"]),
           !path.isEmpty {
            return path
        }
        return "pymobiledevice3" // Will fail with a clear error later
    }

    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: pymobiledevicePath)
    }

    /// Set the simulated location on the connected device
    func setLocation(lat: Double, lng: Double) async throws {
        let output = try await runPymobiledevice(
            arguments: ["developer", "dvt", "simulate-location", "set", "--", String(lat), String(lng)]
        )
        // pymobiledevice3 outputs nothing on success for set
        if output.lowercased().contains("error") || output.lowercased().contains("failed") {
            throw DeviceError.commandFailed(output)
        }
    }

    /// Clear the simulated location
    func clearLocation() async throws {
        let output = try await runPymobiledevice(
            arguments: ["developer", "dvt", "simulate-location", "clear"]
        )
        if output.lowercased().contains("error") || output.lowercased().contains("failed") {
            throw DeviceError.commandFailed(output)
        }
    }

    /// Run pymobiledevice3 with arguments, async
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

    /// Synchronous process runner
    static func runProcess(_ command: String, arguments: [String] = []) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        // Inherit PATH so pymobiledevice3 can find its dependencies
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
```

**Step 2: Write tests**

```swift
import XCTest
@testable import LocationSpoofMac

final class DeviceServiceTests: XCTestCase {
    func testFindReturnsExecutablePath() {
        // Test that the static method at least runs without crashing
        let service = DeviceService(pymobiledevicePath: "/usr/bin/true")
        XCTAssertTrue(service.isAvailable)
    }

    func testIsAvailableReturnsFalseForBadPath() {
        let service = DeviceService(pymobiledevicePath: "/nonexistent/path")
        XCTAssertFalse(service.isAvailable)
    }

    func testRunProcessSucceeds() throws {
        let output = try DeviceService.runProcess("/bin/echo", arguments: ["hello"])
        XCTAssertEqual(output, "hello")
    }

    func testRunProcessFailsOnBadCommand() {
        XCTAssertThrowsError(try DeviceService.runProcess("/bin/false"))
    }
}
```

**Step 3: Run tests**

```bash
cd LocationSpoofMac && xcodebuild test -scheme LocationSpoofMac -destination 'platform=macOS' -quiet
```

Expected: All 4 tests pass

**Step 4: Commit**

```bash
git add -A
git commit -m "Add DeviceService pymobiledevice3 wrapper"
```

---

### Task 4: macOS — BonjourServer

**Files:**
- Create: `LocationSpoofMac/LocationSpoofMac/Services/BonjourServer.swift`

**Step 1: Write BonjourServer**

```swift
import Foundation
import Network

final class BonjourServer: ObservableObject {
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private let queue = DispatchQueue(label: "BonjourServer")
    private var receiveBuffer = Data()

    @Published var isClientConnected = false

    var onMessageReceived: ((SpoofMessage) -> Void)?

    func start() {
        do {
            listener = try NWListener(using: .tcp)
        } catch {
            print("Failed to create NWListener: \(error)")
            return
        }

        listener?.service = NWListener.Service(name: nil, type: "_locspoof._tcp")

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = self?.listener?.port {
                    print("Server ready on port \(port)")
                }
            case .failed(let error):
                print("Listener failed: \(error)")
                self?.listener?.cancel()
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] newConnection in
            guard let self = self else { return }
            if self.activeConnection != nil {
                newConnection.cancel()
                return
            }
            self.setupConnection(newConnection)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        activeConnection?.cancel()
        activeConnection = nil
        listener?.cancel()
        listener = nil
    }

    private func setupConnection(_ connection: NWConnection) {
        activeConnection = connection
        receiveBuffer = Data()

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                DispatchQueue.main.async { self?.isClientConnected = true }
                self?.startReceiving(on: connection)
            case .failed, .cancelled:
                self?.cleanupConnection(connection)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func cleanupConnection(_ connection: NWConnection) {
        if activeConnection === connection {
            activeConnection = nil
            receiveBuffer = Data()
            DispatchQueue.main.async { self.isClientConnected = false }
        }
    }

    private func startReceiving(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBuffer()
            }
            if isComplete {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }
            self.startReceiving(on: connection)
        }
    }

    private func processBuffer() {
        let newline = UInt8(ascii: "\n")
        while let idx = receiveBuffer.firstIndex(of: newline) {
            let lineData = receiveBuffer[receiveBuffer.startIndex..<idx]
            receiveBuffer = Data(receiveBuffer[(idx + 1)...])

            guard !lineData.isEmpty,
                  let msg = try? JSONDecoder().decode(SpoofMessage.self, from: lineData)
            else { continue }

            DispatchQueue.main.async {
                self.onMessageReceived?(msg)
            }
        }
    }

    func send(response: SpoofResponse) {
        guard let connection = activeConnection,
              let data = try? JSONEncoder().encode(response),
              var payload = String(data: data, encoding: .utf8)
        else { return }

        payload.append("\n")
        connection.send(content: Data(payload.utf8), completion: .contentProcessed { error in
            if let error = error {
                print("Send error: \(error)")
            }
        })
    }
}
```

**Step 2: Commit**

```bash
git add -A
git commit -m "Add BonjourServer for macOS app"
```

---

### Task 5: macOS — CommandHandler

**Files:**
- Create: `LocationSpoofMac/LocationSpoofMac/Services/CommandHandler.swift`

**Step 1: Write CommandHandler**

```swift
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

    /// Manual clear from the macOS UI
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
```

**Step 2: Commit**

```bash
git add -A
git commit -m "Add CommandHandler to dispatch messages to DeviceService"
```

---

### Task 6: macOS — Menu Bar App UI

**Files:**
- Create: `LocationSpoofMac/LocationSpoofMac/App/LocationSpoofMacApp.swift`
- Create: `LocationSpoofMac/LocationSpoofMac/Views/MenuBarView.swift`

**Step 1: Write the App entry point**

```swift
import SwiftUI

@main
struct LocationSpoofMacApp: App {
    @State private var handler = CommandHandler()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(handler: handler)
                .frame(width: 300, height: 280)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        if handler.isSpoofing {
            return "location.fill"
        } else if handler.server.isClientConnected {
            return "location"
        } else {
            return "location.slash"
        }
    }
}
```

**Step 2: Write MenuBarView**

```swift
import SwiftUI

struct MenuBarView: View {
    @Bindable var handler: CommandHandler

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: statusIcon)
                    .font(.title2)
                    .foregroundStyle(statusColor)
                VStack(alignment: .leading) {
                    Text("Location Spoof")
                        .font(.headline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            // Connection status
            HStack {
                Circle()
                    .fill(handler.server.isClientConnected ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(handler.server.isClientConnected ? "iOS app connected" : "iOS app not connected")
                    .font(.caption)
                Spacer()
            }

            // pymobiledevice3 status
            HStack {
                Circle()
                    .fill(handler.isReady ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(handler.isReady ? "pymobiledevice3 found" : "pymobiledevice3 not found")
                    .font(.caption)
                Spacer()
            }

            // Current spoof info
            if handler.isSpoofing, let lat = handler.currentLat, let lng = handler.currentLng {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spoofing Location")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text(String(format: "%.6f, %.6f", lat, lng))
                        .font(.system(.caption, design: .monospaced))

                    Button("Clear Spoof") {
                        Task { await handler.clearFromUI() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                }
            }

            // Error display
            if let error = handler.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            Spacer()
            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .onAppear {
            handler.start()
        }
    }

    private var statusIcon: String {
        handler.isSpoofing ? "location.fill" : "location.slash"
    }

    private var statusColor: Color {
        handler.isSpoofing ? .green : .secondary
    }

    private var statusText: String {
        if handler.isSpoofing {
            return "Spoofing active"
        } else if handler.server.isClientConnected {
            return "Connected, idle"
        } else {
            return "Waiting for iOS app..."
        }
    }
}
```

**Step 3: Build the macOS app**

```bash
cd LocationSpoofMac && xcodebuild build -scheme LocationSpoofMac -destination 'platform=macOS' -quiet
```

Expected: Build succeeds

**Step 4: Commit**

```bash
git add -A
git commit -m "Add macOS menu bar app UI"
```

---

### Task 7: iOS — BonjourClient

**Files:**
- Create: `LocationSpoof/LocationSpoof/Services/BonjourClient.swift`

**Step 1: Write BonjourClient**

```swift
import Foundation
import Network

final class BonjourClient: ObservableObject {
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "BonjourClient")
    private var receiveBuffer = Data()
    private var reconnectTimer: DispatchSourceTimer?
    private var shouldReconnect = false

    @Published var isConnected = false
    @Published var discoveredServiceName: String?

    var onResponseReceived: ((SpoofResponse) -> Void)?

    func startBrowsing() {
        shouldReconnect = true

        browser = NWBrowser(
            for: .bonjour(type: "_locspoof._tcp", domain: nil),
            using: NWParameters()
        )

        browser?.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("Browser failed: \(error)")
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            for result in results {
                if case .service(let name, _, _, _) = result.endpoint {
                    DispatchQueue.main.async {
                        self.discoveredServiceName = name
                    }
                    if self.connection == nil {
                        self.connect(to: result.endpoint)
                    }
                    break
                }
            }
        }

        browser?.start(queue: queue)
    }

    func stopBrowsing() {
        shouldReconnect = false
        reconnectTimer?.cancel()
        reconnectTimer = nil
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
    }

    private func connect(to endpoint: NWEndpoint) {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveInterval = 5
        let params = NWParameters(tls: nil, tcp: tcp)

        let conn = NWConnection(to: endpoint, using: params)
        connection = conn
        receiveBuffer = Data()

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async { self.isConnected = true }
                self.startReceiving(on: conn)
            case .failed, .cancelled:
                self.handleDisconnect()
            default:
                break
            }
        }

        conn.start(queue: queue)
    }

    private func handleDisconnect() {
        connection = nil
        receiveBuffer = Data()
        DispatchQueue.main.async { self.isConnected = false }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        reconnectTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.connection == nil else { return }
            self.browser?.cancel()
            self.browser = nil
            self.startBrowsing()
        }
        timer.resume()
        reconnectTimer = timer
    }

    private func startReceiving(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBuffer()
            }
            if isComplete { connection.cancel(); return }
            if error != nil { connection.cancel(); return }
            self.startReceiving(on: connection)
        }
    }

    private func processBuffer() {
        let newline = UInt8(ascii: "\n")
        while let idx = receiveBuffer.firstIndex(of: newline) {
            let lineData = receiveBuffer[receiveBuffer.startIndex..<idx]
            receiveBuffer = Data(receiveBuffer[(idx + 1)...])

            guard !lineData.isEmpty,
                  let resp = try? JSONDecoder().decode(SpoofResponse.self, from: lineData)
            else { continue }

            DispatchQueue.main.async {
                self.onResponseReceived?(resp)
            }
        }
    }

    func send(_ message: SpoofMessage) {
        guard let connection = connection,
              let data = try? JSONEncoder().encode(message),
              var payload = String(data: data, encoding: .utf8)
        else { return }

        payload.append("\n")
        connection.send(content: Data(payload.utf8), completion: .contentProcessed { _ in })
    }
}
```

**Step 2: Commit**

```bash
git add -A
git commit -m "Add BonjourClient for iOS app"
```

---

### Task 8: iOS — SpoofService

**Files:**
- Create: `LocationSpoof/LocationSpoof/Services/SpoofService.swift`

**Step 1: Write SpoofService (high-level orchestrator)**

```swift
import Foundation
import Combine

@Observable
final class SpoofService {
    let client = BonjourClient()

    var isConnected: Bool { client.isConnected }
    var isSpoofing = false
    var spoofedLat: Double?
    var spoofedLng: Double?
    var deviceName: String?
    var lastError: String?

    private var cancellables = Set<AnyCancellable>()

    init() {
        client.onResponseReceived = { [weak self] response in
            self?.handleResponse(response)
        }
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
```

**Step 2: Commit**

```bash
git add -A
git commit -m "Add SpoofService orchestrator for iOS app"
```

---

### Task 9: iOS — CoreData Model

**Files:**
- Create: `LocationSpoof/LocationSpoof/Models/SavedLocation.swift`
- Create: `LocationSpoof/LocationSpoof/Models/PersistenceController.swift`

**Step 1: Write PersistenceController and SavedLocation**

Note: Since we're using xcodegen and not Xcode's visual editor, we'll use a programmatic CoreData model instead of .xcdatamodeld.

`LocationSpoof/LocationSpoof/Models/PersistenceController.swift`:
```swift
import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let model = Self.createModel()
        container = NSPersistentContainer(name: "LocationSpoof", managedObjectModel: model)

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("CoreData failed to load: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    private static func createModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "SavedLocation"
        entity.managedObjectClassName = "SavedLocation"

        let idAttr = NSAttributeDescription()
        idAttr.name = "id"
        idAttr.attributeType = .UUIDAttributeType
        idAttr.isOptional = false

        let nameAttr = NSAttributeDescription()
        nameAttr.name = "name"
        nameAttr.attributeType = .stringAttributeType
        nameAttr.isOptional = false

        let latAttr = NSAttributeDescription()
        latAttr.name = "latitude"
        latAttr.attributeType = .doubleAttributeType
        latAttr.isOptional = false

        let lngAttr = NSAttributeDescription()
        lngAttr.name = "longitude"
        lngAttr.attributeType = .doubleAttributeType
        lngAttr.isOptional = false

        let addressAttr = NSAttributeDescription()
        addressAttr.name = "address"
        addressAttr.attributeType = .stringAttributeType
        addressAttr.isOptional = true

        let createdAtAttr = NSAttributeDescription()
        createdAtAttr.name = "createdAt"
        createdAtAttr.attributeType = .dateAttributeType
        createdAtAttr.isOptional = false

        entity.properties = [idAttr, nameAttr, latAttr, lngAttr, addressAttr, createdAtAttr]
        model.entities = [entity]

        return model
    }
}
```

`LocationSpoof/LocationSpoof/Models/SavedLocation.swift`:
```swift
import CoreData

@objc(SavedLocation)
public class SavedLocation: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var latitude: Double
    @NSManaged public var longitude: Double
    @NSManaged public var address: String?
    @NSManaged public var createdAt: Date
}

extension SavedLocation {
    static func create(
        in context: NSManagedObjectContext,
        name: String,
        latitude: Double,
        longitude: Double,
        address: String? = nil
    ) -> SavedLocation {
        let location = SavedLocation(context: context)
        location.id = UUID()
        location.name = name
        location.latitude = latitude
        location.longitude = longitude
        location.address = address
        location.createdAt = Date()
        return location
    }

    static var fetchAllRequest: NSFetchRequest<SavedLocation> {
        let request = NSFetchRequest<SavedLocation>(entityName: "SavedLocation")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \SavedLocation.createdAt, ascending: false)]
        return request
    }
}
```

**Step 2: Commit**

```bash
git add -A
git commit -m "Add CoreData model for saved locations"
```

---

### Task 10: iOS — MapView (Main Screen)

**Files:**
- Create: `LocationSpoof/LocationSpoof/Views/MapView.swift`
- Create: `LocationSpoof/LocationSpoof/Views/LocationCardView.swift`

**Step 1: Write MapView**

```swift
import SwiftUI
import MapKit

struct SpoofMapView: View {
    @Environment(SpoofService.self) private var spoofService
    @Environment(\.managedObjectContext) private var viewContext

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var showingSaveFavorite = false
    @State private var favoriteName = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            // Map
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    if let coord = selectedCoordinate {
                        Annotation("Spoof", coordinate: coord) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundStyle(.red)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .onTapGesture { screenCoord in
                    if let coord = proxy.convert(screenCoord, from: .local) {
                        selectedCoordinate = coord
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }
            }

            // Search bar
            VStack {
                searchBar
                Spacer()
            }

            // Bottom card
            if selectedCoordinate != nil {
                LocationCardView(
                    coordinate: $selectedCoordinate,
                    showingSaveFavorite: $showingSaveFavorite,
                    favoriteName: $favoriteName,
                    onSave: saveFavorite
                )
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut, value: selectedCoordinate != nil)
    }

    @ViewBuilder
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search location...", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit { performSearch() }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func performSearch() {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText

        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            if let item = response?.mapItems.first,
               let location = item.placemark.location {
                selectedCoordinate = location.coordinate
                cameraPosition = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 5000,
                    longitudinalMeters: 5000
                ))
            }
        }
    }

    private func saveFavorite() {
        guard let coord = selectedCoordinate, !favoriteName.isEmpty else { return }
        _ = SavedLocation.create(
            in: viewContext,
            name: favoriteName,
            latitude: coord.latitude,
            longitude: coord.longitude
        )
        try? viewContext.save()
        favoriteName = ""
        showingSaveFavorite = false
    }

    /// Called from FavoritesView to jump to a saved location
    func selectLocation(_ location: SavedLocation) {
        let coord = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        selectedCoordinate = coord
        cameraPosition = .region(MKCoordinateRegion(
            center: coord,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        ))
    }
}
```

**Step 2: Write LocationCardView**

```swift
import SwiftUI
import MapKit

struct LocationCardView: View {
    @Environment(SpoofService.self) private var spoofService
    @Binding var coordinate: CLLocationCoordinate2D?
    @Binding var showingSaveFavorite: Bool
    @Binding var favoriteName: String
    var onSave: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Drag handle
            RoundedRectangle(cornerRadius: 3)
                .fill(.secondary.opacity(0.5))
                .frame(width: 40, height: 5)

            if let coord = coordinate {
                // Coordinates display
                Text(String(format: "%.6f, %.6f", coord.latitude, coord.longitude))
                    .font(.system(.body, design: .monospaced))

                // Connection status
                HStack(spacing: 6) {
                    Circle()
                        .fill(spoofService.isConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(spoofService.isConnected ? "Connected" : "Not connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Spoof button
                if spoofService.isSpoofing {
                    Button {
                        spoofService.clearLocation()
                    } label: {
                        Label("Reset to Real Location", systemImage: "location.slash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        spoofService.setLocation(lat: coord.latitude, lng: coord.longitude)
                    } label: {
                        Label("Spoof Location", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!spoofService.isConnected)
                }

                // Save favorite
                if showingSaveFavorite {
                    HStack {
                        TextField("Location name", text: $favoriteName)
                            .textFieldStyle(.roundedBorder)
                        Button("Save", action: onSave)
                            .disabled(favoriteName.isEmpty)
                    }
                } else {
                    Button {
                        showingSaveFavorite = true
                    } label: {
                        Label("Save as Favorite", systemImage: "star")
                    }
                    .buttonStyle(.bordered)
                }

                // Error
                if let error = spoofService.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding()
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
```

**Step 3: Build iOS app**

```bash
cd LocationSpoof && xcodebuild build -scheme LocationSpoof -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```

Expected: Build succeeds

**Step 4: Commit**

```bash
git add -A
git commit -m "Add MapView and LocationCardView for iOS app"
```

---

### Task 11: iOS — FavoritesView

**Files:**
- Create: `LocationSpoof/LocationSpoof/Views/FavoritesView.swift`

**Step 1: Write FavoritesView**

```swift
import SwiftUI
import CoreData

struct FavoritesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(fetchRequest: SavedLocation.fetchAllRequest)
    private var locations: FetchedResults<SavedLocation>

    var onSelect: ((SavedLocation) -> Void)?

    var body: some View {
        List {
            if locations.isEmpty {
                ContentUnavailableView(
                    "No Favorites",
                    systemImage: "star.slash",
                    description: Text("Save locations from the map to see them here.")
                )
            } else {
                ForEach(locations) { location in
                    Button {
                        onSelect?(location)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(location.name)
                                    .font(.headline)
                                if let address = location.address, !address.isEmpty {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(String(format: "%.4f, %.4f", location.latitude, location.longitude))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteLocations)
            }
        }
        .navigationTitle("Favorites")
    }

    private func deleteLocations(at offsets: IndexSet) {
        for index in offsets {
            viewContext.delete(locations[index])
        }
        try? viewContext.save()
    }
}
```

**Step 2: Commit**

```bash
git add -A
git commit -m "Add FavoritesView for saved locations"
```

---

### Task 12: iOS — SettingsView

**Files:**
- Create: `LocationSpoof/LocationSpoof/Views/SettingsView.swift`

**Step 1: Write SettingsView**

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(SpoofService.self) private var spoofService

    var body: some View {
        List {
            Section("Connection") {
                HStack {
                    Text("Status")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(spoofService.isConnected ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(spoofService.isConnected ? "Connected" : "Disconnected")
                            .foregroundStyle(.secondary)
                    }
                }

                if let name = spoofService.client.discoveredServiceName {
                    HStack {
                        Text("Mac")
                        Spacer()
                        Text(name)
                            .foregroundStyle(.secondary)
                    }
                }

                if let device = spoofService.deviceName {
                    HStack {
                        Text("Device")
                        Spacer()
                        Text(device)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Spoofing") {
                HStack {
                    Text("Active")
                    Spacer()
                    Text(spoofService.isSpoofing ? "Yes" : "No")
                        .foregroundStyle(spoofService.isSpoofing ? .green : .secondary)
                }

                if spoofService.isSpoofing,
                   let lat = spoofService.spoofedLat,
                   let lng = spoofService.spoofedLng {
                    HStack {
                        Text("Location")
                        Spacer()
                        Text(String(format: "%.6f, %.6f", lat, lng))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Setup Instructions") {
                VStack(alignment: .leading, spacing: 8) {
                    setupStep("1", "Install pymobiledevice3 on your Mac:", "pipx install pymobiledevice3")
                    setupStep("2", "Enable Developer Mode on iPhone:", "Settings > Privacy & Security > Developer Mode")
                    setupStep("3", "Pair iPhone with Mac via USB once")
                    setupStep("4", "Launch the Location Spoof menu bar app on Mac")
                    setupStep("5", "Both devices must be on the same WiFi network")
                }
                .font(.caption)
            }
        }
        .navigationTitle("Settings")
    }

    @ViewBuilder
    private func setupStep(_ num: String, _ text: String, _ code: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(num). \(text)")
            if let code = code {
                Text(code)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.blue)
                    .textSelection(.enabled)
            }
        }
    }
}
```

**Step 2: Commit**

```bash
git add -A
git commit -m "Add SettingsView with connection info and setup instructions"
```

---

### Task 13: iOS — App Entry Point (Wire Everything Together)

**Files:**
- Create: `LocationSpoof/LocationSpoof/App/LocationSpoofApp.swift`

**Step 1: Write the App entry point with TabView**

```swift
import SwiftUI

@main
struct LocationSpoofApp: App {
    @State private var spoofService = SpoofService()
    private let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(spoofService)
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .onAppear {
                    spoofService.start()
                }
        }
    }
}

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var selectedFavorite: SavedLocation?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                SpoofMapView()
            }
            .tabItem {
                Label("Map", systemImage: "map")
            }
            .tag(0)

            NavigationStack {
                FavoritesView { location in
                    selectedFavorite = location
                    selectedTab = 0
                }
            }
            .tabItem {
                Label("Favorites", systemImage: "star")
            }
            .tag(1)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(2)
        }
    }
}
```

**Step 2: Build iOS app**

```bash
cd LocationSpoof && xcodebuild build -scheme LocationSpoof -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```

Expected: Build succeeds

**Step 3: Commit**

```bash
git add -A
git commit -m "Add app entry point wiring all views together"
```

---

### Task 14: Build Verification & Final Cleanup

**Step 1: Build macOS app**

```bash
cd LocationSpoofMac && xcodebuild build -scheme LocationSpoofMac -destination 'platform=macOS' -quiet
```

Expected: Build succeeds with no errors

**Step 2: Build iOS app**

```bash
cd LocationSpoof && xcodebuild build -scheme LocationSpoof -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```

Expected: Build succeeds with no errors

**Step 3: Run all tests**

```bash
cd LocationSpoof && xcodebuild test -scheme LocationSpoof -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
cd ../LocationSpoofMac && xcodebuild test -scheme LocationSpoofMac -destination 'platform=macOS' -quiet
```

Expected: All tests pass

**Step 4: Final commit**

```bash
git add -A
git commit -m "Verify builds and tests pass for both apps"
```
