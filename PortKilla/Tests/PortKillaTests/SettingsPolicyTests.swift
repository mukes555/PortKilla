import XCTest
@testable import PortKillaCore
@testable import PortKilla

/// The 2.0 settings: the policy the CLI shares with the app, per-event
/// notifications, what the list shows, and beta-aware updates.
final class SettingsPolicyTests: XCTestCase {

    override func tearDown() {
        Policy.refusesUnclaimedServers = true
        Policy.defaultLeaseTTL = Reservation.defaultTTL
    }

    // MARK: - Policy shared with the CLI

    func testPolicyLoadsFromTheSharedDomainAndIgnoresNonsense() {
        let suite = "PortKillaTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults.discardSuite(named: suite, defaults: defaults) }
        defaults.set(false, forKey: DefaultsKey.guardRefusesUnclaimed)
        defaults.set(30.0 * 60, forKey: DefaultsKey.leaseDefaultTTL)
        Policy.load(from: defaults)
        XCTAssertFalse(Policy.refusesUnclaimedServers)
        XCTAssertEqual(Policy.defaultLeaseTTL, 30 * 60)

        defaults.set(5.0, forKey: DefaultsKey.leaseDefaultTTL)
        Policy.load(from: defaults)
        XCTAssertEqual(Policy.defaultLeaseTTL, 30 * 60, "a lease shorter than a minute is not a lease")
        defaults.set(Double.infinity, forKey: DefaultsKey.leaseDefaultTTL)
        Policy.load(from: defaults)
        XCTAssertEqual(Policy.defaultLeaseTTL, 30 * 60)
    }

    func testTheGuardMayLetAgentsStopUnclaimedServersWhenAsked() {
        let agent = AgentOwner(name: "Claude Code", sessionPid: 10, source: .processTree)
        XCTAssertTrue(KillDecision.forAgent(caller: agent, target: nil).isRefusal, "on by default")
        XCTAssertEqual(KillDecision.forAgent(caller: agent, target: nil, refusesUnclaimed: false), .allow)
        Policy.refusesUnclaimedServers = false
        XCTAssertEqual(KillDecision.forAgent(caller: agent, target: nil), .allow, "the CLI reads the switch through the policy")
        let other = AgentOwner(name: "Cursor", sessionPid: 20, source: .processTree)
        XCTAssertTrue(KillDecision.forAgent(caller: agent, target: other).isRefusal, "another agent's running server is refused whatever the switch says")
    }

    func testReserveWithoutForUsesTheDefaultLeaseLength() {
        Policy.defaultLeaseTTL = 45 * 60
        guard case .success(.reserve(let options)) = CLIArguments.parse(["reserve", "3000"]) else { return XCTFail("reserve parses") }
        XCTAssertEqual(options.ttl, 45 * 60)
        guard case .success(.reserve(let explicit)) = CLIArguments.parse(["reserve", "3000", "--for", "5m"]) else { return XCTFail("reserve parses") }
        XCTAssertEqual(explicit.ttl, 5 * 60, "--for still wins")
    }

    func testTheAppWritesThePolicyTheCLIReads() {
        let manager = PortManager.forTesting()
        defer { manager.discardTestDefaults() }
        manager.guardRefusesUnclaimed = false
        manager.leaseDefaultTTL = 60 * 60
        XCTAssertFalse(Policy.refusesUnclaimedServers)
        XCTAssertEqual(Policy.defaultLeaseTTL, 60 * 60)
        Policy.refusesUnclaimedServers = true
        Policy.defaultLeaseTTL = Reservation.defaultTTL
        Policy.load(from: manager.defaults)
        XCTAssertFalse(Policy.refusesUnclaimedServers, "what the app stored is what a CLI process loads")
        XCTAssertEqual(Policy.defaultLeaseTTL, 60 * 60)

        manager.resetAllSettings()
        XCTAssertTrue(manager.guardRefusesUnclaimed)
        XCTAssertEqual(manager.leaseDefaultTTL, Reservation.defaultTTL)
        XCTAssertTrue(Policy.refusesUnclaimedServers)
    }

    // MARK: - Notifications and the list

    func testEachNotificationKindHasItsOwnSwitchUnderTheMaster() {
        let manager = PortManager.forTesting()
        defer { manager.discardTestDefaults() }
        XCTAssertTrue(manager.notifies(.portFreed))
        manager.notifyPortFreed = false
        manager.notifyRefusals = false
        XCTAssertFalse(manager.notifies(.portFreed))
        XCTAssertFalse(manager.notifies(.refusal))
        XCTAssertTrue(manager.notifies(.portTaken))
        XCTAssertTrue(manager.notifies(.guardKill))
        manager.notificationsEnabled = false
        XCTAssertFalse(manager.notifies(.portTaken), "the master switch wins")

        let restored = PortManager(defaults: manager.defaults, history: HistoryManager(defaults: manager.defaults), autoStart: false)
        XCTAssertFalse(restored.notifyPortFreed)
        XCTAssertFalse(restored.notifyRefusals)
        XCTAssertTrue(restored.notifyPortTaken)
    }

