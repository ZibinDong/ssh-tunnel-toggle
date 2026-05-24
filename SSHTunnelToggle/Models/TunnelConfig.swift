import Foundation
import Combine

// MARK: - Direction Enum

enum TunnelDirection: String, Codable, CaseIterable, Identifiable {
    case localForward
    case remoteForward

    var id: String { rawValue }

    var label: String {
        switch self {
        case .localForward: return "Local Forward (-L)"
        case .remoteForward: return "Remote Forward (-R)"
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

    init(
        id: UUID = UUID(),
        name: String = "",
        sshHost: String = "",
        direction: TunnelDirection = .localForward,
        localPort: Int = 8080,
        remotePort: Int = 80,
        autoReconnect: Bool = true
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
}

// MARK: - Persistence

extension TunnelConfig {
    private static var configDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SSH Tunnel Toggle", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var configURL: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    static func loadAll() -> [TunnelConfig] {
        let url = configURL
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            var configs = try JSONDecoder().decode([TunnelConfig].self, from: data)
            // Ensure isActive is false on load
            for i in configs.indices { configs[i].isActive = false }
            return configs
        } catch {
            print("Failed to load tunnel configs: \(error)")
            return []
        }
    }

    static func saveAll(_ configs: [TunnelConfig]) {
        do {
            let data = try JSONEncoder().encode(configs)
            try data.write(to: configURL, options: .atomic)
        } catch {
            print("Failed to save tunnel configs: \(error)")
        }
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
