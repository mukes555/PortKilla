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
        let ageSeconds: Int?
        let command: String
        /// Authoritative name from the kernel (native scans). The computed
        /// fallback mis-splits paths with spaces ("Google Chrome Helper" -> "Google").
        var processName: String?

        var name: String {
            if let processName, !processName.isEmpty {
                return processName
            }
            let executable = command.split(separator: " ").first.map(String.init) ?? command
            return executable.split(separator: "/").last.map(String.init) ?? executable
        }
    }

    static let empty = ProcessTable(psOutput: "")

    private let entriesByPid: [Int: Entry]
    private let childrenByPpid: [Int: [Entry]]

    static func capture() -> ProcessTable {
        // Raw-syscall snapshot; ps subprocess only as a fallback
        if let samples = NativeScanner.captureSamples() {
            return ProcessTable(entries: samples.map { sample in
                Entry(
                    pid: sample.pid, ppid: sample.ppid, rssKB: sample.rssKB,
                    cpuPercent: sample.cpuPercent, ageSeconds: sample.ageSeconds,
                    command: sample.command, processName: sample.name
                )
            })
        }

        let output = (try? CommandRunner.run(
            "/bin/ps", ["-axo", "pid=,ppid=,rss=,%cpu=,etime=,command="], timeout: 5.0
        )) ?? ""
        return ProcessTable(psOutput: output)
    }

    init(entries: [Entry]) {
        var byPid: [Int: Entry] = [:]
        var byPpid: [Int: [Entry]] = [:]
        for entry in entries {
            byPid[entry.pid] = entry
            byPpid[entry.ppid, default: []].append(entry)
        }
        entriesByPid = byPid
        childrenByPpid = byPpid
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
                ageSeconds: ElapsedFormat.seconds(fromEtime: String(parts[4])),
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
    func ppid(for pid: Int) -> Int? { entriesByPid[pid]?.ppid }
    func rssKB(for pid: Int) -> Int? { entriesByPid[pid]?.rssKB }
    func cpuPercent(for pid: Int) -> Double? { entriesByPid[pid]?.cpuPercent }
    func ageSeconds(for pid: Int) -> Int? { entriesByPid[pid]?.ageSeconds }
    func children(of pid: Int) -> [Entry] { childrenByPpid[pid] ?? [] }
}
