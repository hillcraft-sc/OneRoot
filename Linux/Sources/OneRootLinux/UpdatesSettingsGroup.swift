import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// Settings ▸ General ▸ Updates, shown only for a tarball install (see
/// `InstallMethod`). One plain HTTPS request to GitHub's releases list; nothing
/// is downloaded or installed — an available release is shown with a link.
@MainActor
final class UpdatesSettingsGroup {
    let group = PreferencesGroup()
    private let center: UpdateCenter
    private let status = ActionRow()
    private let checkButton = Button(label: "Check Now")
    private let viewButton = Button(label: "View Release")
    private var watch: ObservationWatch?
    private var pageURL: URL?

    init(center: UpdateCenter) {
        self.center = center
        group.title = "Updates"
        group.description = "OneRoot was installed from the tarball, so it can look for newer Linux releases itself. Packages (.deb, .rpm, Flatpak, AUR) are updated by your package manager instead."

        let automatic = SwitchRow()
        automatic.title = "Check for updates automatically"
        automatic.subtitle = "At most once a day, when OneRoot starts. Asks GitHub for the newest release; sends nothing about you or your files. Off by default."
        automatic.subtitleLines = 0
        automatic.active = center.checksAutomatically
        automatic.onNotify(.custom("active")) { [automatic] in
            UserDefaults.standard.set(automatic.active, forKey: UpdateCenter.checksAutomaticallyKey)
        }
        group.add(automatic)

        status.title = "OneRoot \(center.currentVersion)"
        status.subtitle = "Not checked yet."
        status.subtitleLines = 0
        checkButton.valign = GTK_ALIGN_CENTER
        checkButton.setAccessibleLabel("Check for updates now")
        checkButton.onClicked { [center] in center.checkNow() }
        viewButton.valign = GTK_ALIGN_CENTER
        viewButton.addCSSClass("suggested-action")
        viewButton.visible = false
        viewButton.setAccessibleLabel("View the new release on GitHub")
        viewButton.onClicked { [weak self] in
            guard let url = self?.pageURL else { return }
            var error: UnsafeMutablePointer<GError>?
            if g_app_info_launch_default_for_uri(url.absoluteString, nil, &error) == 0, let error { g_error_free(error) }
        }
        status.addSuffix(viewButton)
        status.addSuffix(checkButton)
        group.add(status)

        watch = ObservationWatch.watch({ center.state }) { [weak self] state in self?.show(state) }
    }

    private func show(_ state: UpdateCenter.State) {
        checkButton.sensitive = state != .checking
        viewButton.visible = false
        switch state {
        case .idle: status.subtitle = "Not checked yet."
        case .checking: status.subtitle = "Checking\u{2026}"
        case .upToDate(let latest): status.subtitle = "You have the newest release (\(latest))."
        case .available(let release):
            pageURL = release.pageURL
            viewButton.visible = true
            status.subtitle = "Version \(release.version) is available."
        case .failed(let message): status.subtitle = "Couldn\u{2019}t check: \(message)"
        }
    }
}
