import Foundation
import Combine

// MARK: - Direction Enum

enum TunnelDirection: String, Codable, CaseIterable, Identifiable {
    case localForward
    case remoteForward

    var id: String { rawValue }

    var label: String {
        switch self {
        case .localForward: return "Local → Remote (-L)"
        case .remoteForward: return "Remote → Local (-R)"
        }
    }

    var description: String {
        switch self {
        case .localForward: return "Local port → Remote machine (e.g. access remote service locally)"
        case .remoteForward: return "Remote port → Local machine (e.g. use local proxy on remote server)"
        }
    }

    var arrow: String {
        switch self {
        case .localForward: return "→"
        case .remoteForward: return "←"
        }
    }

    var sshFlag: String {
        switch self {
        case .localForward: return "-L"
        case .remoteForward: return "-R"
        }
    }
}

// MARK: - TunnelConfig

struct TunnelConfig: Codable, Identifiable {
    var id: UUID
    var name: String
    var sshHost: String
    var direction: TunnelDirection
    var localPort: Int
    var remotePort: Int
    var autoReconnect: Bool

    /// Runtime-only, not persisted
    var isActive: Bool = false
    var isStarting: Bool = false
    var lastError: String?

    init(
        id: UUID = UUID(),
        name: String = "",
        sshHost: String = "",
        direction: TunnelDirection = .remoteForward,
        localPort: Int = 6789,
        remotePort: Int = 6789,
        autoReconnect: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sshHost = sshHost
        self.direction = direction
        self.localPort = localPort
        self.remotePort = remotePort
        self.autoReconnect = autoReconnect
    }

    enum CodingKeys: String, CodingKey {
        case id, name, sshHost, direction, localPort, remotePort, autoReconnect
    }

    var displayString: String {
        "\(localPort) ↔ \(remotePort) @ \(sshHost)"
    }

    var forwardDescription: String {
        switch direction {
        case .localForward:
            return "localhost:\(localPort) → \(sshHost):\(remotePort)"
        case .remoteForward:
            return "\(sshHost):\(remotePort) → localhost:\(localPort)"
        }
    }

    var sshForwardArguments: [String] {
        switch direction {
        case .localForward:
            return [direction.sshFlag, "\(localPort):127.0.0.1:\(remotePort)"]
        case .remoteForward:
            return [direction.sshFlag, "\(remotePort):127.0.0.1:\(localPort)"]
        }
    }
}

// MARK: - Persistence

protocol TunnelConfigStoring {
    func loadAll() -> [TunnelConfig]
    func saveAll(_ configs: [TunnelConfig])
}

struct FileTunnelConfigStore: TunnelConfigStoring {
    let configURL: URL

    init(configURL: URL = FileTunnelConfigStore.defaultConfigURL) {
        self.configURL = configURL
    }

    func loadAll() -> [TunnelConfig] {
        guard let data = try? Data(contentsOf: configURL) else { return [] }
        do {
            var configs = try JSONDecoder().decode([TunnelConfig].self, from: data)
            for i in configs.indices {
                configs[i].isActive = false
                configs[i].isStarting = false
                configs[i].lastError = nil
            }
            return configs
        } catch {
            print("Failed to load tunnel configs: \(error)")
            return []
        }
    }

    func saveAll(_ configs: [TunnelConfig]) {
        do {
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(configs)
            try data.write(to: configURL, options: .atomic)
        } catch {
            print("Failed to save tunnel configs: \(error)")
        }
    }

    private static var defaultConfigURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("SSH Tunnel Toggle", isDirectory: true)
            .appendingPathComponent("config.json")
    }
}

extension TunnelConfig {
    static func loadAll() -> [TunnelConfig] {
        FileTunnelConfigStore().loadAll()
    }

    static func saveAll(_ configs: [TunnelConfig]) {
        FileTunnelConfigStore().saveAll(configs)
    }
}

// MARK: - SSH Config Parser

extension TunnelConfig {
    static func parseSSHConfigHosts() -> [String] {
        let sshConfigPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/config")

        guard let content = try? String(contentsOf: sshConfigPath, encoding: .utf8) else {
            return []
        }

        var hosts: [String] = []
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match "Host <pattern>" lines, skip wildcards
            if trimmed.hasPrefix("Host ") {
                let pattern = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
                // Skip wildcard patterns
                if !pattern.contains("*") && !pattern.contains("?") {
                    hosts.append(pattern)
                }
            }
        }

        return hosts
    }
}
