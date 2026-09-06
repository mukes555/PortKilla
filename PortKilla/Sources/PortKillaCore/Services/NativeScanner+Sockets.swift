import Foundation
import CLibProc

// MARK: - Sockets
extension NativeScanner {

    /// Every listening TCP socket and bound UDP socket on the system,
    /// or nil when fd enumeration is unavailable. Prefer `capture()`, which
    /// gathers these in the same pass as the process table.
    public static func allListeners() -> [Listener]? {
        let pids = listPids()
        guard pids.count > 5 else { return nil }

        var listeners: [Listener] = []
        var fdBuffer = makeFdBuffer()
        for pid in pids {
            listeners.append(contentsOf: socketListeners(pid, fdBuffer: &fdBuffer))
        }
        return listeners
    }

    public static func socketListeners(_ pid: Int32) -> [Listener] {
        var fdBuffer = makeFdBuffer()
        return socketListeners(pid, fdBuffer: &fdBuffer)
    }

    /// Most processes hold well under 256 descriptors, so one reusable
    /// buffer of that size serves the whole pass; only a process that
    /// overflows it pays for a size probe and a larger fill.
    public static func makeFdBuffer() -> [proc_fdinfo] {
        [proc_fdinfo](repeating: proc_fdinfo(), count: 256)
    }

    public static func socketListeners(_ pid: Int32, fdBuffer: inout [proc_fdinfo]) -> [Listener] {
        let stride = MemoryLayout<proc_fdinfo>.stride
        var filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fdBuffer, Int32(fdBuffer.count * stride))
        guard filled > 0 else { return [] }

        if Int(filled) / stride >= fdBuffer.count {
            // Keep what the first fill returned if the re-probe fails (the
            // process may have exited between the calls).
            let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            if needed > 0 {
                var larger = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride + 16)
                let refilled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &larger, Int32(larger.count * stride))
                if refilled > 0 {
                    fdBuffer = larger
                    filled = refilled
                }
            }
        }

        var listeners: [Listener] = []
        var establishedByPort: [Int: Int] = [:]
        for fd in fdBuffer.prefix(Int(filled) / stride)
        where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
            var socketInfo = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &socketInfo, size) == size else { continue }

            switch Int(socketInfo.psi.soi_kind) {
            case SOCKINFO_TCP:
                let tcp = socketInfo.psi.soi_proto.pri_tcp
                let endpoint = localEndpoint(tcp.tcpsi_ini)
                guard endpoint.port > 0 else { continue }
                if Int(tcp.tcpsi_state) == TSI_S_ESTABLISHED {
                    // An accepted connection shares the listener's local port.
                    establishedByPort[endpoint.port, default: 0] += 1
                    continue
                }
                guard Int(tcp.tcpsi_state) == TSI_S_LISTEN else { continue }
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
        for index in listeners.indices where listeners[index].proto == "tcp" {
            listeners[index].connections = establishedByPort[listeners[index].port] ?? 0
        }
        return listeners
    }

    public static func localEndpoint(_ info: in_sockinfo) -> (host: String, port: Int) {
        let port = Int(UInt16(truncatingIfNeeded: info.insi_lport).bigEndian)

        let isIPv6 = (Int32(info.insi_vflag) & Int32(INI_IPV6)) != 0
        if isIPv6 {
            var address = info.insi_laddr.ina_6
            if isZero(address) {
                return ("*", port)
            }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            // An undecodable address is reported as wildcard: the "exposed"
            // badge must fail closed, not vanish.
            guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count)) != nil else { return ("*", port) }
            return (String(cString: buffer), port)
        }

        var address = info.insi_laddr.ina_46.i46a_addr4
        if address.s_addr == 0 {
            return ("*", port)
        }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil else { return ("*", port) }
        return (String(cString: buffer), port)
    }

    public static func isZero(_ address: in6_addr) -> Bool {
        withUnsafeBytes(of: address) { raw in
            raw.allSatisfy { $0 == 0 }
        }
    }
}