    func testTheListCanDropUDPAndEphemeralPorts() {
        let manager = PortManager.forTesting()
        defer { manager.discardTestDefaults() }
        func port(_ number: Int, proto: String = "tcp", user: String = NSUserName()) -> PortInfo {
            PortInfo(port: number, pid: number, processName: "node", command: "/Users/me/node", user: user, memoryUsage: "1MB",
                     memorySizeKB: 1, type: .nodejs, proto: proto)
        }
        manager.activePorts = [port(3000), port(5353, proto: "udp"), port(52000), port(80, user: "root")]
        manager.recomputeVisiblePorts()
        XCTAssertEqual(manager.visiblePorts.map(\.port), [3000, 5353, 52000], "system processes hidden, the rest shown")
        XCTAssertEqual(manager.hiddenSystemPortsCount, 1)

        manager.showUDP = false
        XCTAssertEqual(manager.visiblePorts.map(\.port), [3000, 52000])
        manager.hideEphemeralPorts = true
        XCTAssertEqual(manager.visiblePorts.map(\.port), [3000])
        XCTAssertEqual(manager.hiddenSystemPortsCount, 1, "the footer's hint counts system processes only")
        manager.hideSystemProcesses = false
        XCTAssertEqual(manager.visiblePorts.map(\.port), [3000, 80], "showing system processes does not undo the other filters")
    }

    // MARK: - Updates

    func testBetaReleasesAreOfferedOnlyWhenAskedAndRankBelowTheRelease() throws {
        XCTAssertFalse(UpdateChecker.isVersion("2.0.0-beta.1", newerThan: "1.16.0"), "not without opting in")
        XCTAssertTrue(UpdateChecker.isVersion("2.0.0-beta.1", newerThan: "1.16.0", includePrereleases: true))
        XCTAssertTrue(UpdateChecker.isVersion("2.0.0", newerThan: "2.0.0-beta.3"))
        XCTAssertFalse(UpdateChecker.isVersion("2.0.0-beta.3", newerThan: "2.0.0", includePrereleases: true))
        XCTAssertTrue(UpdateChecker.isVersion("2.0.0-beta.2", newerThan: "2.0.0-beta.1", includePrereleases: true))
        XCTAssertTrue(UpdateChecker.isVersion("2.0.0-rc.1", newerThan: "2.0.0-beta.9", includePrereleases: true))
        XCTAssertFalse(UpdateChecker.isVersion("2.0.0-beta.1", newerThan: "2.0.0-beta.1", includePrereleases: true))

        let list = """
        [{"tag_name": "v2.1.0-beta.1", "prerelease": true},
         {"tag_name": "v2.0.0", "prerelease": false},
         {"tag_name": "v3.0.0", "draft": true},
         {"tag_name": "v1.16.0"}]
        """.data(using: .utf8)!
        let ok = HTTPURLResponse(url: URL(string: "https://x")!, statusCode: 200, httpVersion: nil, headerFields: nil)
        XCTAssertEqual(UpdateChecker.evaluate(data: list, response: ok, error: nil, current: "1.16.0"), .newer("2.0.0"), "the draft and the beta are skipped")
        XCTAssertEqual(UpdateChecker.evaluate(data: list, response: ok, error: nil, current: "1.16.0", includePrereleases: true), .newer("2.1.0-beta.1"))
        XCTAssertEqual(UpdateChecker.evaluate(data: list, response: ok, error: nil, current: "2.1.0-beta.1", includePrereleases: true), .upToDate)
        let single = #"{"tag_name": "v2.0.0"}"#.data(using: .utf8)!
        XCTAssertEqual(UpdateChecker.evaluate(data: single, response: ok, error: nil, current: "2.0.0"), .upToDate)
    }

    // MARK: - Setup from the app

    func testSetupStepsApplyAndReportInOneLine() throws {
        let project = FileManager.default.temporaryDirectory.appendingPathComponent("portkilla-setup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }
        let write = CLISetup.Step(title: "Add the PortKilla section to CLAUDE.md", detail: "", kind: .writeRules(.claude))
        let outcome = CLISetup.apply(write, project: project)
        XCTAssertTrue(outcome.ok, outcome.message)
        XCTAssertTrue(outcome.message.hasPrefix("Added"), outcome.message)
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.appendingPathComponent("CLAUDE.md").path))
        XCTAssertTrue(CLISetup.apply(write, project: project).message.contains("already current"), "a second apply changes nothing")

        let note = CLISetup.Step(title: "Shell completions", detail: "portkilla completions zsh", kind: .note)
        XCTAssertTrue(CLISetup.apply(note, project: project).ok)
        let missing = CLISetup.Step(title: "Register", detail: "", kind: .runCommand(["no-such-tool-xyz", "--flag"]))
        let failed = CLISetup.apply(missing, project: project)
        XCTAssertFalse(failed.ok)
        XCTAssertTrue(failed.message.contains("not on PATH"), failed.message)
    }

    func testLeaseLengthsAlwaysIncludeTheCurrentChoice() {
        XCTAssertEqual(AgentsSettings.leaseLengths(including: 600).count, 5)
        let custom = AgentsSettings.leaseLengths(including: 15 * 60)
        XCTAssertEqual(custom.count, 6)
        XCTAssertEqual(custom.map(\.seconds), custom.map(\.seconds).sorted())
        XCTAssertTrue(AgentsSettings.isCommand("portkilla completions zsh > ~/.zfunc/_portkilla"))
        XCTAssertFalse(AgentsSettings.isCommand("/Users/me/project"))
    }
}
