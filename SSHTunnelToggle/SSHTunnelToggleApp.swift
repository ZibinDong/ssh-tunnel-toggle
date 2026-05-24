import SwiftUI

@main
struct SSHTunnelToggleApp: App {
    @StateObject private var manager = TunnelManager()

    var body: some Scene {
        MenuBarExtra("SSH Tunnel Toggle", systemImage: "point.3.connected.trianglebadge.dots.wifi.and.wifi") {
            MenuBarView(manager: manager)
        }
        .menuBarExtraStyle(.menu)
    }
}
