import Foundation
import Combine
import UserNotifications

@MainActor
class TunnelManager: ObservableObject {
    @Published var tunnels: [TunnelConfig] = []

    /// Running SSH processes keyed by tunnel ID
    private var processes: [UUID: Process] = [:]
    private var healthCheckTimer: Timer?

    init() {
        tunnels = TunnelConfig.loadAll()
        requestNotificationPermission()
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
        TunnelConfig.saveAll(tunnels)
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
        let config = tunnels[index]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

        var arguments = [
            "-N",      // No remote command
            "-T",      // Disable pseudo-terminal allocation
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "ExitOnForwardFailure=yes",
            config.direction.sshFlag,
            "\(config.localPort):127.0.0.1:\(config.remotePort)",
            config.sshHost
        ]

        process.arguments = arguments

        // Pipe stderr to avoid it going to the app's console
        let stderr = Pipe()
        process.standardError = stderr

        do {
            try process.run()
            processes[id] = process
            tunnels[index].isActive = true
            persist()
            print("Started tunnel: \(config.name) (\(config.displayString))")
        } catch {
            print("Failed to start tunnel \(config.name): \(error)")
            sendNotification(title: "Tunnel Failed", body: "Could not start \(config.name): \(error.localizedDescription)")
        }
    }

    func stopTunnel(id: UUID) {
        guard let index = tunnels.firstIndex(where: { $0.id == id }) else { return }

        if let process = processes[id] {
            if process.isRunning {
                process.terminate()
            }
            processes.removeValue(forKey: id)
        }

        tunnels[index].isActive = false
        persist()
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

            if let process = processes[tunnel.id] {
                if !process.isRunning {
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
        processes.removeValue(forKey: tunnel.id)

        if let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) {
            tunnels[index].isActive = false
            persist()
        }

        sendNotification(
            title: "Tunnel Disconnected",
            body: "\(tunnel.name) (\(tunnel.displayString)) has disconnected."
        )

        // Auto-reconnect
        if tunnel.autoReconnect {
            print("Auto-reconnecting tunnel: \(tunnel.name)")
            // Delay reconnect by 2 seconds to avoid rapid loops
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                Task { @MainActor in
                    self?.startTunnel(id: tunnel.id)
                }
            }
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification auth error: \(error)")
            }
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            }
        }
    }
}
