import XCTest
@testable import PortKilla

/// Pure functions that previously had no coverage, and the invariants the
/// refactor introduced.
final class HousekeepingTests: XCTestCase {

    func testEveryKnownEditorIsClassifiedAsIDEAndProtectedByDefault() {
        let manager = PortManager.forTesting()
        defer { manager.discardTestDefaults() }
        manager.resetProtectedProcessSubstrings()
        let scanner = PortScanner()
        for editor in KnownEditors.substrings {
            let name = editor.capitalized + " Helper"
            XCTAssertEqual(scanner.determinePortType(processName: name, command: "/Applications/x"), .ide, editor)
            XCTAssertTrue(manager.isProtectedProcessName(name), "\(editor) should be protected by default")
        }
    }

    func testTypeRulesKeepTheirOrderAndScope() {
        let scanner = PortScanner()
        XCTAssertEqual(scanner.determinePortType(processName: "Code Helper", command: "/Applications/Visual Studio Code.app/x --type=go"), .ide)
        XCTAssertEqual(scanner.determinePortType(processName: "Google Chrome", command: "/Applications/Google Chrome.app/x"), .ide, "not a Go server")
        XCTAssertEqual(scanner.determinePortType(processName: "node", command: "/usr/local/bin/node server.js"), .nodejs)
        XCTAssertEqual(scanner.determinePortType(processName: "postgres", command: "/opt/homebrew/bin/postgres -D data"), .database)
        XCTAssertEqual(scanner.determinePortType(processName: "docker-proxy", command: "/usr/bin/docker-proxy -host-port 5432"), .docker)
        XCTAssertEqual(scanner.determinePortType(processName: "python3.12", command: "/usr/bin/python3.12 -m http.server"), .python)
        XCTAssertEqual(scanner.determinePortType(processName: "unknownd", command: "/opt/unknownd"), .other)
    }

    func testHistoryManagerCapsAndOrdersWithoutTouchingRealDefaults() throws {
        let suite = "PortKillaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults.discardSuite(named: suite, defaults: defaults) }

        let manager = HistoryManager(defaults: defaults)
        manager.maxHistoryItems = 3
        for port in 1...5 {
            manager.addEntry(port: port, processName: "p\(port)", action: .killed, owner: "Cursor", killedBy: "you")
        }
        XCTAssertEqual(manager.history.map(\.port), [5, 4, 3], "newest first, capped")

        let reloaded = HistoryManager(defaults: defaults)
        XCTAssertEqual(reloaded.history.map(\.port), [5, 4, 3])
        XCTAssertEqual(reloaded.history.first?.owner, "Cursor")

        manager.clearHistory()
        XCTAssertTrue(manager.history.isEmpty)
        XCTAssertNil(defaults.data(forKey: DefaultsKey.history))
    }

    func testHistoryCSVDocumentEscapesEveryColumn() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        let item = PortHistoryItem(port: 3000, processName: "=cmd|calc", action: .killed, owner: "Claude, Code", killedBy: "you")
        let csv = CSV.historyDocument([item], formatter: formatter)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines[0], "Timestamp,Port,Process,Action,Owner,Killed By")
        XCTAssertTrue(lines[1].contains("'=cmd|calc"), "formula lead-in defused")
        XCTAssertTrue(lines[1].contains("\"Claude, Code\""), "comma quoted")
        XCTAssertTrue(lines[1].hasSuffix(",you"))
    }

    func testNormalizeProtectedSubstrings() {
        let manager = PortManager.forTesting()
        defer { manager.discardTestDefaults() }
        manager.protectedProcessSubstrings = [" Xcode ", "xcode", "", "Slack\n"]
        XCTAssertEqual(manager.protectedProcessSubstrings, ["xcode", "slack"])
    }

    func testMemoryFormatBoundaries() {
        XCTAssertEqual(MemoryFormat.string(kilobytes: 512), "512KB")
        XCTAssertEqual(MemoryFormat.string(kilobytes: 1024), "1.0MB")
        XCTAssertEqual(MemoryFormat.string(kilobytes: 1024 * 1024), "1.00GB")
    }

    func testBestProcessNamePrefersTheUntruncatedTableName() {
        XCTAssertEqual(PortScanner.bestProcessName(lsofName: "Google Ch", entryName: "Google Chrome Helper"), "Google Chrome Helper")
        XCTAssertEqual(PortScanner.bestProcessName(lsofName: "node", entryName: "nodemon"), "nodemon")
        XCTAssertEqual(PortScanner.bestProcessName(lsofName: "python3", entryName: "Python"), "python3", "unrelated longer name is not trusted")
        XCTAssertEqual(PortScanner.bestProcessName(lsofName: "node", entryName: nil), "node")
    }
}
