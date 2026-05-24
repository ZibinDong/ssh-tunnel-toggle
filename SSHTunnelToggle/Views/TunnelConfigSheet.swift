import SwiftUI

enum SheetMode {
    case add
    case edit(TunnelConfig)
}

struct TunnelConfigSheet: View {
    @ObservedObject var manager: TunnelManager
    let mode: SheetMode

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var sshHost: String = ""
    @State private var direction: TunnelDirection = .localForward
    @State private var localPort: Int = 8080
    @State private var remotePort: Int = 80
    @State private var autoReconnect: Bool = true

    @State private var sshHosts: [String] = []

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(isEditing ? "Edit Tunnel" : "Add Tunnel")
                .font(.headline)

            Form {
                TextField("Name", text: $name, prompt: Text("Optional display name"))

                HStack {
                    ComboBox(
                        items: sshHosts,
                        selection: $sshHost,
                        prompt: "SSH Host"
                    )
                }

                Picker("Direction", selection: $direction) {
                    ForEach(TunnelDirection.allCases) { dir in
                        Text(dir.label).tag(dir)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("Local Port")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("", value: $localPort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }

                    Image(systemName: "arrow.left.and.right")
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)

                    VStack(alignment: .leading) {
                        Text("Remote Port")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("", value: $remotePort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }

                Toggle("Auto-Reconnect", isOn: $autoReconnect)
            }
            .formStyle(.grouped)

            HStack {
                if isEditing {
                    Button("Delete", role: .destructive) {
                        if case .edit(let config) = mode {
                            manager.deleteTunnel(id: config.id)
                        }
                        dismiss()
                    }
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(sshHost.isEmpty || localPort < 1 || remotePort < 1)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            loadSSHHosts()
            if case .edit(let config) = mode {
                name = config.name
                sshHost = config.sshHost
                direction = config.direction
                localPort = config.localPort
                remotePort = config.remotePort
                autoReconnect = config.autoReconnect
            }
        }
    }

    private func loadSSHHosts() {
        sshHosts = TunnelConfig.parseSSHConfigHosts()
    }

    private func save() {
        switch mode {
        case .add:
            let config = TunnelConfig(
                name: name,
                sshHost: sshHost,
                direction: direction,
                localPort: localPort,
                remotePort: remotePort,
                autoReconnect: autoReconnect
            )
            manager.addTunnel(config)

        case .edit(let original):
            var updated = original
            updated.name = name
            updated.sshHost = sshHost
            updated.direction = direction
            updated.localPort = localPort
            updated.remotePort = remotePort
            updated.autoReconnect = autoReconnect
            manager.updateTunnel(updated)
        }
        dismiss()
    }
}

// MARK: - ComboBox (NSComboBox wrapper)

struct ComboBox: NSViewRepresentable {
    let items: [String]
    @Binding var selection: String
    let prompt: String

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.isEditable = true
        comboBox.placeholderString = prompt
       comboBox.completes = true
        comboBox.usesDataSource = false
        comboBox.numberOfVisibleItems = 10
        comboBox.delegate = context.coordinator
        comboBox.target = context.coordinator
        comboBox.action = #selector(Coordinator.textDidChange(_:))
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        // Only update items if they changed
        let currentItems = (0..<comboBox.numberOfItems).compactMap { comboBox.itemObjectValue(at: $0) as? String }
        if currentItems != items {
            comboBox.removeAllItems()
            comboBox.addItems(withObjectValues: items)
        }

        // Set the selection without triggering delegate
        if comboBox.stringValue != selection {
            comboBox.stringValue = selection
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    class Coordinator: NSObject, NSComboBoxDelegate {
        var selection: Binding<String>

        init(selection: Binding<String>) {
            self.selection = selection
        }

        @objc func textDidChange(_ sender: NSComboBox) {
            selection.wrappedValue = sender.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            selection.wrappedValue = comboBox.stringValue
        }
    }
}
