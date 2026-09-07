import Foundation
import CLibProc

// MARK: - Peers
// Who is connected to a listener right now: the remote end of each
// established connection the process holds on that port.
extension NativeScanner {

    public struct Peer: Equatable, Encodable {
        public let host: String
        public let port: Int
        /// "local" (this machine), "lan" (a private range), or "remote".
        public let kind: String

        public init(host: String, port: Int) {
            self.host = host
            self.port = port
            self.kind = Peer.classify(host)
        }

        public var label: String { "\(host):\(port)" }

        static func classify(_ host: String) -> String {
            if host == "127.0.0.1" || host == "::1" || host.hasPrefix("::ffff:127.") { return "local" }
            let isPrivateV4 = host.hasPrefix("10.") || host.hasPrefix("192.168.")
                || (host.hasPrefix("172.") && (16...31).contains(Int(host.split(separator: ".").dropFirst().first ?? "") ?? -1))
            let isLinkLocal = host.hasPrefix("fe80:") || host.hasPrefix("169.254.") || host.hasPrefix("fd") || host.hasPrefix("fc")
            return isPrivateV4 || isLinkLocal ? "lan" : "remote"
        }
    }

    /// Remote ends of the established TCP connections `pid` holds on
    /// `localPort`, most recent descriptors last. One process, so cheap
    /// enough to run on demand.
    public static func peers(of pid: Int32, localPort: Int) -> [Peer] {
        var fdBuffer = makeFdBuffer()
        let count = fillDescriptors(pid, fdBuffer: &fdBuffer)
        guard count > 0 else { return [] }

        var peers: [Peer] = []
        for fd in fdBuffer.prefix(count) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
            var socketInfo = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &socketInfo, size) == size,
                  Int(socketInfo.psi.soi_kind) == SOCKINFO_TCP else { continue }
            let tcp = socketInfo.psi.soi_proto.pri_tcp
            guard Int(tcp.tcpsi_state) == TSI_S_ESTABLISHED, localEndpoint(tcp.tcpsi_ini).port == localPort else { continue }
            let remote = remoteEndpoint(tcp.tcpsi_ini)
            peers.append(Peer(host: remote.host, port: remote.port))
        }
        return peers
    }

    public static func remoteEndpoint(_ info: in_sockinfo) -> (host: String, port: Int) {
        let port = Int(UInt16(truncatingIfNeeded: info.insi_fport).bigEndian)
        let isIPv6 = (Int32(info.insi_vflag) & Int32(INI_IPV6)) != 0
        if isIPv6 {
            var address = info.insi_faddr.ina_6
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count)) != nil else { return ("?", port) }
            return (String(cString: buffer), port)
        }
        var address = info.insi_faddr.ina_46.i46a_addr4
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil else { return ("?", port) }
        return (String(cString: buffer), port)
    }

    /// "3 clients: 2 local, 1 from the network"
    public static func summary(of peers: [Peer]) -> String {
        guard !peers.isEmpty else { return "no clients connected" }
        let local = peers.filter { $0.kind == "local" }.count
        let lan = peers.filter { $0.kind == "lan" }.count
        let remote = peers.count - local - lan
        var parts: [String] = []
        if local > 0 { parts.append("\(local) local") }
        if lan > 0 { parts.append("\(lan) from the local network") }
        if remote > 0 { parts.append("\(remote) from elsewhere") }
        return "\(peers.count) client\(peers.count == 1 ? "" : "s"): " + parts.joined(separator: ", ")
    }
}
