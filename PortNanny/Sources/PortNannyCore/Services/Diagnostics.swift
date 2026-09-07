import Foundation
import ServiceManagement

/// Where this copy of PortNanny came from; decides what "update" means.
public enum InstallSource: String {
    case homebrew = "Homebrew"
    case applications = "Applications (DMG)"
    case development = "development build"

    public static func detect(bundleURL: URL = Bundle.main.bundleURL) -> InstallSource {
        let caskrooms = ["/opt/homebrew/Caskroom/portnanny", "/usr/local/Caskroom/portnanny"]
        let installedByBrew = caskrooms.contains { FileManager.default.fileExists(atPath: $0) }
        let inApplications = bundleURL.path.hasPrefix("/Applications/")
        if installedByBrew && inApplications { return .homebrew }
        if inApplications { return .applications }
        return .development
    }
}

/// The facts a bug report needs, gathered the same way for `portnanny
/// doctor` and Settings → About → Copy debug info.
public enum Diagnostics {
    public struct Line {
        let label: String
        let value: String
    }

    public static func report() -> [Line] {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let executable = NativeScanner.executablePath(getpid()) ?? "unknown"
        let bundle = URL(fileURLWithPath: executable).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let quarantined = (try? URL(fileURLWithPath: bundle.path).resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties) != nil

        let start = Date()
        let table = ProcessTable.capture()
        let scanMs = Int(Date().timeIntervalSince(start) * 1000)
        let scanPath = table.listeners == nil ? "lsof fallback (libproc unavailable)" : "native libproc"

        let onPath = pathResolution(of: executable)
        let login: String
        switch SMAppService.mainApp.status {
        case .enabled: login = "enabled"
        case .requiresApproval: login = "waiting for approval in System Settings → Login Items"
        case .notRegistered: login = "off"
        case .notFound: login = "not registered (not an installed .app?)"
        @unknown default: login = "unknown"
        }

        return [
            Line(label: "PortNanny", value: UpdateChecker.currentVersion ?? "dev"),
            Line(label: "macOS", value: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"),
            Line(label: "Architecture", value: currentArchitecture()),
            Line(label: "Install source", value: InstallSource.detect(bundleURL: bundle).rawValue),
            Line(label: "Executable", value: executable),
            Line(label: "Quarantine", value: quarantined ? "present (Gatekeeper will prompt)" : "cleared"),
            Line(label: "Scanner", value: "\(scanPath), \(table.allEntries.count) processes, \(table.listeners?.count ?? 0) listeners in \(scanMs) ms"),
            Line(label: "portnanny on PATH", value: onPath),
            Line(label: "Launch at login", value: login),
        ]
    }

    public static func text() -> String {
        report().map { "\($0.label): \($0.value)" }.joined(separator: "\n")
    }

    private static func currentArchitecture() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
    }

    /// Which `portnanny` a shell would run, and whether it is this binary.
    private static func pathResolution(of executable: String) -> String {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            let candidate = "\(directory)/portnanny"
            guard FileManager.default.fileExists(atPath: candidate) else { continue }
            let resolved = URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
            let same = resolved == URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
            return same ? "\(candidate) (this build)" : "\(candidate) (a different build: \(resolved))"
        }
        return "not found (Homebrew links it; otherwise symlink Contents/Helpers/portnanny)"
    }
}
