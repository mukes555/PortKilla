import Foundation

/// Debug builds only. `portkilla __serve <port>` listens until killed, so the
/// scenario tests can spawn a real server whose environment markers and
/// ancestry PortKilla then has to attribute. macOS hides the environment of
/// platform binaries such as /bin/sleep, which is why the harness uses this
/// binary rather than a system one.
enum DebugServer {
    static func serve(port: Int) -> Int32 {
        #if DEBUG
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return CLIExit.killFailed }
        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = in_addr_t(UInt32(0x7F000001).bigEndian)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(socketFD, 8) == 0 else { return CLIExit.killFailed }
        PortKillaCLI.printError("listening on 127.0.0.1:\(port)")
        while true {
            sleep(60)
        }
        #else
        PortKillaCLI.printError("portkilla: __serve is only available in debug builds")
        return CLIExit.usage
        #endif
    }
}
