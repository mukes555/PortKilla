import Foundation

/// One shared human-readable memory formatter (was duplicated in three files).
enum MemoryFormat {
    static func string(kilobytes: Int) -> String {
        let mb = Double(kilobytes) / 1024.0
        if mb < 1 { return "\(kilobytes)KB" }
        if mb < 1024 { return String(format: "%.1fMB", mb) }
        return String(format: "%.2fGB", mb / 1024.0)
    }
}

/// Turns ps's etime ("[[dd-]hh:]mm:ss") into "2d 3h" / "3h 12m" / "12m" / "45s".
enum ElapsedFormat {
    static func humanize(_ etime: String) -> String? {
        var remainder = etime.trimmingCharacters(in: .whitespaces)
        if remainder.isEmpty { return nil }

        var days = 0
        if let dash = remainder.firstIndex(of: "-") {
            days = Int(remainder[..<dash]) ?? 0
            remainder = String(remainder[remainder.index(after: dash)...])
        }

        let parts = remainder.split(separator: ":").map { Int($0) ?? 0 }
        switch (days, parts.count) {
        case (0, 2):
            let (minutes, seconds) = (parts[0], parts[1])
            return minutes > 0 ? "\(minutes)m" : "\(seconds)s"
        case (0, 3):
            return "\(parts[0])h \(parts[1])m"
        case (_, 3) where days > 0:
            return "\(days)d \(parts[0])h"
        default:
            return nil
        }
    }
}
