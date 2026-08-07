import XCTest
@testable import PortKilla

final class ScanBenchmarkTests: XCTestCase {
    func testNativeScanSpeed() {
        // Warm-up
        _ = NativeScanner.captureSamples()
        _ = NativeScanner.allListeners()

        let start = Date()
        let samples = NativeScanner.captureSamples()
        let listeners = NativeScanner.allListeners()
        let elapsed = Date().timeIntervalSince(start)

        print("NATIVE-BENCH: \(samples?.count ?? 0) processes + \(listeners?.count ?? 0) listeners in \(Int(elapsed * 1000))ms")
        XCTAssertLessThan(elapsed, 1.0)
    }
}
