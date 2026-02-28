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
