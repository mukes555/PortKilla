import Foundation

/// `portkilla mcp`: a Model Context Protocol server over stdin/stdout, so an
/// agent gets the guard as a tool instead of a habit. Newline-delimited
/// JSON-RPC 2.0, no dependencies. The agent spawns and reaps this process;
/// nothing is resident, registered, or wrapped, which keeps it inside the
/// project's passive charter. Only responses go to stdout; everything else
/// goes to stderr or the unified log.
final class MCPServer {
    static let protocolVersion = "2024-11-05"

    func serve() -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let reply = handle(line: line) {
                print(reply)
                fflush(stdout)
            }
        }
        return CLIExit.ok
    }

    /// One request in, one response out (nil for notifications). Exposed
    /// for tests, which drive the protocol without a process.
    func handle(line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "parse error"]])
        }
        let id = request["id"]
        let method = request["method"] as? String ?? ""
        let params = request["params"] as? [String: Any] ?? [:]

        if method.hasPrefix("notifications/") { return nil }
        guard let id else { return nil }

        switch method {
        case "initialize":
            return respond(id, [
                "protocolVersion": Self.protocolVersion,
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "portkilla", "version": UpdateChecker.currentVersion ?? "dev"],
            ])
        case "ping":
            return respond(id, [:])
        case "tools/list":
            return respond(id, ["tools": Self.tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            guard let result = call(tool: name, arguments: arguments) else {
                return fail(id, code: -32602, message: "unknown tool '\(name)'")
            }
            return respond(id, result)
        default:
            return fail(id, code: -32601, message: "method not found: \(method)")
        }
    }

    // MARK: - Tools

    static let tools: [[String: Any]] = [
        [
            "name": "list_ports",
            "description": "Listening TCP ports and bound UDP sockets with process, memory, bind address, and the AI agent that started each. filter: all | mine | unowned | orphaned; agent: name to filter by.",
            "inputSchema": ["type": "object", "properties": [
                "filter": ["type": "string", "enum": ["all", "mine", "unowned", "orphaned"]],
                "agent": ["type": "string"],
            ]],
        ],
        [
            "name": "kill_port",
            "description": "Stop every process listening on a port (SIGTERM, verified). dry_run is true by default: call again with dry_run=false to act. Refuses (isError) when another agent's running session owns the port; do not set force unless the user said so.",
            "inputSchema": ["type": "object", "properties": [
                "port": ["type": "integer"],
                "pid": ["type": "integer"],
                "dry_run": ["type": "boolean", "default": true],
                "force": ["type": "boolean", "default": false],
            ]],
        ],
        [
            "name": "whoami",
            "description": "How PortKilla identifies the calling agent for the friendly-fire guard.",
            "inputSchema": ["type": "object", "properties": [:]],
        ],
        [
            "name": "wait_for_port_free",
            "description": "Block until nothing listens on the port, up to timeout_seconds (max 30).",
            "inputSchema": ["type": "object", "properties": [
                "port": ["type": "integer"],
                "timeout_seconds": ["type": "number", "default": 10],
            ], "required": ["port"]],
        ],
    ]

    private func call(tool: String, arguments: [String: Any]) -> [String: Any]? {
        switch tool {
        case "list_ports":
            var options = CLICommand.ListOptions()
            switch arguments["filter"] as? String {
            case "mine": options.mine = true
            case "unowned": options.unowned = true
            case "orphaned": options.orphaned = true
            default: break
            }
            options.agent = arguments["agent"] as? String
            let scan = PortKillaCLI.scan(refreshDocker: true)
            let ports = PortKillaCLI.filtered(scan.ports, by: options, caller: scan.caller)
            let summary = ports.isEmpty ? "No listening ports match." : ports.map { ":\($0.port) \($0.processName) (pid \($0.pid))\($0.agentOwner.map { " owned by \($0.label)" } ?? "")" }.joined(separator: "\n")
            return toolResult(text: summary, structured: ports, isError: false)

        case "kill_port":
            var options = CLICommand.KillOptions()
            options.port = arguments["port"] as? Int
            options.pid = arguments["pid"] as? Int
            options.dryRun = arguments["dry_run"] as? Bool ?? true
            options.force = arguments["force"] as? Bool ?? false
            guard options.port != nil || options.pid != nil else {
                return toolResult(text: "kill_port needs a port or a pid", structured: nil as String?, isError: true)
            }
            let outcome = CLIKill.perform(options)
            let refused = outcome.report.exitCode == CLIExit.refused
            return toolResult(text: outcome.text, structured: outcome.report, isError: refused || outcome.report.exitCode == CLIExit.killFailed)

        case "whoami":
            let me = PortKillaCLI.callerIdentity()
            let text = me.map { "\($0.described), detected from \($0.source.rawValue)" } ?? "Not identified as an AI agent. Export PORTKILLA_OWNER=<name>."
            return toolResult(text: text, structured: PortKillaCLI.WhoAmI(detected: me != nil, owner: me), isError: false)

        case "wait_for_port_free":
            guard let port = arguments["port"] as? Int else {
                return toolResult(text: "wait_for_port_free needs a port", structured: nil as String?, isError: true)
            }
            // Capped: this blocks the whole server loop.
            let timeout = min(arguments["timeout_seconds"] as? Double ?? 10, 30)
            let report = PortKillaCLI.waitUntilFree(port: port, timeout: timeout)
            return toolResult(text: report.free ? ":\(port) is free." : ":\(port) is still in use after \(Int(timeout))s.", structured: report, isError: false)

        default:
            return nil
        }
    }

    // MARK: - Encoding

    private func toolResult<T: Encodable>(text: String, structured: T?, isError: Bool) -> [String: Any] {
        var result: [String: Any] = ["content": [["type": "text", "text": text]], "isError": isError]
        if let structured, let data = try? JSONEncoder().encode(structured),
           let object = try? JSONSerialization.jsonObject(with: data) {
            result["structuredContent"] = object
        }
        return result
    }

    private func respond(_ id: Any, _ result: [String: Any]) -> String {
        encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func fail(_ id: Any, code: Int, message: String) -> String {
        encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    private func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"could not encode response"}}"#
        }
        return text
    }
}
