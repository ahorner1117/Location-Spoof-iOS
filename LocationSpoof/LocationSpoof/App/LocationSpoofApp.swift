import SwiftUI

@main
struct LocationSpoofApp: App {
    @StateObject private var spoofService = SpoofService()
    private let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(spoofService)
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .onAppear {
                    spoofService.start()
                }
        }
    }
}

struct ContentView: View {
    @State private var selectedTab = 0

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
