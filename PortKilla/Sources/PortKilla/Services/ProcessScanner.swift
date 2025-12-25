import Foundation

class ProcessScanner {

    enum ScanError: Error {
        case invalidOutput
        case commandFailed(Int32)
    }

    // Keywords to identify test processes
    private let testKeywords = [
        "jest",
        "vitest",
        "mocha",
        "jasmine",
        "karma",
        "react-scripts test",
        "ava",
        "tape",
        "cypress",
        "playwright",
        "puppeteer",
        "selenium",
        "webdriver",
        "nightwatch",
        "protractor",
        "testcafe"
    ]

    func scanTestProcesses() -> [TestProcessInfo] {
        let task = Process()
        let pipe = Pipe()

        // Use ps to list all processes with PID, RSS (memory), and Command
        task.launchPath = "/bin/ps"
        task.arguments = ["-A", "-o", "pid=,rss=,command="]
        task.standardOutput = pipe

        do {
            try task.run()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            pipe.fileHandleForReading.closeFile()
            task.waitUntilExit()

            if task.terminationStatus != 0 {
                return []
            }

            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }

            return parseProcessOutput(output)
        } catch {
            return []
        }
    }

    func parseProcessOutput(_ output: String) -> [TestProcessInfo] {
        let lines = output.components(separatedBy: "\n")
        var processes: [TestProcessInfo] = []

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty else { continue }

            // ps output format: PID RSS COMMAND (args...)
            // 12345 1024 /usr/local/bin/node ...

            let parts = trimmedLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 3 else { continue }

            guard let pid = Int(parts[0]),
                  let memoryKb = Int(parts[1]) else { continue }

            let command = String(parts[2])

            // Check if it's a test process
            if let type = determineTestType(command: command) {
                let processName = extractProcessName(from: command)
                let memory = formatMemory(kilobytes: memoryKb)

                let info = TestProcessInfo(
                    pid: pid,
                    processName: processName,
                    command: command,
                    memoryUsage: memory,
                    memorySizeKB: memoryKb,
                    type: type
                )
                processes.append(info)
            }
        }

        return processes
    }

    private func determineTestType(command: String) -> TestProcessInfo.TestType? {
        let lowerCommand = command.lowercased()

        // Filter out PortKilla itself and common system tools to avoid false positives
        if lowerCommand.contains("portkilaa") || lowerCommand.contains("grep") {
            return nil
        }

        // Exclude common dev servers that might trigger false positives (e.g. if they have 'test' in path)
        if lowerCommand.contains("next dev") || lowerCommand.contains("next start") || lowerCommand.contains("react-scripts start") {
            return nil
        }

        // Exclude internal drivers/helpers
        if lowerCommand.contains("run-driver") || lowerCommand.contains("ms-playwright-go") {
            return nil
        }

        if lowerCommand.contains("jest") { return .jest }
        if lowerCommand.contains("vitest") { return .vitest }
        if lowerCommand.contains("mocha") { return .mocha }

        // Generic check
        for keyword in testKeywords {
            if lowerCommand.contains(keyword) {
                return .other
            }
        }

        return nil
    }

    private func extractProcessName(from command: String) -> String {
        // Simple extraction: get the last component of the executable path
        // e.g., "/usr/local/bin/node /path/to/jest.js" -> "node" (or "jest" if we are smart)

        let components = command.components(separatedBy: " ")
        if let first = components.first {
            let pathComponents = first.components(separatedBy: "/")
            if let last = pathComponents.last {
                return last
            }
        }
        return "Unknown"
    }

    private func formatMemory(kilobytes: Int) -> String {
        let mb = Double(kilobytes) / 1024.0
        if mb < 1 {
            return "\(kilobytes)KB"
        } else if mb < 1024 {
            return String(format: "%.1fMB", mb)
        } else {
            return String(format: "%.2fGB", mb / 1024.0)
        }
    }
}
