import XCTest
import Foundation
@testable import PortKilla

final class NativeScannerTests: XCTestCase {

    private var ownPid: Int32 { Foundation.ProcessInfo.processInfo.processIdentifier }

    func testCaptureSamplesIncludesSelf() throws {
        let samples = try XCTUnwrap(NativeScanner.captureSamples())
        let me = try XCTUnwrap(samples.first { $0.pid == Int(ownPid) })

        XCTAssertGreaterThan(me.rssKB, 0)
        XCTAssertNotNil(me.ageSeconds)
        XCTAssertTrue(me.command.lowercased().contains("xctest"), "own command was: \(me.command)")
    }

    func testFindsOwnTCPListener() throws {
        // Open a real listening socket on a kernel-assigned port
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(socketFD, 0)
        defer { close(socketFD) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bindResult, 0)
        XCTAssertEqual(listen(socketFD, 1), 0)

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = getsockname(socketFD, $0, &length)
            }
        }
        let port = Int(UInt16(bigEndian: boundAddress.sin_port))
        XCTAssertGreaterThan(port, 0)

        let listeners = NativeScanner.socketListeners(ownPid)
        let match = listeners.first { $0.port == port && $0.proto == "tcp" }
        XCTAssertNotNil(match, "native scanner should see our listener on :\(port); saw \(listeners)")
        XCTAssertEqual(match?.host, "127.0.0.1")
    }

    func testWorkingDirectoryForSelf() {
        let cwd = NativeScanner.workingDirectory(ownPid)
        XCTAssertNotNil(cwd)
        XCTAssertTrue(cwd?.hasPrefix("/") ?? false)
    }

    func testProcessNameForSelf() {
        let name = NativeScanner.processName(ownPid)
        XCTAssertNotNil(name)
    }

    func testUsernameResolvesCurrentUser() {
        XCTAssertEqual(NativeScanner.username(getuid()), NSUserName())
    }
}
