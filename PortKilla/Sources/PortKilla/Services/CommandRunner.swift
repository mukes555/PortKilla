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

        try task.run()

        // Read on a separate queue so a child filling the pipe buffer can never
        // deadlock against us waiting for it to exit.
        let reader = stdout.fileHandleForReading
        var outputData = Data()
        let readFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            outputData = reader.readDataToEndOfFile()
            readFinished.signal()
        }

        let commandName = (path as NSString).lastPathComponent
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            kill(task.processIdentifier, SIGKILL)
            _ = exited.wait(timeout: .now() + 1.0)
            _ = readFinished.wait(timeout: .now() + 1.0)
            throw CommandError.timedOut(commandName)
        }

        // Only close the handle once the reader is done with it; closing a
        // handle another thread is blocked on raises an exception.
        let readCompleted = readFinished.wait(timeout: .now() + timeout) == .success
        if readCompleted {
            reader.closeFile()
        }

        guard allowedExitCodes.contains(task.terminationStatus) else {
            throw CommandError.failed(command: commandName, exitCode: task.terminationStatus)
        }
        guard let output = String(data: outputData, encoding: .utf8) else {
            throw CommandError.notUTF8(commandName)
        }
        return output
    }
}
