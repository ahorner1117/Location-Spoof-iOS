import SwiftUI

@main
struct LocationSpoofMacApp: App {
    @State private var handler = CommandHandler()
    @State private var httpServer = HTTPServer(port: HTTPServer.defaultPort)

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(handler: handler, httpServer: httpServer)
                .frame(width: 320, height: 320)
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
