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

/// Human-readable process ages: "2d 3h" / "3h 12m" / "12m" / "45s".
enum ElapsedFormat {

    static func humanize(seconds total: Int) -> String? {
        guard total >= 0 else { return nil }
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total % 60)s"
    }

    /// Parses ps's etime format ("[[dd-]hh:]mm:ss") into seconds.
    static func seconds(fromEtime etime: String) -> Int? {
        var remainder = etime.trimmingCharacters(in: .whitespaces)
        if remainder.isEmpty { return nil }

        var days = 0
        if let dash = remainder.firstIndex(of: "-") {
            days = Int(remainder[..<dash]) ?? 0
            remainder = String(remainder[remainder.index(after: dash)...])
        }

        let parts = remainder.split(separator: ":").map { Int($0) ?? 0 }
        switch parts.count {
        case 2:
            return days * 86_400 + parts[0] * 60 + parts[1]
        case 3:
            return days * 86_400 + parts[0] * 3_600 + parts[1] * 60 + parts[2]
        default:
            return nil
        }
    }

}
