import XCTest
@testable import PortNannyCore
@testable import PortNanny

/// 2.1 renamed PortKilla to PortNanny. Everything written for the old name
/// (variables, links, preferences) must keep working unchanged.
final class RenameCompatibilityTests: XCTestCase {

    // MARK: - Environment variables

    func testTheOldVariablesStillDeclareOwnerAndSession() {
        let old = ["PORTKILLA_OWNER": "copilot", "PORTKILLA_SESSION": "abc-1"]
        XCTAssertEqual(AgentSignatures.declaredOwner(in: old), "copilot")
        XCTAssertEqual(AgentSignatures.declaredSession(in: old), "abc-1")
        XCTAssertEqual(AgentAttribution.declaredSession(in: old), "abc-1", "the attribution path reads the old name too")

        let both = old.merging(["PORTNANNY_OWNER": "aider", "PORTNANNY_SESSION": "xyz-2"]) { $1 }
        XCTAssertEqual(AgentSignatures.declaredOwner(in: both), "aider", "the new name wins when both are set")
        XCTAssertEqual(AgentSignatures.declaredSession(in: both), "xyz-2")

        XCTAssertTrue(AgentSignatures.markerKeys.contains("PORTKILLA_OWNER"), "the scanner keeps the old key from a process environment")
        XCTAssertTrue(AgentSignatures.markerKeys.contains("PORTKILLA_SESSION"))
    }

    // MARK: - URL scheme

    func testTheOldSchemeStillParses() {
        XCTAssertEqual(URLCommand.parse(URL(string: "portkilla://kill/3000?force=1")!), .kill(port: 3000, force: true))
        XCTAssertEqual(URLCommand.parse(URL(string: "portkilla://show")!), .show)
    }

    // MARK: - Preferences

    func testTheFirstRunCopiesTheOldDomainOnceAndNeverOverwrites() {
        let (legacy, dropLegacy) = makeSuite()
        let (target, dropTarget) = makeSuite()
        defer { dropLegacy(); dropTarget() }
        legacy.set("advanced", forKey: "PortKilla.viewDensity")
        legacy.set([3000, 5173], forKey: "PortKilla.watchedPorts")
        legacy.set(Data([1, 2, 3]), forKey: "portHistory")
        legacy.set("not ours", forKey: "SomeOtherApp.setting")
        target.set("clean", forKey: DefaultsKey.viewDensity)

        XCTAssertEqual(PreferencesMigration.run(into: target, from: legacy), 2, "watched ports and history; density was already set here")
        XCTAssertEqual(target.string(forKey: DefaultsKey.viewDensity), "clean", "never over a value the new app wrote")
        XCTAssertEqual(target.array(forKey: DefaultsKey.watchedPorts) as? [Int], [3000, 5173])
        XCTAssertEqual(target.data(forKey: DefaultsKey.history), Data([1, 2, 3]))
        XCTAssertNil(target.object(forKey: "SomeOtherApp.setting"), "only PortKilla's keys come along")
        XCTAssertTrue(target.bool(forKey: PreferencesMigration.marker))

        legacy.set(true, forKey: "PortKilla.hideSystemProcesses")
        XCTAssertEqual(PreferencesMigration.run(into: target, from: legacy), 0, "once: the old app may keep writing, the new one has moved on")
        XCTAssertNil(target.object(forKey: DefaultsKey.hideSystemProcesses))
    }

    func testAMissingOldDomainStillMarksTheMigrationDone() {
        let (target, dropTarget) = makeSuite()
        defer { dropTarget() }
        XCTAssertEqual(PreferencesMigration.run(into: target, from: nil), 0)
        XCTAssertTrue(target.bool(forKey: PreferencesMigration.marker), "a fresh install never looks again")
    }

    func testTheMigratedKeysKeepTheirNamesApartFromThePrefix() {
        XCTAssertEqual(PreferencesMigration.migratedKey("PortKilla.refusals"), DefaultsKey.refusals)
        XCTAssertEqual(PreferencesMigration.migratedKey("PortKilla.reservations"), DefaultsKey.reservations)
        XCTAssertEqual(PreferencesMigration.migratedKey("portHistory"), DefaultsKey.history)
        XCTAssertNil(PreferencesMigration.migratedKey("AppleLanguages"))
        XCTAssertNil(PreferencesMigration.migratedKey("PortNanny.viewDensity"), "already the new name; nothing to do")
    }

    private func makeSuite() -> (UserDefaults, () -> Void) {
        let name = "PortNannyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (defaults, { UserDefaults.discardSuite(named: name, defaults: defaults) })
    }
}
