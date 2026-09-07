import Foundation

/// The port a project says it uses, read from the places developers put
/// it: `.env` files, package.json scripts, vite.config. A server that ended
/// up elsewhere (because the port was taken) can then be told from one
/// that meant to be there.
public struct ExpectedPort: Codable, Equatable {
    public let port: Int
    /// Where it was read: ".env PORT", "package.json dev", "vite.config.ts".
    public let source: String

    public init(port: Int, source: String) {
        self.port = port
        self.source = source
    }
}

public final class ProjectConfig {
    public static let shared = ProjectConfig()

    private struct Entry {
        let readAt: Date
        let stamps: [String: Date]
        let ports: [ExpectedPort]
    }

    private var cache: [String: Entry] = [:]
    private let lock = NSLock()
    private let fileManager = FileManager.default
    /// How long a project's answer is trusted before its files are stat'ed again.
    static let recheckInterval: TimeInterval = 10

    static let envFiles = [".env", ".env.local", ".env.development", ".env.development.local"]
    static let viteFiles = ["vite.config.ts", "vite.config.js", "vite.config.mjs", "vite.config.mts"]

    public init() {}

    /// Every port the project's files name, cached and re-read when a file
    /// changes. Cheap enough per scan: a few stats per project.
    public func expectedPorts(in projectPath: String, now: Date = Date()) -> [ExpectedPort] {
        lock.lock()
        let cached = cache[projectPath]
        lock.unlock()
        if let cached, now.timeIntervalSince(cached.readAt) < Self.recheckInterval {
            return cached.ports
        }
        let stamps = self.stamps(in: projectPath)
        if let cached, cached.stamps == stamps {
            lock.lock()
            cache[projectPath] = Entry(readAt: now, stamps: stamps, ports: cached.ports)
            lock.unlock()
            return cached.ports
        }
        let ports = read(projectPath)
        lock.lock()
        cache[projectPath] = Entry(readAt: now, stamps: stamps, ports: ports)
        lock.unlock()
        return ports
    }

    /// The expected port closest to where the server actually runs, when
    /// none of them is that port; nil when the project says nothing or the
    /// server is where it should be.
    public static func drift(from expected: [ExpectedPort], actual: Int) -> ExpectedPort? {
        guard !expected.isEmpty, !expected.contains(where: { $0.port == actual }) else { return nil }
        return expected.min { abs($0.port - actual) < abs($1.port - actual) }
    }

    private func stamps(in projectPath: String) -> [String: Date] {
        var stamps: [String: Date] = [:]
        for name in Self.envFiles + ["package.json"] + Self.viteFiles {
            let path = (projectPath as NSString).appendingPathComponent(name)
            if let date = (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date {
                stamps[name] = date
            }
        }
        return stamps
    }

    private func read(_ projectPath: String) -> [ExpectedPort] {
        var ports: [ExpectedPort] = []
        for name in Self.envFiles {
            if let text = contents(projectPath, name) { ports += Self.parseEnv(text, file: name) }
        }
        if let data = fileManager.contents(atPath: (projectPath as NSString).appendingPathComponent("package.json")) {
            ports += Self.parsePackageScripts(data)
        }
        for name in Self.viteFiles {
            if let text = contents(projectPath, name) { ports += Self.parseViteConfig(text, file: name) }
        }
        // First mention wins per port, so the order above is the precedence.
        var seen = Set<Int>()
        return ports.filter { seen.insert($0.port).inserted }
    }

    private func contents(_ projectPath: String, _ name: String) -> String? {
        let path = (projectPath as NSString).appendingPathComponent(name)
        guard let data = fileManager.contents(atPath: path), data.count < 256 * 1024 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// `PORT=3000` and any `*_PORT=...`; quotes stripped, comments ignored.
    static func parseEnv(_ text: String, file: String) -> [ExpectedPort] {
        var ports: [ExpectedPort] = []
        for rawLine in text.split(separator: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)) }
            guard !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            guard key == "PORT" || key.hasSuffix("_PORT") else { continue }
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if let hash = value.firstIndex(of: "#") { value = value[..<hash].trimmingCharacters(in: .whitespaces) }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if let port = Int(value), PortManager.isValidPortNumber(port) {
                ports.append(ExpectedPort(port: port, source: "\(file) \(key)"))
            }
        }
        // PORT itself outranks DB_PORT and friends.
        return ports.sorted { ($0.source.hasSuffix(" PORT") ? 0 : 1) < ($1.source.hasSuffix(" PORT") ? 0 : 1) }
    }

    private static let scriptPort = try! NSRegularExpression(pattern: #"(?:--port[= ]|-p |PORT=)(\d{2,5})\b"#)

    /// `"dev": "vite --port 5173"`, `"start": "PORT=4000 node ."`
    static func parsePackageScripts(_ data: Data) -> [ExpectedPort] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = object["scripts"] as? [String: String] else { return [] }
        var ports: [ExpectedPort] = []
        for name in scripts.keys.sorted() {
            let script = scripts[name]!
            let range = NSRange(script.startIndex..., in: script)
            for match in scriptPort.matches(in: script, range: range) {
                guard let digits = Range(match.range(at: 1), in: script), let port = Int(script[digits]), PortManager.isValidPortNumber(port) else { continue }
                ports.append(ExpectedPort(port: port, source: "package.json \(name)"))
            }
        }
        return ports
    }

    private static let vitePort = try! NSRegularExpression(pattern: #"\bport:\s*(\d{2,5})\b"#)

    static func parseViteConfig(_ text: String, file: String) -> [ExpectedPort] {
        let range = NSRange(text.startIndex..., in: text)
        return vitePort.matches(in: text, range: range).compactMap { match in
            guard let digits = Range(match.range(at: 1), in: text), let port = Int(text[digits]), PortManager.isValidPortNumber(port) else { return nil }
            return ExpectedPort(port: port, source: file)
        }
    }
}
