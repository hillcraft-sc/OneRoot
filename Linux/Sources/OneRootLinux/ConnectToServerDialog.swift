import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// Connect to Server (Ctrl+K): mounts an smb://, nfs://, sftp://, ftp:// or
/// dav:// address through GIO/GVfs (`NetworkMounter`) and opens it. Favorite
/// servers are the shared `SavedServersService`; a login is kept in the
/// desktop keyring when asked, by server host.
@MainActor
enum ConnectToServerDialog {
    static let schemes: Set<String> = ["smb", "nfs", "sftp", "ssh", "ftp", "ftps", "dav", "davs", "afp"]

    /// The address as typed, with a scheme, or nil when it isn't one gio can mount.
    static func parse(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), schemes.contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// What the keyring holds for a server: the user name and password.
    private struct Login: Codable { var username: String; var password: String }

    /// The login remembered for this server under any of its names.
    private static func savedLogin(for url: URL) async -> Login? {
        guard let host = url.host else { return nil }
        for account in await NetworkHostAliases.accounts(for: host) {
            if let json = KeyringService.network.password(account: account),
               let login = try? JSONDecoder().decode(Login.self, from: Data(json.utf8)) { return login }
        }
        return nil
    }

    /// The login the keyring holds for `url`'s server, ready for the mounter.
    static func savedCredentials(for url: URL) async -> NetworkMounter.Credentials? {
        await savedLogin(for: url).map { NetworkMounter.Credentials(username: $0.username, password: $0.password) }
    }

    static func present(window: AppWindow, address prefilled: String? = nil) {
        let dialog = Dialogs.alert(
            heading: "Connect to Server",
            body: "Enter an address such as smb://server/share, sftp://host/path, ftp://host or dav://host/path.",
            responses: [("cancel", "Cancel"), ("connect", "Connect")], suggested: "connect")
        dialog.preferWideLayout = true

        let address = EntryRow()
        address.title = "Server address"
        address.setAccessibleLabel("Server address")
        address.inputPurpose = GTK_INPUT_PURPOSE_URL
        let user = EntryRow()
        user.title = "User name (optional)"
        user.setAccessibleLabel("User name")
        let password = PasswordEntryRow()
        password.title = "Password"
        password.setAccessibleLabel("Password")
        let remember = SwitchRow()
        remember.title = "Remember the login in the keyring"
        remember.subtitle = "Kept in the desktop keyring (Secret Service), never in OneRoot\u{2019}s settings."
        let favorite = SwitchRow()
        favorite.title = "Add to Favorites"
        favorite.subtitle = "Keeps this server at the top of the Network window."
        let fields = ListBox()
        fields.addCSSClass("boxed-list")
        fields.selectionMode = GTK_SELECTION_NONE
        for row in [address, user, password] as [Widget] { fields.append(row) }
        fields.append(remember)
        fields.append(favorite)
        dialog.extraChild = fields

        // A server whose login was remembered fills in as soon as its address is
        // there (typed or picked), unless a login has already been typed.
        func fillSavedLogin() {
            guard let url = parse(address.text) else { return }
            if SavedServersService().load().contains(where: { NetworkPlaces.key($0.url) == NetworkPlaces.key(url) }) {
                favorite.active = true
            }
            guard user.text.isEmpty, password.text.isEmpty else { return }
            let typed = address.text
            Task { @MainActor in
                // Still the same address, and nothing typed meanwhile.
                guard address.text == typed, user.text.isEmpty, password.text.isEmpty, let login = await savedLogin(for: url) else { return }
                user.text = login.username
                password.text = login.password
                remember.active = true
            }
        }
        address.onChanged { fillSavedLogin() }

        dialog.onResponse { response in
            guard response == "connect" else { return }
            guard let url = parse(address.text) else {
                Dialogs.showError("Check the Address", "Enter an address that starts with smb://, nfs://, sftp://, ftp:// or dav://.", parent: window.window)
                return
            }
            let name = user.text.trimmingCharacters(in: .whitespaces)
            let login = name.isEmpty ? nil : NetworkMounter.Credentials(username: name, password: password.text)
            connect(to: url, login: login, remember: remember.active, favorite: favorite.active, window: window)
        }
        if let prefilled { address.text = prefilled }
        fillSavedLogin()
        dialog.present(window.window)
        MainContext.delay(ms: 60) { _ = address.grabFocus() }
    }

    /// Mounts and opens `url` in the active tab; reports what went wrong.
    static func connect(to url: URL, login typed: NetworkMounter.Credentials?, remember rememberRequested: Bool, favorite: Bool = false, window: AppWindow) {
        window.showToast("Connecting to \(url.host ?? url.absoluteString)\u{2026}")
        Task { @MainActor in
            // Nothing typed: use the login remembered for this server, and keep it remembered.
            let saved = typed == nil ? await savedCredentials(for: url) : nil
            let login = typed ?? saved
            let remember = rememberRequested || saved != nil
            do {
                let folder = try await NetworkMounter().mount(url, credentials: login)
                if let host = url.host {
                    // Under every name the server goes by, so the host name the
                    // network announces finds a login saved for its IP address.
                    let accounts = await NetworkHostAliases.accounts(for: host)
                    if remember, let login, let json = try? JSONEncoder().encode(Login(username: login.username, password: login.password)) {
                        for account in accounts {
                            do { try KeyringService.network.store(String(decoding: json, as: UTF8.self), account: account, label: "OneRoot login for \(account)") }
                            catch {
                                Dialogs.showError("Couldn\u{2019}t Remember the Login",
                                                  "\(error.localizedDescription) Remembering a login needs a Secret Service such as GNOME Keyring or KeePassXC running. The connection itself worked.",
                                                  parent: window.window)
                                break
                            }
                        }
                    } else if !remember {
                        for account in accounts { KeyringService.network.remove(account: account) }
                    }
                }
                if favorite { SavedServersService().add(SavedServer(name: url.host ?? url.absoluteString, url: url)) }
                window.activePane?.navigate(to: folder)
            } catch {
                // A login is needed (none remembered, or it was refused): ask for it.
                if let failure = error as? NetworkMounter.Failure, failure == .needsLogin || failure == .authentication {
                    window.showToast("\(url.host ?? "The server") needs a login.")
                    present(window: window, address: url.absoluteString)
                    return
                }
                let browsable = (error as? NetworkMounter.Failure).map { if case .notBrowsable = $0 { return false } else { return true } } ?? true
                Dialogs.showError(browsable ? "Couldn\u{2019}t Connect to \(url.host ?? url.absoluteString)" : "Connected, but Can\u{2019}t Browse It",
                                  error.localizedDescription, parent: window.window)
            }
        }
    }
}
