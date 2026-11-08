import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// The Network window: your Favorites at the top (each with a delete button),
/// then the servers the network announces. Choosing one connects at once with
/// the login remembered for it. "Enter Address…" opens Connect to Server.
@MainActor
enum BrowseNetworkDialog {
    static func present(window: AppWindow) {
        let favorites = SavedServersService()
        var found: [NetworkServer] = []
        var aliases: [String: Set<String>] = [:]
        var rowPlaces: [NetworkPlace?] = []
        var finished = false

        // "close" is listed first: it is what closing the window answers with.
        let dialog = Dialogs.alert(
            heading: "Network",
            body: "Choose a server to connect to it.",
            responses: [("close", "Close"), ("address", "Enter Address\u{2026}")], defaultResponse: "close")
        dialog.preferWideLayout = true

        let list = ListBox()
        list.addCSSClass("boxed-list")
        list.selectionMode = GTK_SELECTION_NONE
        list.setAccessibleLabel("Servers")
        let scroller = ScrolledWindow(child: list)
        scroller.setPolicy(horizontal: GTK_POLICY_NEVER, vertical: GTK_POLICY_AUTOMATIC)
        scroller.propagateNaturalHeight = true
        gtk_scrolled_window_set_max_content_height(OpaquePointer(scroller.pointer), 320)
        let status = Label("Looking for servers on your network\u{2026}")
        status.addCSSClass(.dimLabel)
        status.halign = GTK_ALIGN_START
        status.wrap = true
        let box = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 10)
        box.append(scroller)
        box.append(status)
        dialog.extraChild = box

        func sectionHeader(_ text: String) -> ListBoxRow {
            let label = Label(text)
            label.addCSSClass("heading")
            label.halign = GTK_ALIGN_START
            label.marginStart = 12
            label.marginTop = 8
            label.marginBottom = 4
            let row = ListBoxRow()
            row.child = label
            row.selectable = false
            row.activatable = false
            return row
        }

        func rebuild() {
            let places = NetworkPlaces.combine(favorites: favorites.load(), found: found, aliases: aliases)
            list.removeAll()
            rowPlaces = []
            scroller.visible = !places.isEmpty
            var lastKind: NetworkPlace.Kind?
            for place in places {
                if place.kind != lastKind {
                    lastKind = place.kind
                    list.append(sectionHeader(place.kind == .favorite ? "Favorites" : "On Your Network"))
                    rowPlaces.append(nil)
                }
                let row = ActionRow(title: place.title, subtitle: place.address)
                row.activatable = true
                if let id = place.favoriteID {
                    let delete = Button(iconName: "user-trash-symbolic")
                    delete.addCSSClass(.flat)
                    delete.valign = GTK_ALIGN_CENTER
                    delete.tooltipText = "Remove from Favorites"
                    delete.setAccessibleLabel("Remove \(place.title) from Favorites")
                    delete.onClicked {
                        // Forget the favorite and the login kept for it.
                        favorites.remove(id: id)
                        if let host = place.url?.host {
                            Task { @MainActor in
                                for account in await NetworkHostAliases.accounts(for: host) { KeyringService.network.remove(account: account) }
                            }
                        }
                        rebuild()
                    }
                    row.addSuffix(delete)
                }
                list.append(row)
                rowPlaces.append(place)
            }
        }

        list.onRowActivated { row in
            guard !finished, row.index < rowPlaces.count, let url = rowPlaces[row.index]?.url else { return }
            finished = true
            _ = adw_dialog_close(dialog.castedPointer() as UnsafeMutablePointer<AdwDialog>)
            ConnectToServerDialog.connect(to: url, login: nil, remember: false, window: window)
        }
        dialog.onResponse { response in
            let wasOpen = !finished
            finished = true
            if response == "address", wasOpen { ConnectToServerDialog.present(window: window) }
        }
        rebuild()
        dialog.present(window.window)

        Task { @MainActor in
            let result = await NetworkBrowser.discover()
            guard !finished else { return }
            switch result {
            case .success(let servers):
                found = servers
                status.text = servers.isEmpty ? "No servers announced themselves on your network. Use Enter Address to type one." : ""
            case .failure(let failure):
                status.text = "Browsing the network isn\u{2019}t available here (\(failure.localizedDescription)). It needs gvfs-dnssd and the Avahi service. Use Enter Address to type an address."
            }
            status.visible = !status.text.isEmpty
            // Match each name to its addresses, so a favorite saved under an IP
            // address isn't listed again under the name the network announces.
            let hosts = Set((favorites.load().map(\.url) + found.compactMap { URL(string: $0.address) }).compactMap { $0.host?.lowercased() })
            await withTaskGroup(of: (String, [String]).self) { group in
                for host in hosts { group.addTask { (host, await NetworkHostAliases.accounts(for: host)) } }
                for await (host, names) in group { aliases[host] = Set(names) }
            }
            guard !finished else { return }
            rebuild()
        }
    }
}
