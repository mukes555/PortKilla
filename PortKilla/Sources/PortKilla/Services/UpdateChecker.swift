import Foundation

/// Checks GitHub Releases for a newer version.
///
/// The app is distributed unsigned (no Apple Developer account), so instead of
/// an auto-updater like Sparkle this surfaces a "Download vX.Y.Z" menu item
/// that opens the releases page.
enum UpdateChecker {

    static let releasesPageURL = URL(string: "https://github.com/mukes555/PortKilla/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/mukes555/PortKilla/releases/latest")!

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

    enum CheckResult: Equatable {
        case newer(String)
        case upToDate
        case failed(String)
    }

    /// Fetches the latest release tag and calls back on the main queue. A
    /// network or HTTP failure is reported as such, never as "up to date".
    static func fetchNewerVersion(completion: @escaping (CheckResult) -> Void) {
        guard let current = currentVersion else {
            // Dev binary without a bundle: nothing meaningful to compare.
            DispatchQueue.main.async { completion(.failed("no version information")) }
            return
        }

        // Ignore the URL cache: a stale cached body would hide a new release.
        var request = URLRequest(url: apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let result = evaluate(data: data, response: response, error: error, current: current)
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    static func evaluate(data: Data?, response: URLResponse?, error: Error?, current: String) -> CheckResult {
        if let error {
            return .failed(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // 403 is GitHub's unauthenticated rate limit; common on shared IPs.
            return .failed("GitHub responded with \(http.statusCode)")
        }
        guard let data, let latest = parseTagName(data) else {
            return .failed("unexpected response")
        }
        return isVersion(latest, newerThan: current) ? .newer(latest) : .upToDate
    }

    /// Rate limiter for the automatic check on launch.
    static func shouldAutoCheck(now: Date = Date()) -> Bool {
        guard currentVersion != nil else { return false }
        let last = UserDefaults.standard.object(forKey: DefaultsKey.lastUpdateCheck) as? Date ?? .distantPast
        return now.timeIntervalSince(last) > 24 * 60 * 60
    }

    static func markChecked(now: Date = Date()) {
        UserDefaults.standard.set(now, forKey: DefaultsKey.lastUpdateCheck)
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
