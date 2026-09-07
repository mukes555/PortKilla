import XCTest
@testable import PortKillaCore

/// Phase E1: rule files for each tool, the setup wizard's plan, and the
/// Claude Code plugin shipped in the repository.
final class SetupTests: XCTestCase {

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func table(_ rows: [(Int, Int, String)]) -> ProcessTable {
        let lines = rows.map { "\($0.0) \($0.1) 1024 0.0 05:00 \($0.2)" }.joined(separator: "\n")
        return ProcessTable(psOutput: lines)
    }

    func testRuleFilesGetTheirFoldersAndFrontmatter() throws {
        let project = FileManager.default.temporaryDirectory.appendingPathComponent("portkilla-setup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }

        for target in CLICommand.RuleTarget.allCases {
            let file = project.appendingPathComponent(target.path)
            XCTAssertEqual(try AgentDocsInstaller.install(into: file), .added, target.rawValue)
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertTrue(text.contains(AgentDocsInstaller.beginMarker) && text.contains(AgentDocsInstaller.endMarker), target.rawValue)
            XCTAssertTrue(text.contains("portkilla free <port>"), target.rawValue)
            XCTAssertEqual(try AgentDocsInstaller.install(into: file), .unchanged, "running twice changes nothing")
        }
        let cursor = try String(contentsOf: project.appendingPathComponent(".cursor/rules/portkilla.mdc"), encoding: .utf8)
        XCTAssertTrue(cursor.hasPrefix("---\ndescription: "), "Cursor rules start with frontmatter")
        XCTAssertTrue(cursor.contains("alwaysApply: true"))
        let windsurf = try String(contentsOf: project.appendingPathComponent(".windsurf/rules/portkilla.md"), encoding: .utf8)
        XCTAssertTrue(windsurf.hasPrefix("---\ntrigger: always_on\n---"))
        let claude = try String(contentsOf: project.appendingPathComponent("CLAUDE.md"), encoding: .utf8)
        XCTAssertTrue(claude.hasPrefix(AgentDocsInstaller.beginMarker), "plain markdown files get no frontmatter")

        // An existing file keeps what it had; the block goes after it.
        let agents = project.appendingPathComponent("AGENTS.md")
        try "# My rules\n".write(to: agents, atomically: true, encoding: .utf8)
        XCTAssertEqual(try AgentDocsInstaller.install(into: agents), .added)
        XCTAssertTrue(try String(contentsOf: agents, encoding: .utf8).hasPrefix("# My rules\n\n<!-- portkilla:begin -->"))
    }

    func testAgentDocsAndSetupParse() {
        var cursor = CLICommand.AgentDocsOptions()
        cursor.write = true
        cursor.file = ".cursor/rules/portkilla.mdc"
        XCTAssertEqual(CLIArguments.parse(["agent-docs", "--cursor"]), .success(.agentDocs(cursor)))
        var codex = CLICommand.AgentDocsOptions()
        codex.write = true
        codex.file = "AGENTS.md"
        XCTAssertEqual(CLIArguments.parse(["agent-docs", "--codex"]), .success(.agentDocs(codex)))
        XCTAssertEqual(CLIArguments.parse(["agent-docs", "--zed"]), .failure(.unknownOption("--zed", command: "agent-docs")))
        var setup = CLICommand.SetupOptions()
        setup.yes = true
        setup.project = "/p"
        XCTAssertEqual(CLIArguments.parse(["setup", "-y", "--project=/p"]), .success(.setup(setup)))
        XCTAssertEqual(CLIArguments.parse(["setup", "--now"]), .failure(.unknownOption("--now", command: "setup")))
    }

    func testThePlanFollowsTheToolsPresent() throws {
        let both = DoctorAgents.report(table: table([(100, 1, "claude"), (200, 1, "/opt/homebrew/bin/codex")]), path: "")
        let steps = CLISetup.plan(agents: both, project: URL(fileURLWithPath: "/p"), pathHint: "ok", shell: "/bin/zsh")
        XCTAssertEqual(steps.first?.title, "portkilla on PATH")
        XCTAssertEqual(steps.first?.detail, "ok")
        XCTAssertTrue(steps.contains { $0.kind == .runCommand(["claude", "mcp", "add", "--scope", "user", "portkilla", "--", "portkilla", "mcp"]) })
        XCTAssertTrue(steps.contains { $0.kind == .writeRules(.claude) })
        XCTAssertTrue(steps.contains { $0.kind == .writeRules(.codex) })
        XCTAssertFalse(steps.contains { $0.kind == .writeRules(.cursor) }, "Cursor is not on this machine")
        XCTAssertTrue(steps.last?.title.contains("zsh") == true)
        XCTAssertTrue(steps.contains { $0.detail.contains("claude plugin marketplace add mukes555/PortKilla") })

        let none = DoctorAgents.report(table: table([(300, 1, "/bin/zsh")]), path: "")
        let bare = CLISetup.plan(agents: none, project: URL(fileURLWithPath: "/p"), pathHint: "ok", shell: "/usr/local/bin/fish")
        XCTAssertTrue(bare.contains { $0.title == "No AI tool found on this Mac" })
        XCTAssertTrue(bare.last?.detail.contains("fish") == true)
        XCTAssertFalse(bare.contains { if case .runCommand = $0.kind { return true } else { return false } })
    }

    func testThePluginShipsItsPieces() throws {
        let plugin = repoRoot.appendingPathComponent("plugins/portkilla")
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: plugin.appendingPathComponent(".claude-plugin/plugin.json"))) as? [String: Any])
        XCTAssertEqual(manifest["name"] as? String, "portkilla")
        let mcp = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: plugin.appendingPathComponent(".mcp.json"))) as? [String: Any])
        let server = try XCTUnwrap((mcp["mcpServers"] as? [String: Any])?["portkilla"] as? [String: Any])
        XCTAssertEqual(server["args"] as? [String], ["mcp"])
        let hooks = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: plugin.appendingPathComponent("hooks/hooks.json"))) as? [String: Any])
        XCTAssertNotNil((hooks["hooks"] as? [String: Any])?["PreToolUse"], "the lsof hook")
        let skill = try String(contentsOf: plugin.appendingPathComponent("skills/portkilla/SKILL.md"), encoding: .utf8)
        for needle in ["name: portkilla", "portkilla free <port>", "exit code 3", "portkilla exec", "portkilla whois", "portkilla drift", "kill --orphaned"] {
            XCTAssertTrue(skill.lowercased().contains(needle.lowercased()), "SKILL.md should mention \(needle)")
        }
        for command in ["ports", "free"] {
            let text = try String(contentsOf: plugin.appendingPathComponent("commands/\(command).md"), encoding: .utf8)
            XCTAssertTrue(text.hasPrefix("---\ndescription: "), command)
            XCTAssertTrue(text.contains("portkilla"), command)
        }
        let marketplace = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: repoRoot.appendingPathComponent(".claude-plugin/marketplace.json"))) as? [String: Any])
        let entry = try XCTUnwrap((marketplace["plugins"] as? [[String: Any]])?.first)
        XCTAssertEqual(entry["source"] as? String, "./plugins/portkilla")
    }

    func testTheSkillMirrorsTheAgentDocsCommands() throws {
        // Every command the agent docs mention must be in the skill too, so
        // plugin users and CLAUDE.md users get the same advice.
        let skill = try String(contentsOf: repoRoot.appendingPathComponent("plugins/portkilla/skills/portkilla/SKILL.md"), encoding: .utf8)
        let commands = ["portkilla free", "portkilla kill", "portkilla exec", "portkilla reserve", "portkilla release", "portkilla free-port",
                        "portkilla whois", "portkilla drift", "portkilla wait", "portkilla list", "portkilla history"]
        for command in commands {
            XCTAssertTrue(PortKillaCLI.agentDocs.contains(command), "agent docs mention \(command)")
            XCTAssertTrue(skill.contains(command), "the skill mentions \(command)")
        }
    }
}
