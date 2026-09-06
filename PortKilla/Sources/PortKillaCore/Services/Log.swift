import Foundation
import OSLog

/// Structured logging into the unified log, with zero disk cost. Read it with:
///   log stream --predicate 'subsystem == "com.mukes555.PortKilla"' --level info
/// Process names are marked private so nothing leaks into a shared log.
public enum Log {
    private static let subsystem = "com.mukes555.PortKilla"
    public static let scan = Logger(subsystem: subsystem, category: "scan")
    public static let kill = Logger(subsystem: subsystem, category: "kill")
    public static let guardLog = Logger(subsystem: subsystem, category: "guard")
    public static let update = Logger(subsystem: subsystem, category: "update")
}
