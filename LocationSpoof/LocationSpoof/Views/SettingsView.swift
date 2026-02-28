import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var spoofService: SpoofService

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
