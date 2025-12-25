import XCTest
@testable import PortKilla

final class ScannerParsingTests: XCTestCase {
    private final class StubPortScanner: PortScanner {
        override func getProcessCommand(pid: Int) -> String {
            "/usr/local/bin/node /tmp/server.js"
        }

        override func getProcessMemory(pid: Int) -> (String, Int) {
            ("10MB", 10 * 1024)
        }
    }

    func testParsePortOutputExtractsPortsAndKeepsDifferentPids() {
        let output = """
        COMMAND PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node    111 me    23u  IPv4 0x0000000000000000      0t0  TCP *:3000 (LISTEN)
        node    222 me    23u  IPv6 0x0000000000000000      0t0  TCP [::1]:3000 (LISTEN)
        """

        let ports = StubPortScanner().parsePortOutput(output)

        XCTAssertEqual(ports.count, 2)
        XCTAssertTrue(ports.contains(where: { $0.port == 3000 && $0.pid == 111 }))
        XCTAssertTrue(ports.contains(where: { $0.port == 3000 && $0.pid == 222 }))
    }

    func testParsePortOutputDedupesSamePidSamePort() {
        let output = """
        COMMAND PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node    111 me    23u  IPv4 0x0000000000000000      0t0  TCP *:5173 (LISTEN)
        node    111 me    24u  IPv6 0x0000000000000000      0t0  TCP [::1]:5173 (LISTEN)
        """

        let ports = StubPortScanner().parsePortOutput(output)

        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports.first?.port, 5173)
        XCTAssertEqual(ports.first?.pid, 111)
    }

    func testParseProcessOutputDetectsJest() {
        let output = """
          123  2048 /usr/local/bin/node /tmp/node_modules/.bin/jest --watch
        """

        let processes = ProcessScanner().parseProcessOutput(output)

        XCTAssertEqual(processes.count, 1)
        XCTAssertEqual(processes.first?.pid, 123)
        XCTAssertEqual(processes.first?.type, .jest)
    }

    func testParseProcessOutputFiltersPortKilla() {
        let output = """
          999  1024 /Applications/PortKilaa.app/Contents/MacOS/PortKilaa
        """

        let processes = ProcessScanner().parseProcessOutput(output)
        XCTAssertTrue(processes.isEmpty)
    }
}

