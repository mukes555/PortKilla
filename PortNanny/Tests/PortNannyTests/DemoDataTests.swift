import XCTest
@testable import PortNannyCore
@testable import PortNanny

/// README images come from scripted data, never from the Mac that renders them.
final class DemoDataTests: XCTestCase {

    func testTheDemoPortsCarryNothingFromThisMac() {
        let home = NSHomeDirectory()
        let ports = DemoData.ports(includePort3000: true)
        XCTAssertGreaterThan(ports.count, 5, "enough rows for a screenshot")
        for port in ports {
            XCTAssertNotEqual(port.user, NSUserName(), "\(port.port)")
            XCTAssertFalse(port.command.contains(home), port.command)
            XCTAssertFalse((port.projectPath ?? "").contains(home), port.projectPath ?? "")
        }
        XCTAssertFalse(DemoData.test.command.contains(home))
    }

    func testDemoModeNeverScans() {
        setenv("PORTNANNY_SNAPSHOT_DATA", "demo", 1)
        defer { unsetenv("PORTNANNY_SNAPSHOT_DATA") }
        let manager = PortManager.forTesting()
        defer { manager.discardTestDefaults() }
        XCTAssertTrue(manager.usesDemoData)
        manager.currentUser = DemoData.user
        manager.activePorts = DemoData.ports(includePort3000: true)
        XCTAssertEqual(manager.hiddenPortsCount, 0, "the scripted rows belong to the demo user, not to a system account")
        manager.refresh()
        XCTAssertFalse(manager.isRefreshing, "a refresh in demo mode is a no-op")
        XCTAssertEqual(manager.activePorts.count, DemoData.ports(includePort3000: true).count, "the scripted ports stay")
    }
}
