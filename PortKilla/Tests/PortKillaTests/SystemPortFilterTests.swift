import XCTest
@testable import PortKilla

final class SystemPortFilterTests: XCTestCase {

    private func makePort(user: String, command: String, type: PortInfo.PortType = .other) -> PortInfo {
        PortInfo(
            port: 3000, pid: 42, processName: "proc", command: command,
            user: user, memoryUsage: "1MB", memorySizeKB: 1024, type: type
        )
    }

    func testOtherUsersProcessesAreSystem() {
        let manager = PortManager()
        XCTAssertTrue(manager.isSystemPort(makePort(user: "root", command: "/opt/thing")))
        XCTAssertTrue(manager.isSystemPort(makePort(user: "_mdnsresponder", command: "/usr/sbin/mDNSResponder")))
    }

    func testSystemBinariesAreSystemEvenWhenUserOwned() {
        let manager = PortManager()
        let me = NSUserName()
        XCTAssertTrue(manager.isSystemPort(makePort(user: me, command: "/System/Library/CoreServices/thing")))
        XCTAssertTrue(manager.isSystemPort(makePort(user: me, command: "/usr/libexec/rapportd")))
    }

    func testUserDevProcessIsNotSystem() {
        let manager = PortManager()
        let me = NSUserName()
        XCTAssertFalse(manager.isSystemPort(makePort(user: me, command: "/usr/local/bin/node server.js")))
    }
}
