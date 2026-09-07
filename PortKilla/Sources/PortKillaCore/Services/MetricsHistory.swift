import Foundation

/// The last two minutes of CPU and memory per process, one sample per scan,
/// for sparklines. Kept apart from the port list so rows are not re-rendered
/// every scan: only the sparkline views observe this.
public final class MetricsHistory: ObservableObject {
    public struct Sample: Equatable {
        public let cpuPercent: Double
        public let memoryKB: Int
        public let at: Date
    }

    public static let capacity = 60

    /// Bumps once per recording; views observe this, not the samples.
    @Published public private(set) var tick = 0
    private var samples: [Int: [Sample]] = [:]
    private let lock = NSLock()

    public init() {}

    /// Records one sample per process seen in this scan and forgets the
    /// processes that are gone. Call on the main queue.
    public func record(_ ports: [PortInfo], at date: Date = Date()) {
        lock.lock()
        var seen = Set<Int>()
        for port in ports where !seen.contains(port.pid) {
            seen.insert(port.pid)
            var history = samples[port.pid] ?? []
            history.append(Sample(cpuPercent: port.cpuPercent, memoryKB: port.memorySizeKB, at: date))
            if history.count > Self.capacity {
                history.removeFirst(history.count - Self.capacity)
            }
            samples[port.pid] = history
        }
        samples = samples.filter { seen.contains($0.key) }
        lock.unlock()
        tick += 1
    }

    public func samples(for pid: Int) -> [Sample] {
        lock.lock()
        defer { lock.unlock() }
        return samples[pid] ?? []
    }

    public func cpu(for pid: Int) -> [Double] {
        samples(for: pid).map(\.cpuPercent)
    }

    public func memoryKB(for pid: Int) -> [Double] {
        samples(for: pid).map { Double($0.memoryKB) }
    }
}
