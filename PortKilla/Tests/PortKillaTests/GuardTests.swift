import XCTest
@testable import PortKillaCore
@testable import PortKilla

final class GuardTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Isolate persisted watch/guard state
        UserDefaults.standard.removeObject(forKey: "PortKilla.watchedPorts")
        UserDefaults.standard.removeObject(forKey: "PortKilla.guardedPorts")
    }

    func testGuardingImpliesWatching() {
        let manager = PortManager.forTesting()
        defer { manager.discardTestDefaults() }
        manager.stopAutoRefresh()

        manager.toggleGuard(4242)
        XCTAssertTrue(manager.isGuarded(4242))
        XCTAssertTrue(manager.isWatched(4242))
    }

    func testUnwatchingRemovesGuard() {
        let manager = PortManager.forTesting()
        defer { manager.discardTestDefaults() }
        manager.stopAutoRefresh()

        manager.toggleGuard(4242)
        manager.toggleWatch(4242) // unwatch
        XCTAssertFalse(manager.isWatched(4242))
        XCTAssertFalse(manager.isGuarded(4242))
    }

    func testToggleGuardOffLeavesWatchOn() {
        let manager = PortManager.forTesting()
        defer { manager.discardTestDefaults() }
        manager.stopAutoRefresh()

        manager.toggleGuard(4242)
        manager.toggleGuard(4242) // guard off
        XCTAssertFalse(manager.isGuarded(4242))
        XCTAssertTrue(manager.isWatched(4242), "removing a guard should not silently unwatch")
    }
}
