import XCTest
@testable import SSHTunnelToggle

final class TunnelConfigTests: XCTestCase {
    func testDefaultTunnelDoesNotAutoReconnect() {
        XCTAssertFalse(TunnelConfig().autoReconnect)
    }

    func testLocalForwardBuildsLocalPortToRemotePortArguments() {
        let config = TunnelConfig(
            sshHost: "devbox",
            direction: .localForward,
            localPort: 8080,
            remotePort: 80
        )

        XCTAssertEqual(config.sshForwardArguments, ["-L", "8080:127.0.0.1:80"])
    }

    func testRemoteForwardBuildsRemotePortToLocalPortArguments() {
        let config = TunnelConfig(
            sshHost: "devbox",
            direction: .remoteForward,
            localPort: 6789,
            remotePort: 9000
        )

        XCTAssertEqual(config.sshForwardArguments, ["-R", "9000:127.0.0.1:6789"])
    }

    @MainActor
    func testManagerLoadsPersistedTunnelsAndAddTunnelPersistsImmediately() throws {
        let store = InMemoryTunnelStore(initialConfigs: [
            TunnelConfig(name: "existing", sshHost: "devbox", direction: .localForward, localPort: 8080, remotePort: 80)
        ])
        let manager = TunnelManager(store: store)

        XCTAssertEqual(manager.tunnels.map(\.name), ["existing"])

        manager.addTunnel(TunnelConfig(name: "new", sshHost: "remote", direction: .remoteForward, localPort: 6789, remotePort: 9000))

        XCTAssertEqual(manager.tunnels.map(\.name), ["existing", "new"])
        XCTAssertEqual(store.savedConfigs.map(\.name), ["existing", "new"])
    }
}

private final class InMemoryTunnelStore: TunnelConfigStoring {
    private let initialConfigs: [TunnelConfig]
    private(set) var savedConfigs: [TunnelConfig] = []

    init(initialConfigs: [TunnelConfig]) {
        self.initialConfigs = initialConfigs
    }

    func loadAll() -> [TunnelConfig] {
        initialConfigs
    }

    func saveAll(_ configs: [TunnelConfig]) {
        savedConfigs = configs
    }
}
