import XCTest
@testable import PortNannyCore
@testable import PortNanny

final class DistributionTests: XCTestCase {

    func testPrereleaseTagsAreNeverOfferedAsUpdates() {
        XCTAssertFalse(UpdateChecker.isVersion("2.0.0-rc1", newerThan: "1.14.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.15.0-beta", newerThan: "1.14.0"))
        XCTAssertTrue(UpdateChecker.isVersion("1.15.0", newerThan: "1.14.0"))
        XCTAssertTrue(UpdateChecker.isVersion("2.0", newerThan: "1.99.99"))
    }

    func testRateLimitIsExplained() {
        let limited = HTTPURLResponse(url: URL(string: "https://x")!, statusCode: 403, httpVersion: nil, headerFields: nil)
        guard case .failed(let reason) = UpdateChecker.evaluate(data: nil, response: limited, error: nil, current: "1.0.0") else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(reason.contains("rate limit"))
    }

    func testPerCommandHelpParses() {
        XCTAssertEqual(CLIArguments.parse(["kill", "--help"]), .success(.help(topic: "kill")))
        XCTAssertEqual(CLIArguments.parse(["list", "-h"]), .success(.help(topic: "list")))
        XCTAssertEqual(CLIArguments.parse(["help", "wait"]), .success(.help(topic: "wait")))
        XCTAssertEqual(CLIArguments.parse(["-v"]), .success(.version(json: false)))
        XCTAssertEqual(CLIArguments.parse(["version", "--json"]), .success(.version(json: true)))
        XCTAssertEqual(CLIArguments.parse(["doctor"]), .success(.doctor(json: false, agents: false)))
        XCTAssertEqual(CLIArguments.parse(["completions", "zsh"]), .success(.completions(shell: "zsh")))
        XCTAssertEqual(CLIArguments.parse(["completions", "ksh"]), .failure(.unknownOption("ksh", command: "completions")))
        for topic in ["list", "kill", "free", "wait", "history", "whoami", "doctor"] {
            XCTAssertTrue(CLIArguments.usage(for: topic).contains("portnanny \(topic)"), topic)
        }
        XCTAssertEqual(CLIArguments.usage(for: "nonsense"), CLIArguments.usage)
    }

    func testCompletionsCoverEveryCommand() {
        for shell in ["zsh", "bash", "fish"] {
            let script = CLICompletions.script(for: shell) ?? ""
            for command in CLICompletions.commands {
                XCTAssertTrue(script.contains(command), "\(shell) completions miss \(command)")
            }
        }
        // Every parseable command is completable, and vice versa.
        for command in CLICompletions.commands where !["help", "completions", "version", "doctor", "agent-docs", "whoami"].contains(command) {
            XCTAssertNotNil(CLIArguments.parse([command, "1"]) ?? nil, command)
        }
    }

    func testDiagnosticsReportHasTheBugReportFacts() {
        let labels = Diagnostics.report().map(\.label)
        for expected in ["PortNanny", "macOS", "Architecture", "Install source", "Scanner", "portnanny on PATH", "Launch at login"] {
            XCTAssertTrue(labels.contains(expected), expected)
        }
        XCTAssertEqual(InstallSource.detect(bundleURL: URL(fileURLWithPath: "/Users/me/dev/.build/debug")), .development)
    }
}
