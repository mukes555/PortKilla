import Foundation

/// Facts about a process that cannot change after exec: its executable path,
/// its argv, and the allowlisted environment markers. They are read once per
/// (pid, start time) and reused by every later refresh. A recycled pid has a
/// different start time and therefore gets a fresh entry.
///
/// This is where most of a refresh's cost used to go: two sysctls plus a
/// 4 KB path buffer for every one of ~600 processes, every two seconds, to
/// learn things that had not changed since the last time.
final class ProcessFacts {
    static let shared = ProcessFacts()

    struct Facts: Equatable {
        let executablePath: String?
        let command: String?
    }

    private struct Entry {
        let startTime: UInt64
        let facts: Facts
        var markers: [String: String]?
    }

    private let lock = NSLock()
    private var entries: [Int32: Entry] = [:]
    private let readPath: (Int32) -> String?
    private let readCommand: (Int32) -> String?
    private let readMarkers: (Int32, Set<String>) -> [String: String]

    init(readPath: @escaping (Int32) -> String? = NativeScanner.executablePath,
         readCommand: @escaping (Int32) -> String? = NativeScanner.commandLine,
         readMarkers: @escaping (Int32, Set<String>) -> [String: String] = NativeScanner.environmentMarkers) {
        self.readPath = readPath
        self.readCommand = readCommand
        self.readMarkers = readMarkers
    }

    /// Path and argv for `pid`, read from the kernel only the first time this
    /// (pid, start time) is seen.
    func facts(for pid: Int32, startedAt startTime: UInt64) -> Facts {
        lock.lock()
        if let entry = entries[pid], entry.startTime == startTime {
            lock.unlock()
            return entry.facts
        }
        lock.unlock()

        // Kernel reads happen outside the lock; a concurrent capture of the
        // same pid just does the same cheap work twice.
        let facts = Facts(executablePath: readPath(pid), command: readCommand(pid))
        lock.lock()
        entries[pid] = Entry(startTime: startTime, facts: facts, markers: nil)
        lock.unlock()
        return facts
    }

    /// Environment markers for `pid`, cached alongside its facts. A pid this
    /// cache has not captured is read directly and not remembered.
    func markers(for pid: Int32, keys: Set<String>) -> [String: String] {
        lock.lock()
        if let cached = entries[pid]?.markers {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let markers = readMarkers(pid, keys)
        lock.lock()
        entries[pid]?.markers = markers
        lock.unlock()
        return markers
    }

    /// Drops entries for processes that no longer exist.
    func prune(keeping live: Set<Int32>) {
        lock.lock()
        entries = entries.filter { live.contains($0.key) }
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }
}
