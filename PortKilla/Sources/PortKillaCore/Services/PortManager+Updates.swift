import Foundation

// MARK: - Updates
// Once a day (when allowed), and on request from About.
extension PortManager {

    public func checkForUpdates(manual: Bool) {
        UpdateChecker.fetchNewerVersion(includePrereleases: includePrereleases) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .newer(let version):
                UpdateChecker.markChecked()
                self.updateAvailableVersion = version
                if manual { self.showToast("v\(version) available") }
            case .upToDate:
                UpdateChecker.markChecked()
                self.updateAvailableVersion = nil
                if manual { self.showToast("You're up to date") }
            case .failed(let reason):
                // Not marked as checked, so the next launch tries again.
                Log.update.error("update check failed: \(reason, privacy: .public)")
                if manual { self.showToast("Couldn't check for updates: \(reason)") }
            }
        }
    }
}
