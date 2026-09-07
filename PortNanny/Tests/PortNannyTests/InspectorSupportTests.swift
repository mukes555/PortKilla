import XCTest
@testable import PortNannyCore
@testable import PortNanny

/// UI-2 support: the metrics ring buffer, peer classification, the HTTP
/// peek's title parsing, and the sparkline geometry.
final class InspectorSupportTests: XCTestCase {

    private func port(_ number: Int, pid: Int, cpu: Double, memoryKB: Int) -> PortInfo {
        PortInfo(port: number, pid: pid, processName: "node", command: "node", user: "me", memoryUsage: "1MB",
                 memorySizeKB: memoryKB, type: .nodejs, cpuPercent: cpu)
    }

    func testMetricsKeepACappedHistoryPerProcessAndForgetTheGone() {
        let metrics = MetricsHistory()
        for index in 0..<(MetricsHistory.capacity + 5) {
            metrics.record([port(3000, pid: 1, cpu: Double(index), memoryKB: 100 + index), port(3001, pid: 2, cpu: 0, memoryKB: 1)])
        }
        XCTAssertEqual(metrics.cpu(for: 1).count, MetricsHistory.capacity)
        XCTAssertEqual(metrics.cpu(for: 1).last, Double(MetricsHistory.capacity + 4))
        XCTAssertEqual(metrics.memoryKB(for: 1).first, 105, "the oldest samples fall off")
        XCTAssertEqual(metrics.tick, MetricsHistory.capacity + 5)

        metrics.record([port(3000, pid: 1, cpu: 1, memoryKB: 1)])
        XCTAssertTrue(metrics.cpu(for: 2).isEmpty, "a process that left the scan is forgotten")
        XCTAssertTrue(metrics.samples(for: 99).isEmpty)
    }

    func testMetricsRecordOneSamplePerProcessEvenWhenItListensTwice() {
        let metrics = MetricsHistory()
        metrics.record([port(3000, pid: 1, cpu: 5, memoryKB: 1), port(3001, pid: 1, cpu: 5, memoryKB: 1)])
        XCTAssertEqual(metrics.cpu(for: 1).count, 1)
    }

    func testPeersAreClassifiedAndSummarised() {
        XCTAssertEqual(NativeScanner.Peer(host: "127.0.0.1", port: 1).kind, "local")
        XCTAssertEqual(NativeScanner.Peer(host: "::1", port: 1).kind, "local")
        XCTAssertEqual(NativeScanner.Peer(host: "192.168.1.20", port: 1).kind, "lan")
        XCTAssertEqual(NativeScanner.Peer(host: "10.0.0.5", port: 1).kind, "lan")
        XCTAssertEqual(NativeScanner.Peer(host: "172.16.0.9", port: 1).kind, "lan")
        XCTAssertEqual(NativeScanner.Peer(host: "172.32.0.9", port: 1).kind, "remote")
        XCTAssertEqual(NativeScanner.Peer(host: "fe80::1", port: 1).kind, "lan")
        XCTAssertEqual(NativeScanner.Peer(host: "203.0.113.7", port: 1).kind, "remote")
        let peers = [NativeScanner.Peer(host: "127.0.0.1", port: 5), NativeScanner.Peer(host: "127.0.0.1", port: 6), NativeScanner.Peer(host: "192.168.1.2", port: 7)]
        XCTAssertEqual(NativeScanner.summary(of: peers), "3 clients: 2 local, 1 from the local network")
        XCTAssertEqual(NativeScanner.summary(of: []), "no clients connected")
        XCTAssertEqual(peers[2].label, "192.168.1.2:7")
    }

    func testHTTPPeekFindsTheTitle() {
        XCTAssertEqual(HTTPPeek.title(in: "<html><head><TITLE>\n  Vite   App \n</title></head>"), "Vite App")
        XCTAssertEqual(HTTPPeek.title(in: "<title lang=\"en\">Docs</title>"), "Docs")
        XCTAssertNil(HTTPPeek.title(in: "<html><body>no title</body></html>"))
        XCTAssertNil(HTTPPeek.title(in: "<title></title>"))
        XCTAssertEqual(HTTPPeek.title(in: "<title>" + String(repeating: "x", count: 200) + "</title>")?.count, 80)
        let result = HTTPPeek.Result(status: 200, server: "Vite", contentType: "text/html; charset=utf-8", title: "Vite App", redirect: nil)
        XCTAssertEqual(result.summary, "200 · text/html · Vite App")
    }

    func testSparklinePointsSpanTheWidthAndScaleToTheirRange() {
        let points = Sparkline.points(for: [0, 10, 5], in: CGSize(width: 100, height: 20))
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points.first?.x, 0)
        XCTAssertEqual(points.last?.x, 100)
        XCTAssertEqual(points[0].y, 18.5, accuracy: 0.01, "the minimum sits at the bottom inset")
        XCTAssertEqual(points[1].y, 1.5, accuracy: 0.01, "the maximum at the top inset")
        XCTAssertTrue(Sparkline.points(for: [1], in: CGSize(width: 100, height: 20)).isEmpty, "one sample is not a line")
        let flat = Sparkline.points(for: [3, 3, 3], in: CGSize(width: 100, height: 20))
        XCTAssertEqual(flat.map(\.y), [10, 10, 10], "a flat series sits at mid height")
    }

    func testTourAndPeekPreferencesDefaultOff() {
        let manager = PortManager.forTesting()
        defer { manager.discardTestDefaults() }
        XCTAssertFalse(manager.probeLocalServers)
        manager.probeLocalServers = true
        XCTAssertTrue(manager.defaults.bool(forKey: DefaultsKey.probeLocalServers))
        XCTAssertTrue(PaletteQuery.Command.allCases.contains(.tour))
    }
}
