import Foundation

/// Checks GitHub Releases for a newer version.
///
/// The app is distributed unsigned (no Apple Developer account), so instead of
/// an auto-updater like Sparkle this surfaces a "Download vX.Y.Z" menu item
/// that opens the releases page.
public enum UpdateChecker {

    public static let releasesPageURL = URL(string: "https://github.com/mukes555/PortNanny/releases/latest")!

    /// The page for one release: a beta is never "latest".
    public static func releasePage(for version: String) -> URL {
        URL(string: "https://github.com/mukes555/PortNanny/releases/tag/v\(version)") ?? releasesPageURL
    }
    private static let latestURL = URL(string: "https://api.github.com/repos/mukes555/PortNanny/releases/latest")!
    /// Betas never become "latest" on GitHub, so opting into them means
    /// reading the recent releases and choosing.
    private static let recentURL = URL(string: "https://api.github.com/repos/mukes555/PortNanny/releases?per_page=15")!

    public static var currentVersion: String? {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return version
        }
        return versionViaSymlinkedExecutable
    }

    /// When the CLI runs through a symlink (`/opt/homebrew/bin/portnanny`),
    /// Bundle.main does not resolve the .app around it. Ask the kernel for the
    /// real executable path (argv[0] is just "portnanny" when found via PATH)
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

    public enum CheckResult: Equatable {
        case newer(String)
        case upToDate
        case failed(String)
    }

    /// Fetches the newest release tag and calls back on the main queue. A
    /// network or HTTP failure is reported as such, never as "up to date".
    public static func fetchNewerVersion(includePrereleases: Bool = false, completion: @escaping (CheckResult) -> Void) {
        guard let current = currentVersion else {
            // Dev binary without a bundle: nothing meaningful to compare.
            DispatchQueue.main.async { completion(.failed("no version information")) }
            return
        }

        // Ignore the URL cache: a stale cached body would hide a new release.
        var request = URLRequest(url: includePrereleases ? recentURL : latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let result = evaluate(data: data, response: response, error: error, current: current, includePrereleases: includePrereleases)
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    public static func evaluate(data: Data?, response: URLResponse?, error: Error?, current: String, includePrereleases: Bool = false) -> CheckResult {
        if let error {
            return .failed(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // 403 is GitHub's unauthenticated rate limit; common on shared IPs.
            if http.statusCode == 403 || http.statusCode == 429 {
                return .failed("GitHub rate limit reached, try again in an hour")
            }
            return .failed("GitHub responded with \(http.statusCode)")
        }
        guard let data else { return .failed("unexpected response") }
        let candidates = parseTagNames(data)
        guard !candidates.isEmpty else { return .failed("unexpected response") }
        let offered = candidates.filter { isVersion($0, newerThan: current, includePrereleases: includePrereleases) }
        let newest = offered.compactMap { candidate in Version(candidate).map { (text: candidate, version: $0) } }
            .max { $0.version < $1.version }
        return newest.map { .newer($0.text) } ?? .upToDate
    }

    /// Rate limiter for the automatic check on launch.
    public static func shouldAutoCheck(now: Date = Date()) -> Bool {
        guard currentVersion != nil else { return false }
        let last = UserDefaults.standard.object(forKey: DefaultsKey.lastUpdateCheck) as? Date ?? .distantPast
        return now.timeIntervalSince(last) > 24 * 60 * 60
    }

    public static func markChecked(now: Date = Date()) {
        UserDefaults.standard.set(now, forKey: DefaultsKey.lastUpdateCheck)
    }

    public static func parseTagName(_ data: Data) -> String? {
        parseTagNames(data).first
    }

    /// One release object, or a list of them; drafts are nobody's update.
    public static func parseTagNames(_ data: Data) -> [String] {
        let object = try? JSONSerialization.jsonObject(with: data)
        let releases: [[String: Any]]
        if let one = object as? [String: Any] {
            releases = [one]
        } else if let many = object as? [[String: Any]] {
            releases = many
        } else {
            return []
        }
        return releases.compactMap { release in
            guard release["draft"] as? Bool != true, let tag = release["tag_name"] as? String else { return nil }
            return tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        }
    }

    /// Numeric semver comparison: "1.10.0" > "1.9.9". A tag with a
    /// prerelease suffix ("2.0.0-beta.1") is offered only when asked for,
    /// and ranks below the release it precedes.
    public static func isVersion(_ candidate: String, newerThan current: String, includePrereleases: Bool = false) -> Bool {
        guard let a = Version(candidate), let b = Version(current) else { return false }
        if a.prerelease != nil && !includePrereleases { return false }
        return b < a
    }

    /// "2.0.0-beta.1": numbers, then an optional prerelease that sorts below
    /// the release with the same numbers.
    struct Version: Comparable {
        let numbers: [Int]
        let prerelease: [String]?

        init?(_ text: String) {
            let dash = text.firstIndex(of: "-")
            let core = dash.map { String(text[..<$0]) } ?? text
            let parts = core.split(separator: ".").map { Int($0) }
            guard !parts.isEmpty, !parts.contains(nil) else { return nil }
            numbers = parts.compactMap { $0 }
            prerelease = dash.map { text[text.index(after: $0)...].split(separator: ".").map(String.init) }
        }

        static func < (lhs: Version, rhs: Version) -> Bool {
            for index in 0..<max(lhs.numbers.count, rhs.numbers.count) {
                let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
                let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
                if left != right { return left < right }
            }
            switch (lhs.prerelease, rhs.prerelease) {
            case (nil, nil): return false
            case (nil, _): return false
            case (_, nil): return true
            case (let left?, let right?): return identifiers(left, precede: right)
            }
        }

        /// Semver's rule: numeric identifiers compare as numbers and rank
        /// below words; a shorter list that matches is the earlier one.
        private static func identifiers(_ left: [String], precede right: [String]) -> Bool {
            for (a, b) in zip(left, right) where a != b {
                switch (Int(a), Int(b)) {
                case (let x?, let y?): return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a < b
                }
            }
            return left.count < right.count
        }
    }
}
