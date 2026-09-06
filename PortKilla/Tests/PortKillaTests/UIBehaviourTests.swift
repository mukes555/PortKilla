import XCTest
@testable import PortKilla

/// Regression tests for the v1.12.0 UI batch (the parts that are pure logic).
final class UIBehaviourTests: XCTestCase {

    private func port(_ number: Int, type: PortInfo.PortType, container: String? = nil) -> PortInfo {
        PortInfo(port: number, pid: number, processName: "p", command: "p", user: "me", memoryUsage: "",
                 memorySizeKB: 0, type: type, containerName: container)
    }

    func testBulkKillFollowsTheActiveFilter() {
        let web = port(3000, type: .nodejs)
        let db = port(5432, type: .database)
        let docker = port(8080, type: .other, container: "api")

        XCTAssertTrue(PortListView.ListFilter.all.includesInBulkKill(web))
        XCTAssertFalse(PortListView.ListFilter.all.includesInBulkKill(db), "⌘K on All keeps the classic Kill All Dev scope")
        XCTAssertTrue(PortListView.ListFilter.database.includesInBulkKill(db))
        XCTAssertFalse(PortListView.ListFilter.database.includesInBulkKill(web), "the Databases tab must not kill web servers it doesn't show")
        XCTAssertTrue(PortListView.ListFilter.docker.includesInBulkKill(docker))
        XCTAssertFalse(PortListView.ListFilter.tests.includesInBulkKill(web))
    }

    func testBulkKillLabelsNameTheirScope() {
        XCTAssertEqual(PortListView.ListFilter.all.bulkKillLabel, "Kill All Dev")
        XCTAssertEqual(PortListView.ListFilter.database.bulkKillLabel, "Kill All Databases")
        XCTAssertEqual(PortListView.ListFilter.docker.bulkKillLabel, "Kill All Docker")
        XCTAssertEqual(PortListView.ListFilter.tests.bulkKillLabel, "Kill All Tests")
    }

    func testHistoryLimitTrimsImmediately() {
        let manager = PortManager.forTesting()
        defer { manager.discardTestDefaults() }
        manager.historyLimit = 100
        XCTAssertEqual(manager.history.maxHistoryItems, 100)
        manager.historyLimit = 50
        XCTAssertEqual(manager.history.maxHistoryItems, 50)
        XCTAssertLessThanOrEqual(manager.history.history.count, 50)
    }
}
