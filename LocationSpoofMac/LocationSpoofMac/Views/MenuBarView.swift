import SwiftUI

struct MenuBarView: View {
    @Bindable var handler: CommandHandler
    @Bindable var httpServer: HTTPServer

    var body: some View {
        VStack(spacing: 12) {
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

            HStack {
                Circle()
                    .fill(handler.server.isClientConnected ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(handler.server.isClientConnected ? "iOS app connected" : "iOS app not connected")
                    .font(.caption)
                Spacer()
            }

            HStack {
                Circle()
                    .fill(handler.isReady ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(handler.isReady ? "pymobiledevice3 found" : "pymobiledevice3 not found")
                    .font(.caption)
                Spacer()
            }

            if httpServer.isRunning, let port = httpServer.boundPort {
                HStack {
                    Image(systemName: "network")
                        .foregroundStyle(.secondary)
                    Text("Remote API: port \(port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

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
            httpServer.start(handler: handler)
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
