import SwiftUI
import MapKit

struct LocationCardView: View {
    @EnvironmentObject private var spoofService: SpoofService
    @Binding var coordinate: CLLocationCoordinate2D?
    @Binding var showingSaveFavorite: Bool
    @Binding var favoriteName: String
    var onSave: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(.secondary.opacity(0.5))
                .frame(width: 40, height: 5)

            if let coord = coordinate {
                Text(String(format: "%.6f, %.6f", coord.latitude, coord.longitude))
                    .font(.system(.body, design: .monospaced))

                HStack(spacing: 6) {
                    Circle()
                        .fill(spoofService.isConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(spoofService.isConnected ? "Connected" : "Not connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if spoofService.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Setting location...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else if spoofService.isSpoofing {
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
