import XCTest
@testable import PortNannyCore
@testable import PortNanny

final class PortTypeClassificationTests: XCTestCase {
    private let scanner = PortScanner()

    private func classify(_ processName: String, _ command: String) -> PortInfo.PortType {
        scanner.determinePortType(processName: processName, command: command)
    }

    func testChromeIsIdeToolNotGo() {
        // Regression: substring "go" used to classify "Google Chrome" as a Go server.
        let type = classify("Google Chrome", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        XCTAssertEqual(type, .ide)
    }

    func testAirPlayHelperIsNotGo() {
        // Regression: substring "air" used to classify AirPlay helpers as Go.
        let type = classify("AirPlayXPCHelper", "/usr/libexec/AirPlayXPCHelper")
        XCTAssertEqual(type, .other)
    }

    func testGoBinaryIsGo() {
        XCTAssertEqual(classify("go", "/usr/local/bin/go run ./cmd/server"), .go)
    }

    func testNodeIsNodejs() {
        XCTAssertEqual(classify("node", "/usr/local/bin/node server.js"), .nodejs)
        XCTAssertEqual(classify("node", "node_modules/.bin/vite dev"), .nodejs)
    }

    func testPostgresIsDatabase() {
        XCTAssertEqual(classify("postgres", "/opt/homebrew/bin/postgres -D /data"), .database)
    }

    func testPythonIsPython() {
        XCTAssertEqual(classify("Python", "/usr/bin/python3 -m http.server 8000"), .python)
    }

    func testVsCodeHelperIsIde() {
        XCTAssertEqual(classify("Code Helper (Plugin)", "/Applications/Visual Studio Code.app/..."), .ide)
    }

    func testUnknownDaemonIsOther() {
        XCTAssertEqual(classify("rapportd", "/usr/libexec/rapportd"), .other)
    }
}

final class WildcardHostTests: XCTestCase {
    func testWildcardHostDetection() {
        XCTAssertTrue(PortInfo.isWildcardHost("*"))
        XCTAssertTrue(PortInfo.isWildcardHost("0.0.0.0"))
        XCTAssertTrue(PortInfo.isWildcardHost("::"))
        XCTAssertFalse(PortInfo.isWildcardHost("127.0.0.1"))
        XCTAssertFalse(PortInfo.isWildcardHost("::1"))
        XCTAssertFalse(PortInfo.isWildcardHost("192.168.1.5"))
    }

    func testDockerProxyIsDocker() {
        // Regression: docker-proxy was misclassified as .database
        let scanner = PortScanner()
        XCTAssertEqual(scanner.determinePortType(processName: "docker-proxy", command: "/usr/bin/docker-proxy"), .docker)
    }
}
