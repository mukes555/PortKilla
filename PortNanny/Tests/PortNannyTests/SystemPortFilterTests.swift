import XCTest
@testable import PortNannyCore
@testable import PortNanny

final class SystemPortFilterTests: XCTestCase {

    private func makePort(user: String, command: String, type: PortInfo.PortType = .other) -> PortInfo {
        PortInfo(
            port: 3000, pid: 42, processName: "proc", command: command,
            user: user, memoryUsage: "1MB", memorySizeKB: 1024, type: type
        )
    }

    func testOtherUsersProcessesAreSystem() {
        let manager = PortManager.forTesting()
        defer { manager.discardTestDefaults() }
        XCTAssertTrue(manager.isSystemPort(makePort(user: "root", command: "/opt/thing")))
        XCTAssertTrue(manager.isSystemPort(makePort(user: "_mdnsresponder", command: "/usr/sbin/mDNSResponder")))
    }

    func testSystemBinariesAreSystemEvenWhenUserOwned() {
        let manager = PortManager.forTesting()
        defer { manager.discardTestDefaults() }
        let me = NSUserName()
        XCTAssertTrue(manager.isSystemPort(makePort(user: me, command: "/System/Library/CoreServices/thing")))
        XCTAssertTrue(manager.isSystemPort(makePort(user: me, command: "/usr/libexec/rapportd")))
    }

    func testUserDevProcessIsNotSystem() {
        let manager = PortManager.forTesting()
        defer { manager.discardTestDefaults() }
        let me = NSUserName()
        XCTAssertFalse(manager.isSystemPort(makePort(user: me, command: "/usr/local/bin/node server.js")))
    }
}
