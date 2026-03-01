import SwiftUI

final class AppServices {
    let handler = CommandHandler()
    let httpServer = HTTPServer(port: HTTPServer.defaultPort)

    init() {
        handler.start()
        httpServer.start(handler: handler)
    }
}

@main
struct LocationSpoofMacApp: App {
    @State private var services = AppServices()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(handler: services.handler, httpServer: services.httpServer)
                .frame(width: 320, height: 320)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        if services.handler.isSpoofing {
            return "location.fill"
        } else if services.handler.server.isClientConnected {
            return "location"
        } else {
            return "location.slash"
        }
    }
}
