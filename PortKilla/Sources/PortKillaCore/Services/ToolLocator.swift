import Foundation

/// Finds a command-line tool the way a user's shell would, plus the places
/// version managers hide them, because the app's own PATH is the bare
/// system one and the CLI may run from an agent with a trimmed one.
public enum ToolLocator {
    public static func resolve(_ tool: String, path: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
                               home: String = NSHomeDirectory()) -> String? {
        if tool.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: tool) ? tool : nil
        }
        let directories = path.split(separator: ":").map(String.init) + commonDirectories(home: home)
        for directory in directories {
            let candidate = "\(directory)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    static func commonDirectories(home: String) -> [String] {
        var directories = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
                           "\(home)/.volta/bin", "\(home)/.bun/bin", "\(home)/Library/pnpm", "\(home)/.local/share/pnpm",
                           "\(home)/.yarn/bin", "\(home)/.local/bin"]
        // nvm and fnm keep one bin directory per Node version.
        for versions in ["\(home)/.nvm/versions/node", "\(home)/.local/share/fnm/node-versions"] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: versions)) ?? []
            for name in names.sorted().reversed() {
                directories.append("\(versions)/\(name)/bin")
                directories.append("\(versions)/\(name)/installation/bin")
            }
        }
        return directories
    }
}
