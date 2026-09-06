import XCTest
@testable import PortKilla

final class ScanBenchmarkTests: XCTestCase {
    func testNativeScanSpeed() {
        // Warm-up
        _ = NativeScanner.capture()

        let start = Date()
        let snapshot = NativeScanner.capture()
        let elapsed = Date().timeIntervalSince(start)

        print("NATIVE-BENCH: \(snapshot?.samples.count ?? 0) processes + \(snapshot?.listeners.count ?? 0) listeners in \(Int(elapsed * 1000))ms (one pass)")
        XCTAssertLessThan(elapsed, 1.0)
    }

    /// The whole refresh as PortManager runs it, enrichment included: this is
    /// where attribution, cwd lookups, and children used to hide their cost.
    func testFullRefreshSpeed() {
        let scanner = PortScanner()
        _ = try? scanner.scanActivePorts(processes: ProcessTable.capture()) // warm caches

        let start = Date()
        let table = ProcessTable.capture()
        let ports = (try? scanner.scanActivePorts(processes: table, depth: .full)) ?? []
        let full = Date().timeIntervalSince(start)

        let lightStart = Date()
        _ = try? scanner.scanActivePorts(processes: ProcessTable.capture(), depth: .light)
        let light = Date().timeIntervalSince(lightStart)

        print("FULL-BENCH: \(ports.count) ports enriched in \(Int(full * 1000))ms; light refresh \(Int(light * 1000))ms; facts cached: \(ProcessFacts.shared.count)")
        XCTAssertLessThan(full, 1.0)
    }
}
