import Foundation
import CLibProc

/// Raw-syscall process and socket enumeration via libproc — what lsof and ps
/// do internally, without spawning a single subprocess. A full scan takes
/// microseconds instead of ~100ms of fork/exec/parse.
enum NativeScanner {

    /// Reads a NUL-terminated string from a fixed-size C char tuple, bounding
    /// the scan to the array so a (hypothetically) non-terminated kernel field
    /// can't be read past its end.
    static func stringFromFixedCArray<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let end = bytes.firstIndex(of: 0) ?? bytes.count
            return String(decoding: bytes[..<end], as: UTF8.self)
        }
    }

    struct Listener {
        let pid: Int
        let port: Int
        let host: String
        let proto: String // "tcp" | "udp"
    }

    struct ProcessSample {
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

    static func listPids() -> [Int32] {
        let capacity = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard capacity > 0 else { return [] }

        var pids = [Int32](repeating: 0, count: Int(capacity) / MemoryLayout<Int32>.stride + 16)
        let filled = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<Int32>.stride))
        guard filled > 0 else { return [] }

        return Array(pids.prefix(Int(filled) / MemoryLayout<Int32>.stride)).filter { $0 > 0 }
    }

    /// Full snapshot of all processes, or nil when the kernel interfaces are
    /// unavailable (callers fall back to ps).
    static func captureSamples() -> [ProcessSample]? {
        let pids = listPids()
        guard pids.count > 5 else { return nil }

        let now = Date().timeIntervalSince1970
        var samples: [ProcessSample] = []
        samples.reserveCapacity(pids.count)

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
                // counter is higher than the new one's) — a wrapping subtraction
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

            // pbi_name truncates at 15 chars; the executable path's basename
            // is the full name ("Google Chrome Helper"), so prefer it.
            let shortName = Self.stringFromFixedCArray(bsd.pbi_name)
            let path = executablePath(pid)
            let command = commandLine(pid) ?? path ?? shortName
            let fullName = path.map { ($0 as NSString).lastPathComponent } ?? shortName

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
        }

        cpuSampleLock.lock()
        previousCPUSample = newCPUSamples
        cpuSampleLock.unlock()
        return samples
    }

    static func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }

    static func taskInfo(_ pid: Int32) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        return info
    }

    static func executablePath(_ pid: Int32) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE (4 * MAXPATHLEN) is a computed macro Swift can't import
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Executable base name for a live PID (used for kill identity checks).
    static func processName(_ pid: Int32) -> String? {
        if let path = executablePath(pid) {
            return (path as NSString).lastPathComponent
        }
        guard let bsd = bsdInfo(pid) else { return nil }
        let name = Self.stringFromFixedCArray(bsd.pbi_name)
        return name.isEmpty ? nil : name
    }

    /// Full command line via KERN_PROCARGS2 (only readable for own processes;
    /// callers fall back to the executable path).
    static func commandLine(_ pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc > 0 else { return nil }

        // Layout: argc | exec_path\0 | padding \0s | argv[0]\0 argv[1]\0 …
        var index = MemoryLayout<Int32>.size
        // Skip exec_path
        while index < size && buffer[index] != 0 { index += 1 }
        // Skip padding
        while index < size && buffer[index] == 0 { index += 1 }

        var arguments: [String] = []
        var current: [UInt8] = []
        while index < size && arguments.count < Int(argc) {
            if buffer[index] == 0 {
                arguments.append(String(decoding: current, as: UTF8.self))
                current = []
            } else {
                current.append(buffer[index])
            }
            index += 1
        }

        let command = arguments.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return command.isEmpty ? nil : command
    }

    /// Working directory via PROC_PIDVNODEPATHINFO (own processes only).
    static func workingDirectory(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = Self.stringFromFixedCArray(info.pvi_cdir.vip_path)
        return path.isEmpty ? nil : path
    }

    static func childPids(of pid: Int32) -> [Int32] {
        listPids().filter { bsdInfo($0)?.pbi_ppid == UInt32(pid) }
    }

    private static var usernameCache: [uid_t: String] = [:]

    static func username(_ uid: uid_t) -> String {
        usernameLock.lock()
        defer { usernameLock.unlock() }
        if let cached = usernameCache[uid] { return cached }
        let name = getpwuid(uid).map { String(cString: $0.pointee.pw_name) } ?? "\(uid)"
        usernameCache[uid] = name
        return name
    }

    // MARK: - Sockets

    /// Every listening TCP socket and bound UDP socket on the system,
    /// or nil when fd enumeration is unavailable.
    static func allListeners() -> [Listener]? {
        let pids = listPids()
        guard pids.count > 5 else { return nil }

        var listeners: [Listener] = []
        for pid in pids {
            listeners.append(contentsOf: socketListeners(pid))
        }
        return listeners
    }

    static func socketListeners(_ pid: Int32) -> [Listener] {
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        let count = Int(bufferSize) / MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: count + 16)
        let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * MemoryLayout<proc_fdinfo>.stride))
        guard filled > 0 else { return [] }

        var listeners: [Listener] = []
        for fd in fds.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.stride)
        where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
            var socketInfo = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &socketInfo, size) == size else { continue }

            switch Int(socketInfo.psi.soi_kind) {
            case SOCKINFO_TCP:
                let tcp = socketInfo.psi.soi_proto.pri_tcp
                guard Int(tcp.tcpsi_state) == TSI_S_LISTEN else { continue }
                let endpoint = localEndpoint(tcp.tcpsi_ini)
                guard endpoint.port > 0 else { continue }
                listeners.append(Listener(pid: Int(pid), port: endpoint.port, host: endpoint.host, proto: "tcp"))

            case SOCKINFO_IN:
                guard Int32(socketInfo.psi.soi_protocol) == IPPROTO_UDP else { continue }
                let ini = socketInfo.psi.soi_proto.pri_in
                let endpoint = localEndpoint(ini)
                // Bound, unconnected, non-ephemeral sockets only
                let isConnected = ini.insi_fport != 0
                guard endpoint.port > 0, endpoint.port < 49152, !isConnected else { continue }
                listeners.append(Listener(pid: Int(pid), port: endpoint.port, host: endpoint.host, proto: "udp"))

            default:
                continue
            }
        }
        return listeners
    }

    private static func localEndpoint(_ info: in_sockinfo) -> (host: String, port: Int) {
        let port = Int(UInt16(truncatingIfNeeded: info.insi_lport).bigEndian)

        let isIPv6 = (Int32(info.insi_vflag) & Int32(INI_IPV6)) != 0
        if isIPv6 {
            var address = info.insi_laddr.ina_6
            if isZero(address) {
                return ("*", port)
            }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count))
            return (String(cString: buffer), port)
        }

        var address = info.insi_laddr.ina_46.i46a_addr4
        if address.s_addr == 0 {
            return ("*", port)
        }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count))
        return (String(cString: buffer), port)
    }

    private static func isZero(_ address: in6_addr) -> Bool {
        withUnsafeBytes(of: address) { raw in
            raw.allSatisfy { $0 == 0 }
        }
    }
}
