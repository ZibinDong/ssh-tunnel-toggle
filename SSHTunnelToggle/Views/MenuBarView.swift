import SwiftUI

struct MenuBarView: View {
    @ObservedObject var manager: TunnelManager
    @State private var showingAddSheet = false
    @State private var editingTunnel: TunnelConfig?

    var body: some View {
        if manager.tunnels.isEmpty {
            Text("No tunnels configured")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button("Add Tunnel...") {
                showingAddSheet = true
            }

            Divider()
        } else {
            ForEach(manager.tunnels) { tunnel in
                tunnelRow(tunnel)
            }

            Divider()

            Button("Add Tunnel...") {
                showingAddSheet = true
            }
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private func tunnelRow(_ tunnel: TunnelConfig) -> some View {
        Button {
            manager.toggleTunnel(id: tunnel.id)
        } label: {
            HStack(spacing: 6) {
                // Status circle
                Circle()
                    .fill(tunnel.isActive ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                // Direction arrow
                Text(tunnel.direction.arrow)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                // Info
                VStack(alignment: .leading, spacing: 1) {
                    Text(tunnel.name.isEmpty ? tunnel.sshHost : tunnel.name)
                        .font(.system(.body))
                    Text(tunnel.displayString)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if tunnel.isActive {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .contextMenu {
            Button("Edit...") {
                editingTunnel = tunnel
            }
            Divider()
            Button("Delete", role: .destructive) {
                manager.deleteTunnel(id: tunnel.id)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            TunnelConfigSheet(manager: manager, mode: .add)
        }
        .sheet(item: $editingTunnel) { config in
            TunnelConfigSheet(manager: manager, mode: .edit(config))
        }
    }
}
