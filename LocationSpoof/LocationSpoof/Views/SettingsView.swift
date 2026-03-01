import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var spoofService: SpoofService
    @AppStorage(RemoteConfig.remoteMacAPIURLKey) private var remoteMacAPIURL = ""

    var body: some View {
        List {
            Section("Remote access") {
                TextField("Mac API URL (optional)", text: $remoteMacAPIURL)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onChange(of: remoteMacAPIURL) { _, _ in
                        NotificationCenter.default.post(name: .remoteMacAPIURLDidChange, object: nil)
                    }

                if spoofService.isRemoteMode {
                    Label("Using remote Mac API", systemImage: "network")
                        .foregroundStyle(.green)
                }

                Text("Use when you're not on the same WiFi. Examples: Tailscale (http://100.x.x.x:8765), Cloudflare Tunnel (https://xxx.trycloudflare.com). Leave empty for local Bonjour.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

                if spoofService.isRemoteMode {
                    HStack {
                        Text("Mode")
                        Spacer()
                        Text("Remote API")
                            .foregroundStyle(.secondary)
                    }
                } else if let name = spoofService.client.discoveredServiceName {
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
                    setupStep("5", "Same WiFi: use Bonjour. Elsewhere: set Mac API URL above and expose port 8765 via Tailscale or Cloudflare Tunnel.")
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
