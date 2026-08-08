import XCTest
@testable import PortKilla

final class WatchAndUpdateTests: XCTestCase {

    // MARK: - Watch events

    func testFreedPortProducesFreedEvent() {
        let events = PortManager.watchEvents(
            watched: [3000],
            previous: [3000: "node"],
            current: [:]
        )
        XCTAssertEqual(events, [PortManager.WatchEvent(port: 3000, kind: .freed)])
    }

    func testNewlyOccupiedPortProducesOccupiedEvent() {
        let events = PortManager.watchEvents(
            watched: [5432],
            previous: [:],
            current: [5432: "postgres"]
        )
        XCTAssertEqual(events, [PortManager.WatchEvent(port: 5432, kind: .occupied(by: "postgres"))])
    }

    func testUnchangedPortsProduceNoEvents() {
        let stillBusy = PortManager.watchEvents(watched: [3000], previous: [3000: "node"], current: [3000: "node"])
        let stillFree = PortManager.watchEvents(watched: [3000], previous: [:], current: [:])
        XCTAssertTrue(stillBusy.isEmpty)
        XCTAssertTrue(stillFree.isEmpty)
    }

    func testOccupantSwapProducesOccupiedEvent() {
        // Regression: a restart/swap (node -> python) with no idle scan between
        // must still fire .occupied so the guard kills the replacement.
        let events = PortManager.watchEvents(
            watched: [3000],
            previous: [3000: "node"],
            current: [3000: "python"]
        )
        XCTAssertEqual(events, [PortManager.WatchEvent(port: 3000, kind: .occupied(by: "python"))])
    }

    func testUnwatchedPortsAreIgnored() {
        let events = PortManager.watchEvents(watched: [], previous: [3000: "node"], current: [:])
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Version comparison

    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isVersion("1.3.0", newerThan: "1.2.0"))
        XCTAssertTrue(UpdateChecker.isVersion("1.10.0", newerThan: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isVersion("2.0", newerThan: "1.9.9"))
        XCTAssertFalse(UpdateChecker.isVersion("1.2.0", newerThan: "1.2.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.2.0", newerThan: "1.3.0"))
    }

    func testParseTagName() {
        let json = #"{"tag_name": "v1.4.0", "name": "Release"}"#.data(using: .utf8)!
        XCTAssertEqual(UpdateChecker.parseTagName(json), "1.4.0")

        let bare = #"{"tag_name": "2.0.1"}"#.data(using: .utf8)!
        XCTAssertEqual(UpdateChecker.parseTagName(bare), "2.0.1")

        XCTAssertNil(UpdateChecker.parseTagName(Data("not json".utf8)))
    }

    // MARK: - lsof cwd parsing

    func testParseCwdOutput() {
        let output = """
        p123
        fcwd
        n/Users/dev/projects/my-app
        p456
        fcwd
        n/opt/homebrew/var
        """
        let result = PortScanner.parseCwdOutput(output)
        XCTAssertEqual(result[123], "/Users/dev/projects/my-app")
        XCTAssertEqual(result[456], "/opt/homebrew/var")
    }
}
