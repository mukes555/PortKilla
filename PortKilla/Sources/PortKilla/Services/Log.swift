import Foundation
import OSLog

/// Structured logging into the unified log, with zero disk cost. Read it with:
///   log stream --predicate 'subsystem == "com.mukes555.PortKilla"' --level info
/// Process names are marked private so nothing leaks into a shared log.
enum Log {
    private static let subsystem = "com.mukes555.PortKilla"
    static let scan = Logger(subsystem: subsystem, category: "scan")
    static let kill = Logger(subsystem: subsystem, category: "kill")
    static let guardLog = Logger(subsystem: subsystem, category: "guard")
    static let update = Logger(subsystem: subsystem, category: "update")
}
