import XCTest
@testable import PortKilla

final class ProcessTableTests: XCTestCase {

    func testParsesEntriesWithCommandsContainingSpaces() {
        let table = ProcessTable(psOutput: """
          100  1  2048  12.5  1-02:30:00 /usr/local/bin/node server.js --port 3000
          200  100  1024  0.0  05:00 /bin/sleep 100
        """)

        XCTAssertEqual(table.command(for: 100), "/usr/local/bin/node server.js --port 3000")
        XCTAssertEqual(table.rssKB(for: 100), 2048)
        XCTAssertEqual(table.rssKB(for: 200), 1024)
        XCTAssertEqual(table.cpuPercent(for: 100), 12.5)
        XCTAssertEqual(table.elapsed(for: 100), "1-02:30:00")
    }

    func testChildLookup() {
        let table = ProcessTable(psOutput: """
          100  1  2048  0.0  05:00 /usr/local/bin/node server.js
          200  100  1024  0.0  05:00 /bin/sleep 100
          300  100  1024  0.0  05:00 /bin/sleep 200
        """)

        let children = table.children(of: 100)
        XCTAssertEqual(children.map(\.pid).sorted(), [200, 300])
        XCTAssertEqual(children.first?.name, "sleep")
        XCTAssertTrue(table.children(of: 200).isEmpty)
    }

    func testIgnoresMalformedLines() {
        let table = ProcessTable(psOutput: """
          garbage line
          100  1  2048  0.0  05:00 /usr/local/bin/node
          not-a-pid  1  2048  0.0  05:00 /bin/thing
        """)

        XCTAssertEqual(table.command(for: 100), "/usr/local/bin/node")
        XCTAssertEqual(table.allEntries.count, 1)
    }

    func testElapsedHumanize() {
        XCTAssertEqual(ElapsedFormat.humanize("00:45"), "45s")
        XCTAssertEqual(ElapsedFormat.humanize("12:45"), "12m")
        XCTAssertEqual(ElapsedFormat.humanize("03:12:45"), "3h 12m")
        XCTAssertEqual(ElapsedFormat.humanize("2-03:12:45"), "2d 3h")
        XCTAssertNil(ElapsedFormat.humanize(""))
    }

    func testCaptureIncludesCurrentProcess() {
        let table = ProcessTable.capture()
        let myPid = Int(Foundation.ProcessInfo.processInfo.processIdentifier)
        XCTAssertNotNil(table.command(for: myPid), "capture() should list the test runner itself")
    }
}
