import Foundation
import Combine

@MainActor
class TunnelManager: ObservableObject {
    @Published var tunnels: [TunnelConfig] = []

    /// Running SSH processes keyed by tunnel ID
    private var processes: [UUID: RunningTunnel] = [:]
    private var healthCheckTimer: Timer?
    private let store: TunnelConfigStoring

    init(store: TunnelConfigStoring = FileTunnelConfigStore()) {
        self.store = store
        tunnels = store.loadAll()
        startHealthCheck()
    }

    deinit {
        healthCheckTimer?.invalidate()
    }

    // MARK: - CRUD

    func addTunnel(_ config: TunnelConfig) {
        tunnels.append(config)
        persist()
    }

    func updateTunnel(_ config: TunnelConfig) {
        if let index = tunnels.firstIndex(where: { $0.id == config.id }) {
            // Stop tunnel if it was active before update
            if tunnels[index].isActive {
                stopTunnel(id: config.id)
            }
            tunnels[index] = config
            persist()
        }
    }

    func deleteTunnel(id: UUID) {
        stopTunnel(id: id)
        tunnels.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        store.saveAll(tunnels)
    }

    // MARK: - Start / Stop

    func toggleTunnel(id: UUID) {
        if let index = tunnels.firstIndex(where: { $0.id == id }) {
            if tunnels[index].isActive {
                stopTunnel(id: id)
            } else {
                startTunnel(id: id)
            }
        }
    }

    func startTunnel(id: UUID) {
        guard let index = tunnels.firstIndex(where: { $0.id == id }) else { return }
        guard processes[id] == nil else { return }
        let config = tunnels[index]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

        let arguments = [
            "-N",      // No remote command
            "-T",      // Disable pseudo-terminal allocation
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "BatchMode=yes"
        ] + config.sshForwardArguments + [config.sshHost]

        process.arguments = arguments

        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        let running = RunningTunnel(process: process, stderrPipe: stderr)
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let message = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.appendProcessError(message, for: id)
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.handleProcessExit(id: id, status: process.terminationStatus)
            }
        }

        tunnels[index].isStarting = true
        tunnels[index].isActive = false
        tunnels[index].lastError = nil

        do {
            try process.run()
            processes[id] = running
            confirmStartedTunnel(id: id)
        } catch {
            tunnels[index].isStarting = false
            tunnels[index].isActive = false
            tunnels[index].lastError = error.localizedDescription
            sendNotification(title: "Tunnel Failed", body: "Could not start \(config.name): \(error.localizedDescription)")
        }
    }

    func stopTunnel(id: UUID) {
        guard let index = tunnels.firstIndex(where: { $0.id == id }) else { return }

        if let running = processes[id] {
            running.stderrPipe.fileHandleForReading.readabilityHandler = nil
            if running.process.isRunning {
                running.process.terminate()
            }
            processes.removeValue(forKey: id)
        }

        tunnels[index].isStarting = false
        tunnels[index].isActive = false
    }

    // MARK: - Health Check

    private func startHealthCheck() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkTunnelHealth()
            }
        }
    }

    private func checkTunnelHealth() {
        for tunnel in tunnels {
            guard tunnel.isActive else { continue }

            if let running = processes[tunnel.id] {
                if !running.process.isRunning {
                    // Tunnel died unexpectedly
                    handleTunnelDied(tunnel)
                }
            } else {
                // No process but marked active — fix state
                if let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) {
                    tunnels[index].isActive = false
                    persist()
                }
            }
        }
    }

    private func handleTunnelDied(_ tunnel: TunnelConfig) {
        let error = processError(for: tunnel.id, fallback: "SSH process exited.")
        processes[tunnel.id]?.stderrPipe.fileHandleForReading.readabilityHandler = nil
        processes.removeValue(forKey: tunnel.id)

        if let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) {
            tunnels[index].isStarting = false
            tunnels[index].isActive = false
            tunnels[index].lastError = error
            persist()
        }

        sendNotification(
            title: "Tunnel Disconnected",
            body: "\(tunnel.name) (\(tunnel.displayString)) has disconnected."
        )

        // Do not auto-reconnect after errors. Keep the failure visible until the user retries.
    }

    // MARK: - Notifications (via osascript, no bundleIdentifier needed)

    private func sendNotification(title: String, body: String) {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody = body.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\""
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        try? task.run()
    }

    private func confirmStartedTunnel(id: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            Task { @MainActor in
                guard let self, let index = self.tunnels.firstIndex(where: { $0.id == id }) else { return }
                guard let running = self.processes[id] else { return }

                if running.process.isRunning {
                    self.tunnels[index].isStarting = false
                    self.tunnels[index].isActive = true
                    self.tunnels[index].lastError = nil
                    print("Started tunnel: \(self.tunnels[index].name) (\(self.tunnels[index].forwardDescription))")
                } else {
                    self.handleProcessExit(id: id, status: running.process.terminationStatus)
                }
            }
        }
    }

    private func appendProcessError(_ message: String, for id: UUID) {
        guard let running = processes[id] else { return }
        running.stderrText += message
        if running.stderrText.count > 4_000 {
            running.stderrText = String(running.stderrText.suffix(4_000))
        }
        if let index = tunnels.firstIndex(where: { $0.id == id }) {
            tunnels[index].lastError = sanitizedError(running.stderrText)
        }
    }

    private func handleProcessExit(id: UUID, status: Int32) {
        guard let running = processes[id] else { return }
        let error = processError(for: id, fallback: "SSH exited with status \(status).")
        processes.removeValue(forKey: id)
        running.stderrPipe.fileHandleForReading.readabilityHandler = nil

        guard let index = tunnels.firstIndex(where: { $0.id == id }) else { return }
        tunnels[index].isStarting = false
        tunnels[index].isActive = false

        if status != 0 {
            tunnels[index].lastError = error
            sendNotification(title: "Tunnel Failed", body: tunnels[index].lastError ?? "SSH exited.")
        }

    }

    private func processError(for id: UUID, fallback: String) -> String {
        guard let stderr = processes[id]?.stderrText, !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return sanitizedError(stderr)
    }

    private func sanitizedError(_ message: String) -> String {
        message
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .suffix(3)
            .joined(separator: " ")
    }
}

private final class RunningTunnel {
    let process: Process
    let stderrPipe: Pipe
    var stderrText: String = ""

    init(process: Process, stderrPipe: Pipe) {
        self.process = process
        self.stderrPipe = stderrPipe
    }
}
