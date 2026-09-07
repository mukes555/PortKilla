import XCTest
@testable import PortNannyCore
@testable import PortNanny

final class ScannerParsingTests: XCTestCase {
    private func makeProcessTable() -> ProcessTable {
        ProcessTable(psOutput: """
          111  1  10240  1.5  03:12 /usr/local/bin/node /tmp/server.js
          222  1  10240  0.0  03:12 /usr/local/bin/node /tmp/server.js
        """)
    }

    func testParsePortOutputExtractsPortsAndKeepsDifferentPids() {
        let output = """
        COMMAND PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node    111 me    23u  IPv4 0x0000000000000000      0t0  TCP *:3000 (LISTEN)
        node    222 me    23u  IPv6 0x0000000000000000      0t0  TCP [::1]:3000 (LISTEN)
        """

        let ports = PortScanner().parsePortOutput(output, processes: makeProcessTable())

        XCTAssertEqual(ports.count, 2)
        XCTAssertTrue(ports.contains(where: { $0.port == 3000 && $0.pid == 111 }))
        XCTAssertTrue(ports.contains(where: { $0.port == 3000 && $0.pid == 222 }))
    }

    func testParsePortOutputTakesDetailsFromProcessTable() {
        let output = """
        COMMAND PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node    111 me    23u  IPv4 0x0000000000000000      0t0  TCP *:3000 (LISTEN)
        """

        let ports = PortScanner().parsePortOutput(output, processes: makeProcessTable())

        XCTAssertEqual(ports.first?.command, "/usr/local/bin/node /tmp/server.js")
        XCTAssertEqual(ports.first?.memorySizeKB, 10240)
        XCTAssertEqual(ports.first?.type, .nodejs)
        XCTAssertEqual(ports.first?.cpuPercent, 1.5)
        XCTAssertEqual(ports.first?.age, "3m")
    }

    func testUdpParsingTagsProtoAndSkipsEphemeralAndConnected() {
        let output = """
        COMMAND PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        rapportd 111 me   5u  IPv4 0x0000000000000000      0t0  UDP *:5353
        chrome   222 me   6u  IPv4 0x0000000000000000      0t0  UDP 192.168.1.5:52000->1.2.3.4:443
        chrome   222 me   7u  IPv4 0x0000000000000000      0t0  UDP *:60000
        """

        let ports = PortScanner().parsePortOutput(output, processes: makeProcessTable(), proto: "udp")

        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports.first?.port, 5353)
        XCTAssertEqual(ports.first?.proto, "udp")
    }

    func testTcpAndUdpOnSamePortGetDistinctIds() {
        let tcp = PortInfo(port: 5353, pid: 1, processName: "a", command: "", user: "u", memoryUsage: "", memorySizeKB: 0, type: .other, proto: "tcp")
        let udp = PortInfo(port: 5353, pid: 1, processName: "a", command: "", user: "u", memoryUsage: "", memorySizeKB: 0, type: .other, proto: "udp")
        XCTAssertNotEqual(tcp.id, udp.id)
    }

    func testParsePortOutputDedupesSamePidSamePort() {
        let output = """
        COMMAND PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node    111 me    23u  IPv4 0x0000000000000000      0t0  TCP *:5173 (LISTEN)
        node    111 me    24u  IPv6 0x0000000000000000      0t0  TCP [::1]:5173 (LISTEN)
        """

        let ports = PortScanner().parsePortOutput(output, processes: makeProcessTable())

        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports.first?.port, 5173)
        XCTAssertEqual(ports.first?.pid, 111)
    }

    func testParsePortOutputDetectsExposedBind() {
        let output = """
        COMMAND PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node    111 me    23u  IPv4 0x0000000000000000      0t0  TCP *:3000 (LISTEN)
        node    222 me    23u  IPv4 0x0000000000000000      0t0  TCP 127.0.0.1:4000 (LISTEN)
        """

        let ports = PortScanner().parsePortOutput(output, processes: makeProcessTable())

        XCTAssertEqual(ports.first(where: { $0.port == 3000 })?.isExposed, true)
        XCTAssertEqual(ports.first(where: { $0.port == 4000 })?.isExposed, false)
        XCTAssertEqual(ports.first(where: { $0.port == 4000 })?.bindAddress, "127.0.0.1")
    }

    func testExposedBindSurvivesIPv4IPv6Merge() {
        // Localhost line first, wildcard dupe second: the merged row must
        // still read as exposed.
        let output = """
        COMMAND PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node    111 me    23u  IPv4 0x0000000000000000      0t0  TCP 127.0.0.1:3000 (LISTEN)
        node    111 me    24u  IPv6 0x0000000000000000      0t0  TCP *:3000 (LISTEN)
        """

        let ports = PortScanner().parsePortOutput(output, processes: makeProcessTable())

        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports.first?.isExposed, true)
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

    func testParseProcessOutputFiltersPortNanny() {
        let output = """
          999  1024 /Applications/PortKilaa.app/Contents/MacOS/PortKilaa
        """

        let processes = ProcessScanner().parseProcessOutput(output)
        XCTAssertTrue(processes.isEmpty)
    }
}
