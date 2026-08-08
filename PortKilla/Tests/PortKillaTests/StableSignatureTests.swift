import XCTest
@testable import PortKilla

final class StableSignatureTests: XCTestCase {
    private func port(_ p: Int, cpu: Double, age: String?, mem: Int = 1024, name: String = "node") -> PortInfo {
        PortInfo(port: p, pid: 100, processName: name, command: "x", user: "u",
                 memoryUsage: "1MB", memorySizeKB: mem, type: .nodejs,
                 bindAddress: "127.0.0.1", proto: "tcp", cpuPercent: cpu, age: age)
    }

    func testSignatureIgnoresCpuAndAge() {
        // Only cpu/age differ → same signature → no republish/re-diff
        let a = [port(3000, cpu: 1.0, age: "2m")]
        let b = [port(3000, cpu: 87.5, age: "9m")]
        XCTAssertEqual(PortManager.stableSignature(a), PortManager.stableSignature(b))
    }

    func testSignatureReflectsStructuralChange() {
        let a = [port(3000, cpu: 1.0, age: "2m", mem: 1024)]
        let bMem = [port(3000, cpu: 1.0, age: "2m", mem: 999999)]
        let bName = [port(3000, cpu: 1.0, age: "2m", name: "python")]
        let bGone: [PortInfo] = []
        XCTAssertNotEqual(PortManager.stableSignature(a), PortManager.stableSignature(bMem))
        XCTAssertNotEqual(PortManager.stableSignature(a), PortManager.stableSignature(bName))
        XCTAssertNotEqual(PortManager.stableSignature(a), PortManager.stableSignature(bGone))
    }
}
