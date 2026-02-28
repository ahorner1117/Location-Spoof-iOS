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
