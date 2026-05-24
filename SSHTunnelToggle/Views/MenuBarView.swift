import SwiftUI

struct MenuBarView: View {
    @ObservedObject var manager: TunnelManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("SSH Tunnel Toggle")
                    .font(.headline)
                Spacer()
                Button {
                    openConfigWindow(mode: .add)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            if manager.tunnels.isEmpty {
                VStack(spacing: 8) {
                    Text("No tunnels configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 16)
                    Button("Add Tunnel...") {
                        openConfigWindow(mode: .add)
                    }
                    .buttonStyle(.borderless)
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(manager.tunnels) { tunnel in
                            tunnelRow(tunnel)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(
                    minHeight: min(max(CGFloat(manager.tunnels.count) * 58, 64), 320),
                    maxHeight: 320
                )
            }

            Divider()

            // Footer
            HStack {
                Text("\(manager.tunnels.filter(\.isActive).count)/\(manager.tunnels.count) active")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 340)
    }

    private func openConfigWindow(mode: SheetMode) {
        TunnelConfigWindowRegistry.shared.open(manager: manager, mode: mode)
    }

    @ViewBuilder
    private func tunnelRow(_ tunnel: TunnelConfig) -> some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(tunnel.isActive ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(tunnel.isActive ? Color.green.opacity(0.3) : Color.clear, lineWidth: 3)
                )

            // Tunnel info
            VStack(alignment: .leading, spacing: 1) {
                Text(tunnel.name.isEmpty ? tunnel.sshHost : tunnel.name)
                    .font(.system(.body, weight: .medium))
                Text(tunnel.forwardDescription)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let lastError = tunnel.lastError, !lastError.isEmpty {
                    Text(lastError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            if tunnel.isStarting {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
            }

            Button {
                openConfigWindow(mode: .edit(tunnel))
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit tunnel")

            TunnelSwitch(isOn: tunnel.isActive, isDisabled: tunnel.isStarting) {
                manager.toggleTunnel(id: tunnel.id)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.03))
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit...") {
                openConfigWindow(mode: .edit(tunnel))
            }
            Divider()
            Button("Delete", role: .destructive) {
                manager.deleteTunnel(id: tunnel.id)
            }
        }
    }
}

private struct TunnelSwitch: View {
    let isOn: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Color.green : Color.gray.opacity(0.45))
                    .frame(width: 38, height: 20)

                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
                    .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .accessibilityLabel(isOn ? "Stop tunnel" : "Start tunnel")
    }
}

@MainActor
private final class TunnelConfigWindowRegistry {
    static let shared = TunnelConfigWindowRegistry()

    private var controllers: [TunnelConfigWindowController] = []

    private init() {}

    func open(manager: TunnelManager, mode: SheetMode) {
        let controller = TunnelConfigWindowController(manager: manager, mode: mode)
        controllers.append(controller)
        controller.onClose = { [weak self, weak controller] in
            guard let controller else { return }
            self?.controllers.removeAll { $0 === controller }
        }
        controller.show()
    }
}

@MainActor
private final class TunnelConfigWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(manager: TunnelManager, mode: SheetMode) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = mode.isEditing ? "Edit Tunnel" : "Add Tunnel"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace]
        window.tabbingMode = .disallowed

        super.init(window: window)

        window.delegate = self
        window.contentView = NSHostingView(
            rootView: TunnelConfigSheet(manager: manager, form: TunnelConfigFormModel(mode: mode), mode: mode) { [weak self] in
                self?.close()
            }
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        window.center()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
