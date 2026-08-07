import Foundation

/// A snapshot of every running process, taken with a single `ps` invocation.
///
/// The scanners previously spawned `ps`/`pgrep` once per listening port
/// (dozens of subprocesses per refresh); they now share one of these per
/// refresh and do dictionary lookups instead.
struct ProcessTable {

    struct Entry {
        let pid: Int
        let ppid: Int
        let rssKB: Int
        let cpuPercent: Double
        /// Raw ps etime, e.g. "05:12" or "2-03:44:01"
        let elapsed: String
        let command: String

        /// Executable base name, e.g. "/usr/local/bin/node server.js" -> "node"
        var name: String {
            let executable = command.split(separator: " ").first.map(String.init) ?? command
            return executable.split(separator: "/").last.map(String.init) ?? executable
        }
    }

    static let empty = ProcessTable(psOutput: "")

    private let entriesByPid: [Int: Entry]
    private let childrenByPpid: [Int: [Entry]]

    static func capture() -> ProcessTable {
        let output = (try? CommandRunner.run(
            "/bin/ps", ["-axo", "pid=,ppid=,rss=,%cpu=,etime=,command="], timeout: 5.0
        )) ?? ""
        return ProcessTable(psOutput: output)
    }

    init(psOutput: String) {
        var byPid: [Int: Entry] = [:]
        var byPpid: [Int: [Entry]] = [:]

        // Line format: PID PPID RSS %CPU ETIME COMMAND (command keeps its spaces)
        for line in psOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
            guard parts.count >= 6,
                  let pid = Int(parts[0]),
                  let ppid = Int(parts[1]),
                  let rss = Int(parts[2]) else { continue }

            let entry = Entry(
                pid: pid,
                ppid: ppid,
                rssKB: rss,
                cpuPercent: Double(parts[3]) ?? 0,
                elapsed: String(parts[4]),
                command: String(parts[5])
            )
            byPid[pid] = entry
            byPpid[ppid, default: []].append(entry)
        }

        entriesByPid = byPid
        childrenByPpid = byPpid
    }

    var allEntries: [Entry] { Array(entriesByPid.values) }

    func command(for pid: Int) -> String? { entriesByPid[pid]?.command }
    func name(for pid: Int) -> String? { entriesByPid[pid]?.name }
    func rssKB(for pid: Int) -> Int? { entriesByPid[pid]?.rssKB }
    func cpuPercent(for pid: Int) -> Double? { entriesByPid[pid]?.cpuPercent }
    func elapsed(for pid: Int) -> String? { entriesByPid[pid]?.elapsed }
    func children(of pid: Int) -> [Entry] { childrenByPpid[pid] ?? [] }
}
