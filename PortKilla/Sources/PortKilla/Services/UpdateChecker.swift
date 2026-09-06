import Foundation

/// Checks GitHub Releases for a newer version.
///
/// The app is distributed unsigned (no Apple Developer account), so instead of
/// an auto-updater like Sparkle this surfaces a "Download vX.Y.Z" menu item
/// that opens the releases page.
enum UpdateChecker {

    static let releasesPageURL = URL(string: "https://github.com/mukes555/PortKilla/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/mukes555/PortKilla/releases/latest")!
    private static let lastCheckKey = "PortKilla.lastUpdateCheck"

    static var currentVersion: String? {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return version
        }
        return versionViaSymlinkedExecutable
    }

    /// When the CLI runs through a symlink (`/opt/homebrew/bin/portkilla`),
    /// Bundle.main does not resolve the .app around it. Ask the kernel for the
    /// real executable path (argv[0] is just "portkilla" when found via PATH)
    /// and read the bundle's Info.plist from there.
    private static var versionViaSymlinkedExecutable: String? {
        guard let path = NativeScanner.executablePath(getpid()) else { return nil }
        let executable = URL(fileURLWithPath: path)
        // <App>.app/Contents/MacOS/<exe> -> <App>.app/Contents/Info.plist
        let plist = executable.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return info["CFBundleShortVersionString"] as? String
    }

    /// Fetches the latest release tag; calls back on the main queue with the
    /// newer version string, or nil when up to date / undeterminable.
    static func fetchNewerVersion(completion: @escaping (String?) -> Void) {
        guard let current = currentVersion else {
            // Dev binary without a bundle — nothing meaningful to compare.
            DispatchQueue.main.async { completion(nil) }
            return
        }

        var request = URLRequest(url: apiURL, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            let latest = data.flatMap(parseTagName)
            let newer = latest.flatMap { isVersion($0, newerThan: current) ? $0 : nil }
            DispatchQueue.main.async { completion(newer) }
        }.resume()
    }

    /// Rate limiter for the automatic check on launch.
    static func shouldAutoCheck(now: Date = Date()) -> Bool {
        guard currentVersion != nil else { return false }
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        return now.timeIntervalSince(last) > 24 * 60 * 60
    }

    static func markChecked(now: Date = Date()) {
        UserDefaults.standard.set(now, forKey: lastCheckKey)
    }

    static func parseTagName(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        return tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Numeric semver comparison: "1.10.0" > "1.9.9".
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }

        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }
}
