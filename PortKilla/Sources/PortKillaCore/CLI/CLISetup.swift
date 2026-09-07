import Foundation

/// `portkilla setup`: the steps that make each AI tool on this Mac free
/// ports through PortKilla, offered one at a time. Every change is asked
/// about; nothing is written or run without a yes (or --yes).
public enum CLISetup {

    /// One thing the wizard can do, or just say.
    public struct Step: Equatable {
        public enum Kind: Equatable {
            /// Prints and moves on.
            case note
            /// Writes a rule file into the project.
            case writeRules(CLICommand.RuleTarget)
            /// Runs a command (the tool's own registration).
            case runCommand([String])
        }
        public let title: String
        public let detail: String
        public let kind: Kind
    }

    public static func run(_ options: CLICommand.SetupOptions) -> Int32 {
        let project = URL(fileURLWithPath: options.project ?? FileManager.default.currentDirectoryPath)
        let report = DoctorAgents.report()
        let steps = plan(agents: report, project: project)
        let interactive = isatty(0) != 0 && isatty(1) != 0

        print("PortKilla setup for \(project.path)\n")
        if !interactive && !options.yes {
            for step in steps { print(describe(step)) }
            print("\nNo terminal to ask on; run with --yes to apply the steps above.")
            return CLIExit.ok
        }
        var failures = 0
        for step in steps {
            switch step.kind {
            case .note:
                print(describe(step))
            case .writeRules, .runCommand:
                let wanted = options.yes || ask(step)
                guard wanted else {
                    print("  skipped")
                    continue
                }
                if apply(step, project: project) { print("  done") } else { failures += 1 }
            }
            print("")
        }
        print("Run `portkilla doctor --agents` any time to see how each tool is recognised.")
        return failures == 0 ? CLIExit.ok : CLIExit.killFailed
    }

    /// The steps for the tools present, plus the ones that always apply.
    public static func plan(agents report: DoctorAgents.Report, project: URL, pathHint: String? = nil,
                            shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh") -> [Step] {
        let onPath = pathHint ?? Diagnostics.report().first { $0.label == "portkilla on PATH" }?.value ?? "unknown"
        var steps: [Step] = [Step(title: "portkilla on PATH", detail: onPath, kind: .note)]
        let present = report.agents.filter { $0.running > 0 || $0.installedAt != nil }
        func has(_ name: String) -> Bool { present.contains { $0.name == name } }

        if has("Claude Code") {
            steps.append(Step(title: "Register the MCP server with Claude Code",
                              detail: "runs: claude mcp add --scope user portkilla -- portkilla mcp",
                              kind: .runCommand(["claude", "mcp", "add", "--scope", "user", "portkilla", "--", "portkilla", "mcp"])))
            steps.append(Step(title: "Add the PortKilla section to CLAUDE.md", detail: project.appendingPathComponent("CLAUDE.md").path, kind: .writeRules(.claude)))
            steps.append(Step(title: "The Claude Code plugin does all of that at once, plus the lsof hook",
                              detail: "claude plugin marketplace add mukes555/PortKilla && claude plugin install portkilla@portkilla", kind: .note))
        }
        if has("Codex CLI") {
            steps.append(Step(title: "Add the PortKilla section to AGENTS.md", detail: project.appendingPathComponent("AGENTS.md").path, kind: .writeRules(.codex)))
            steps.append(Step(title: "Register the MCP server with Codex", detail: MCPSetup.agents["codex"] ?? "", kind: .note))
        }
        if has("Cursor") {
            steps.append(Step(title: "Write Cursor's rule file", detail: project.appendingPathComponent(CLICommand.RuleTarget.cursor.path).path, kind: .writeRules(.cursor)))
            steps.append(Step(title: "Register the MCP server with Cursor", detail: MCPSetup.agents["cursor"] ?? "", kind: .note))
        }
        if has("Windsurf") {
            steps.append(Step(title: "Write Windsurf's rule file", detail: project.appendingPathComponent(CLICommand.RuleTarget.windsurf.path).path, kind: .writeRules(.windsurf)))
        }
        if present.isEmpty {
            steps.append(Step(title: "No AI tool found on this Mac", detail: "install one, or write rules by hand: portkilla agent-docs --write", kind: .note))
        }
        let shellName = (shell as NSString).lastPathComponent
        let completions: String
        switch shellName {
        case "zsh": completions = "portkilla completions zsh > ~/.zfunc/_portkilla   (with ~/.zfunc in fpath)"
        case "bash": completions = "portkilla completions bash >> ~/.bash_completion"
        case "fish": completions = "portkilla completions fish > ~/.config/fish/completions/portkilla.fish"
        default: completions = "portkilla completions zsh|bash|fish"
        }
        steps.append(Step(title: "Shell completions (\(shellName))", detail: completions, kind: .note))
        return steps
    }

    static func describe(_ step: Step) -> String {
        let marker = step.kind == .note ? "  " : "* "
        return "\(marker)\(step.title)\n    \(step.detail.replacingOccurrences(of: "\n", with: "\n    "))"
    }

    private static func ask(_ step: Step) -> Bool {
        print(describe(step))
        print("  Apply? [y/N] ", terminator: "")
        guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        return answer == "y" || answer == "yes"
    }

    /// True on success; prints the failure itself.
    static func apply(_ step: Step, project: URL) -> Bool {
        switch step.kind {
        case .note:
            return true
        case .writeRules(let target):
            do {
                let result = try AgentDocsInstaller.install(into: project.appendingPathComponent(target.path))
                print("  \(result.rawValue) \(target.path)")
                return true
            } catch {
                PortKillaCLI.printError("  could not write \(target.path): \(error.localizedDescription)")
                return false
            }
        case .runCommand(let command):
            guard let tool = ToolLocator.resolve(command[0]) else {
                PortKillaCLI.printError("  \(command[0]) is not on PATH; run by hand: \(command.joined(separator: " "))")
                return false
            }
            do {
                let output = try CommandRunner.run(tool, Array(command.dropFirst()), timeout: 30)
                if !output.isEmpty { print("  " + output.trimmingCharacters(in: .newlines).replacingOccurrences(of: "\n", with: "\n  ")) }
                return true
            } catch {
                PortKillaCLI.printError("  \(command.joined(separator: " ")) failed: \(error.localizedDescription)")
                return false
            }
        }
    }
}
