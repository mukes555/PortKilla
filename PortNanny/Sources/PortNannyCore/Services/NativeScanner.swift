import Foundation
import CLibProc

/// Raw-syscall process and socket enumeration via libproc: what lsof and ps
/// do internally, without spawning a single subprocess. A full scan takes
/// microseconds instead of ~100ms of fork/exec/parse.
public enum NativeScanner {

    /// Reads a NUL-terminated string from a fixed-size C char tuple, bounding
    /// the scan to the array so a (hypothetically) non-terminated kernel field
    /// can't be read past its end.
    public static func stringFromFixedCArray<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let end = bytes.firstIndex(of: 0) ?? bytes.count
            return String(decoding: bytes[..<end], as: UTF8.self)
        }
    }

    public struct Listener {
        public let pid: Int
        public let port: Int
        public let host: String
        public let proto: String // "tcp" | "udp"
        /// Established TCP connections this process holds on the same local
        /// port: the clients currently talking to the server.
        public var connections: Int = 0
    }

    public struct ProcessSample {
        let pid: Int
        let ppid: Int
        let uid: uid_t
        let name: String
        let command: String
        let rssKB: Int
        let cpuPercent: Double
        let ageSeconds: Int?
    }

    // MARK: - Process table

    /// CPU%: computed from the delta between successive scans; first sighting
    /// falls back to the lifetime average.
    private static var previousCPUSample: [Int32: (time: TimeInterval, cpuNS: UInt64)] = [:]
    private static let cpuSampleLock = NSLock()
    private static let usernameLock = NSLock()

    public static func listPids() -> [Int32] {
        let capacity = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard capacity > 0 else { return [] }

        var pids = [Int32](repeating: 0, count: Int(capacity) / MemoryLayout<Int32>.stride + 16)
        let filled = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<Int32>.stride))
        guard filled > 0 else { return [] }

        return Array(pids.prefix(Int(filled) / MemoryLayout<Int32>.stride)).filter { $0 > 0 }
    }

    /// One pass over every process: table facts and listening sockets
    /// together. nil when the kernel interfaces are unavailable (callers fall
    /// back to ps and lsof).
    public struct Snapshot {
        let samples: [ProcessSample]
        let listeners: [Listener]
    }

    public static func captureSamples() -> [ProcessSample]? {
        capture()?.samples
    }

    public static func capture() -> Snapshot? {
        let pids = listPids()
        guard pids.count > 5 else { return nil }

        let now = Date().timeIntervalSince1970
        var samples: [ProcessSample] = []
        samples.reserveCapacity(pids.count)
        var listeners: [Listener] = []
        var fdBuffer = makeFdBuffer()

        // Snapshot the previous CPU baseline once; the hundreds of per-PID
        // syscalls below run WITHOUT the lock so a concurrent capture or
        // username() lookup never stalls behind them.
        cpuSampleLock.lock()
        let previousSamples = previousCPUSample
        cpuSampleLock.unlock()

        var newCPUSamples: [Int32: (time: TimeInterval, cpuNS: UInt64)] = [:]

        for pid in pids {
            guard let bsd = bsdInfo(pid) else { continue }

            var rssKB = 0
            var cpuPercent = 0.0
            var ageSeconds: Int?

            if let task = taskInfo(pid) {
                rssKB = Int(task.pti_resident_size / 1024)
                let cpuNS = task.pti_total_user &+ task.pti_total_system
                newCPUSamples[pid] = (now, cpuNS)

                // cpuNS < previous means the PID was recycled (the old process's
                // counter is higher than the new one's): a wrapping subtraction
                // would show billions of %. Fall back to the lifetime average.
                if let previous = previousSamples[pid], now > previous.time, cpuNS >= previous.cpuNS {
                    let deltaNS = Double(cpuNS - previous.cpuNS)
                    cpuPercent = deltaNS / ((now - previous.time) * 1_000_000_000) * 100
                } else {
                    let uptime = now - TimeInterval(bsd.pbi_start_tvsec)
                    if uptime > 1 {
                        cpuPercent = Double(cpuNS) / (uptime * 1_000_000_000) * 100
                    }
                }
                cpuPercent = max(0, min(cpuPercent, 100 * Double(Foundation.ProcessInfo.processInfo.activeProcessorCount)))
            }

            if bsd.pbi_start_tvsec > 0 {
                ageSeconds = max(0, Int(now) - Int(bsd.pbi_start_tvsec))
            }

            // Path and argv never change after exec, so they come from the
            // per-process cache. pbi_name truncates at 15 chars; the path's
            // basename is the full name ("Google Chrome Helper").
            let shortName = Self.stringFromFixedCArray(bsd.pbi_name)
            let facts = ProcessFacts.shared.facts(for: pid, startedAt: bsd.pbi_start_tvsec, shortName: shortName)
            let command = facts.command ?? facts.executablePath ?? shortName
            let fullName = facts.executablePath.map { ($0 as NSString).lastPathComponent } ?? shortName

            samples.append(ProcessSample(
                pid: Int(pid),
                ppid: Int(bsd.pbi_ppid),
                uid: bsd.pbi_uid,
                name: fullName.isEmpty ? ((command as NSString).lastPathComponent) : fullName,
                command: command,
                rssKB: rssKB,
                cpuPercent: (cpuPercent * 10).rounded() / 10,
                ageSeconds: ageSeconds
            ))
            listeners.append(contentsOf: socketListeners(pid, fdBuffer: &fdBuffer))
        }

        // Merge rather than replace: a link-initiated kill captures on its own
        // queue, and a wholesale replacement milliseconds apart would zero the
        // timer's deltas for a cycle.
        cpuSampleLock.lock()
        previousCPUSample.merge(newCPUSamples) { old, new in new.time - old.time < 0.5 ? old : new }
        previousCPUSample = previousCPUSample.filter { newCPUSamples[$0.key] != nil }
        cpuSampleLock.unlock()
        ProcessFacts.shared.prune(keeping: Set(pids))
        return Snapshot(samples: samples, listeners: listeners)
    }

    public static func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }

    public static func taskInfo(_ pid: Int32) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        return info
    }

    public static func executablePath(_ pid: Int32) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE (4 * MAXPATHLEN) is a computed macro Swift can't import
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Executable base name for a live PID (used for kill identity checks).
    public static func processName(_ pid: Int32) -> String? {
        if let path = executablePath(pid) {
            return (path as NSString).lastPathComponent
        }
        guard let bsd = bsdInfo(pid) else { return nil }
        let name = Self.stringFromFixedCArray(bsd.pbi_name)
        return name.isEmpty ? nil : name
    }

    /// Full command line via KERN_PROCARGS2 (only readable for own processes;
    /// callers fall back to the executable path). Parsing stops after argv;
    /// the environment that follows in the same buffer is never decoded here.
    public static func commandLine(_ pid: Int32) -> String? {
        guard let buffer = procArgsBuffer(pid), let layout = ProcArgsLayout(buffer) else { return nil }

        var index = layout.argvStart
        var arguments: [String] = []
        // Read by count so an empty argument (sh -c '') isn't taken as the end.
        while index < buffer.count && arguments.count < layout.argc {
            arguments.append(readCString(buffer, from: &index))
        }
        let command = arguments.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return command.isEmpty ? nil : command
    }

    /// Selected environment variables of `pid`, restricted to `keys`.
    ///
    /// A process environment routinely holds API keys and tokens, so the
    /// allowlist is enforced at the byte level: the buffer is scanned without
    /// decoding, only values of allowlisted keys become Strings, and the
    /// buffer is zeroed before it is released. Used to attribute a server to
    /// the agent that spawned it (the environment is inherited at spawn and
    /// survives reparenting, unlike the process tree).
    ///
    /// macOS withholds the environment of platform (OS-signed) binaries from
    /// unprivileged readers; only argv comes back for those. Dev servers are
    /// third-party binaries, so attribution is unaffected.
    public static func environmentMarkers(_ pid: Int32, keys: Set<String>) -> [String: String] {
        guard var buffer = procArgsBuffer(pid), let layout = ProcArgsLayout(buffer) else { return [:] }
        defer {
            _ = buffer.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
        }

        var index = layout.argvStart
        var skipped = 0
        while index < buffer.count && skipped < layout.argc {
            skipCString(buffer, from: &index)
            skipped += 1
        }

        let wanted = keys.map { (name: $0, bytes: Array($0.utf8)) }
        var markers: [String: String] = [:]
        while index < buffer.count {
            let start = index
            while index < buffer.count && buffer[index] != 0 { index += 1 }
            let entry = buffer[start..<index]
            index += 1
            if entry.isEmpty { break } // the env block ends at the first empty string

            guard let equals = entry.firstIndex(of: UInt8(ascii: "=")) else { continue }
            let key = entry[entry.startIndex..<equals]
            guard let match = wanted.first(where: { key.elementsEqual($0.bytes) }) else { continue }
            markers[match.name] = String(decoding: entry[(equals + 1)...], as: UTF8.self)
        }
        return markers
    }

    /// KERN_PROCARGS2 layout:
    /// argc | exec_path\0 | padding \0s | argv[0]\0 … argv[argc-1]\0 | env KEY=VALUE\0 … | \0
    private struct ProcArgsLayout {
        let argc: Int
        let argvStart: Int

        init?(_ buffer: [UInt8]) {
            guard buffer.count > MemoryLayout<Int32>.size else { return nil }
            let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
            guard argc > 0 else { return nil }

            var index = MemoryLayout<Int32>.size
            while index < buffer.count && buffer[index] != 0 { index += 1 } // exec_path
            while index < buffer.count && buffer[index] == 0 { index += 1 } // padding
            self.argc = Int(argc)
            self.argvStart = index
        }
    }

    private static func procArgsBuffer(_ pid: Int32) -> [UInt8]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        // The fill call reports how much it actually wrote.
        if size < buffer.count { buffer.removeSubrange(size...) }
        return buffer
    }

    /// Reads one NUL-terminated string starting at `index` and advances past the NUL.
    private static func readCString(_ buffer: [UInt8], from index: inout Int) -> String {
        let start = index
        skipCString(buffer, from: &index)
        let end = min(index - 1, buffer.count)
        return String(decoding: buffer[start..<max(start, end)], as: UTF8.self)
    }

    private static func skipCString(_ buffer: [UInt8], from index: inout Int) {
        while index < buffer.count && buffer[index] != 0 { index += 1 }
        index += 1
    }

    /// Working directory via PROC_PIDVNODEPATHINFO (own processes only).
    public static func workingDirectory(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = Self.stringFromFixedCArray(info.pvi_cdir.vip_path)
        return path.isEmpty ? nil : path
    }

    /// pid -> ppid for every process in one pass, so a tree walk never
    /// re-enumerates the table per node.
    public static func parentMap() -> [Int32: Int32] {
        processMap().mapValues(\.ppid)
    }

    /// pid -> (ppid, name) in one pass. A tree kill needs the name as it was
    /// when the tree was captured: reading it again at kill time compares a
    /// recycled pid with itself and can never fail.
    public static func processMap() -> [Int32: (ppid: Int32, name: String)] {
        var processes: [Int32: (ppid: Int32, name: String)] = [:]
        for pid in listPids() {
            if let bsd = bsdInfo(pid) {
                processes[pid] = (Int32(bsd.pbi_ppid), stringFromFixedCArray(bsd.pbi_name))
            }
        }
        return processes
    }

    private static var usernameCache: [uid_t: String] = [:]

    public static func username(_ uid: uid_t) -> String {
        usernameLock.lock()
        defer { usernameLock.unlock() }
        if let cached = usernameCache[uid] { return cached }
        let name = getpwuid(uid).map { String(cString: $0.pointee.pw_name) } ?? "\(uid)"
        usernameCache[uid] = name
        return name
    }
}
