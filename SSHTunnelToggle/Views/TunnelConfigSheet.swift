import SwiftUI

enum SheetMode {
    case add
    case edit(TunnelConfig)

    var isEditing: Bool {
        if case .edit = self { return true }
        return false
    }
}

struct TunnelConfigSheet: View {
    @ObservedObject var manager: TunnelManager
    @ObservedObject var form: TunnelConfigFormModel
    let mode: SheetMode
    let onClose: () -> Void
    private let sshConfigHosts = TunnelConfig.parseSSHConfigHosts()

    var body: some View {
        VStack(spacing: 16) {
            Text(mode.isEditing ? "Edit Tunnel" : "Add Tunnel")
                .font(.headline)

            Form {
                LabeledContent("Name") {
                    AppKitTextField(text: $form.name, placeholder: "Optional display name")
                }

                LabeledContent("SSH Host") {
                    SSHHostComboBox(
                        text: $form.sshHost,
                        hosts: sshConfigHosts,
                        placeholder: "e.g. Galaxea_dev"
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Picker("Direction", selection: $form.direction) {
                        ForEach(TunnelDirection.allCases) { dir in
                            Text(dir.label).tag(dir)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(form.direction.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("Local Port")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        AppKitTextField(text: $form.localPort, placeholder: "6789")
                            .frame(width: 80)
                    }

                    Image(systemName: "arrow.left.and.right")
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)

                    VStack(alignment: .leading) {
                        Text("Remote Port")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        AppKitTextField(text: $form.remotePort, placeholder: "6789")
                            .frame(width: 80)
                    }
                }

            }
            .formStyle(.grouped)

            HStack {
                if mode.isEditing {
                    Button("Delete", role: .destructive) {
                        if case .edit(let config) = mode {
                            manager.deleteTunnel(id: config.id)
                        }
                        onClose()
                    }
                }

                Spacer()

                Button("Cancel") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!form.isValid)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func save() {
        guard let lp = Int(form.localPort), let rp = Int(form.remotePort) else { return }
        switch mode {
        case .add:
            let config = TunnelConfig(
                name: form.name,
                sshHost: form.trimmedSSHHost,
                direction: form.direction,
                localPort: lp,
                remotePort: rp,
                autoReconnect: false
            )
            manager.addTunnel(config)

        case .edit(let original):
            var updated = original
            updated.name = form.name
            updated.sshHost = form.trimmedSSHHost
            updated.direction = form.direction
            updated.localPort = lp
            updated.remotePort = rp
            updated.autoReconnect = false
            manager.updateTunnel(updated)
        }
        onClose()
    }
}

@MainActor
final class TunnelConfigFormModel: ObservableObject {
    @Published var name: String
    @Published var sshHost: String
    @Published var direction: TunnelDirection
    @Published var localPort: String
    @Published var remotePort: String

    init(mode: SheetMode) {
        switch mode {
        case .add:
            name = ""
            sshHost = ""
            direction = .remoteForward
            localPort = "6789"
            remotePort = "6789"
        case .edit(let config):
            name = config.name
            sshHost = config.sshHost
            direction = config.direction
            localPort = String(config.localPort)
            remotePort = String(config.remotePort)
        }
    }

    var trimmedSSHHost: String {
        sshHost.trimmingCharacters(in: .whitespaces)
    }

    var isValid: Bool {
        guard !trimmedSSHHost.isEmpty else { return false }
        guard let lp = Int(localPort), lp > 0, lp <= 65535 else { return false }
        guard let rp = Int(remotePort), rp > 0, rp <= 65535 else { return false }
        return true
    }
}

private struct SSHHostComboBox: NSViewRepresentable {
    @Binding var text: String
    let hosts: [String]
    let placeholder: String

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.stringValue = text
        comboBox.placeholderString = placeholder
        comboBox.bezelStyle = .roundedBezel
        comboBox.isBordered = true
        comboBox.drawsBackground = true
        comboBox.isEditable = true
        comboBox.completes = true
        comboBox.numberOfVisibleItems = min(max(hosts.count, 1), 12)
        comboBox.addItems(withObjectValues: hosts)
        comboBox.delegate = context.coordinator
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        context.coordinator.text = $text

        if comboBox.stringValue != text {
            comboBox.stringValue = text
        }
        comboBox.placeholderString = placeholder

        let existingHosts = (0..<comboBox.numberOfItems).compactMap { comboBox.itemObjectValue(at: $0) as? String }
        if existingHosts != hosts {
            comboBox.removeAllItems()
            comboBox.addItems(withObjectValues: hosts)
            comboBox.numberOfVisibleItems = min(max(hosts.count, 1), 12)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSComboBoxDelegate, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            updateText(textField.stringValue)
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            if let selectedValue = comboBox.objectValueOfSelectedItem as? String {
                updateText(selectedValue)
            } else {
                updateText(comboBox.stringValue)
            }
        }

        private func updateText(_ newValue: String) {
            if text.wrappedValue != newValue {
                text.wrappedValue = newValue
            }
        }
    }
}

private struct AppKitTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.placeholderString = placeholder
        textField.bezelStyle = .roundedBezel
        textField.isBordered = true
        textField.drawsBackground = true
        textField.delegate = context.coordinator
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        if textField.stringValue != text {
            textField.stringValue = text
        }
        textField.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text.wrappedValue = textField.stringValue
        }
    }
}
