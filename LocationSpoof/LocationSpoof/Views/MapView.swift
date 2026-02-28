import SwiftUI
import MapKit

struct SpoofMapView: View {
    @EnvironmentObject private var spoofService: SpoofService
    @Environment(\.managedObjectContext) private var viewContext

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var searchText = ""
    @State private var showingSaveFavorite = false
    @State private var favoriteName = ""

    var body: some View {
        ZStack(alignment: .bottom) {
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

            VStack {
                searchBar
                Spacer()
            }

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
}
