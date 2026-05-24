import SwiftUI

@main
struct SSHTunnelToggleApp: App {
    @StateObject private var manager = TunnelManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(manager: manager)
        } label: {
            Image("StatusBarIcon")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)
    }
}
