import Foundation

/// Runs a command-line tool with a hard timeout, capturing stdout.
///
/// Every external tool the app shells out to (lsof, ps, pgrep, docker) goes
/// through here so a hung subprocess can never freeze a refresh: on timeout
/// the child is SIGKILLed and an error is thrown.
enum CommandRunner {

    enum CommandError: Error, LocalizedError {
        case timedOut(String)
        case failed(command: String, exitCode: Int32)
        case notUTF8(String)

        var errorDescription: String? {
            switch self {
            case .timedOut(let command):
                return "\(command) timed out"
            case .failed(let command, let exitCode):
                return "\(command) failed (exit \(exitCode))"
            case .notUTF8(let command):
                return "\(command) produced unreadable output"
            }
        }
    }

    /// Some tools use non-zero exits for "no results" (lsof/pgrep exit 1 when
    /// nothing matches), so callers can widen `allowedExitCodes` for those.
    static func run(
        _ path: String,
        _ arguments: [String],
        timeout: TimeInterval = 5.0,
        allowedExitCodes: Set<Int32> = [0]
    ) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments

        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in exited.signal() }

        // Output arrives through a readability handler instead of a blocking
        // read on a worker thread: nothing ever parks inside read(2), so the
        // handle can always be closed, timeout included. A blocking design
        // leaked one fd and one dispatch thread every time a child hung.
        let output = OutputCollector()
        let reader = stdout.fileHandleForReading
        reader.readabilityHandler = { handle in output.read(from: handle) }
        defer { output.close(reader) }

        let commandName = (path as NSString).lastPathComponent
        try task.run()

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            // terminate() is guarded by Foundation against a reaped pid, unlike
            // a raw kill(2) after a racing exit.
            if task.isRunning {
                task.terminate()
                kill(task.processIdentifier, SIGKILL)
            }
            _ = exited.wait(timeout: .now() + 1.0)
            throw CommandError.timedOut(commandName)
        }

        // The child has exited; its output must be complete before it is
        // parsed. A pipe still held open by a grandchild counts as a hang.
        guard output.waitForEOF(timeout: max(1.0, timeout)) else {
            throw CommandError.timedOut(commandName)
        }

        guard allowedExitCodes.contains(task.terminationStatus) else {
            throw CommandError.failed(command: commandName, exitCode: task.terminationStatus)
        }
        guard let text = String(data: output.data, encoding: .utf8) else {
            throw CommandError.notUTF8(commandName)
        }
        return text
    }

    /// Accumulates pipe output and owns the handle's lifetime: reads and the
    /// close take one lock, so the fd is never closed under a read in flight
    /// (which raises an uncatchable ObjC exception).
    private final class OutputCollector {
        private let lock = NSLock()
        private let eof = DispatchSemaphore(value: 0)
        private var buffer = Data()
        private var closed = false

        func read(from handle: FileHandle) {
            lock.lock()
            defer { lock.unlock() }
            guard !closed else { return }
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                eof.signal()
            } else {
                buffer.append(chunk)
            }
        }

        func close(_ handle: FileHandle) {
            lock.lock()
            defer { lock.unlock() }
            guard !closed else { return }
            closed = true
            handle.readabilityHandler = nil
            try? handle.close()
        }

        func waitForEOF(timeout: TimeInterval) -> Bool {
            eof.wait(timeout: .now() + timeout) == .success
        }

        var data: Data {
            lock.lock()
            defer { lock.unlock() }
            return buffer
        }
    }
}
