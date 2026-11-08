import Adwaita
import CAdwaita
import Foundation

/// Open With: the apps the desktop knows for a file's type (from its
/// .desktop files), and GTK's app chooser for the rest.
@MainActor
enum AppChooser {
    struct App {
        let id: String
        let name: String
    }

    /// The apps recommended for `url`'s type, the default first.
    static func apps(for url: URL) -> [App] {
        guard let type = g_content_type_guess(url.lastPathComponent, nil, 0, nil) else { return [] }
        defer { g_free(type) }
        var result: [App] = []
        var seen = Set<String>()
        if let defaultApp = g_app_info_get_default_for_type(type, 0) {
            if let app = app(defaultApp) { result.append(app); seen.insert(app.id) }
            g_object_unref(UnsafeMutableRawPointer(defaultApp))
        }
        let list = g_app_info_get_recommended_for_type(type)
        var node = list
        while let current = node {
            if let info = current.pointee.data.map({ OpaquePointer($0) }), let app = app(info), !seen.contains(app.id) {
                result.append(app)
                seen.insert(app.id)
            }
            node = current.pointee.next
        }
        g_list_free_full(list) { g_object_unref($0) }
        return result
    }

    private static func app(_ info: OpaquePointer) -> App? {
        guard let id = g_app_info_get_id(info), let name = g_app_info_get_display_name(info) else { return nil }
        return App(id: String(cString: id), name: String(cString: name))
    }

    /// Installed apps that look like editors or IDEs (the desktop file lists
    /// TextEditor or IDE among its categories), by name.
    static func installedEditors() -> [App] {
        let all = g_app_info_get_all()
        defer { g_list_free_full(all) { g_object_unref($0) } }
        var result: [App] = []
        var node = all
        while let current = node {
            if let info = current.pointee.data.map({ OpaquePointer($0) }),
               g_app_info_should_show(info) != 0,
               let app = app(info), isEditor(categories: categories(of: info)) {
                result.append(app)
            }
            node = current.pointee.next
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The display name of the installed app with desktop ID `id`.
    static func name(of id: String) -> String? {
        let all = g_app_info_get_all()
        defer { g_list_free_full(all) { g_object_unref($0) } }
        var node = all
        while let current = node {
            if let info = current.pointee.data.map({ OpaquePointer($0) }), let app = app(info), app.id == id { return app.name }
            node = current.pointee.next
        }
        return nil
    }

    /// The `Categories=` line of the app's desktop file, found the way the
    /// desktop does: the data folders' `applications` directories.
    private static func categories(of info: OpaquePointer) -> String {
        guard let id = g_app_info_get_id(info) else { return "" }
        return desktopCategories(forID: String(cString: id))
    }

    nonisolated static func desktopCategories(forID id: String) -> String {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var directories = [environment["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.local/share"]
        directories += (environment["XDG_DATA_DIRS"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/local/share:/usr/share")
            .split(separator: ":").map(String.init)
        directories += [home + "/.local/share/flatpak/exports/share", "/var/lib/flatpak/exports/share"]
        for directory in directories {
            let path = directory + "/applications/" + id
            if let text = try? String(contentsOfFile: path, encoding: .utf8) { return categories(inDesktopFile: text) }
        }
        return ""
    }

    nonisolated static func categories(inDesktopFile text: String) -> String {
        var inEntry = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("[") { inEntry = line == "[Desktop Entry]"; continue }
            if inEntry, line.hasPrefix("Categories=") { return String(line.dropFirst("Categories=".count)) }
        }
        return ""
    }

    nonisolated static func isEditor(categories: String) -> Bool {
        let parts = Set(categories.split(separator: ";").map(String.init))
        return parts.contains("TextEditor") || parts.contains("IDE")
    }

    /// Opens `urls` with the app whose desktop ID is `id`.
    static func launch(_ id: String, urls: [URL]) -> String? {
        let all = g_app_info_get_all()
        defer { g_list_free_full(all) { g_object_unref($0) } }
        var node = all
        while let current = node {
            if let info = current.pointee.data.map({ OpaquePointer($0) }),
               let appID = g_app_info_get_id(info), String(cString: appID) == id {
                return launch(info, urls: urls)
            }
            node = current.pointee.next
        }
        return "That app isn't installed any more."
    }

    private static func launch(_ info: OpaquePointer, urls: [URL]) -> String? {
        var list: UnsafeMutablePointer<GList>?
        for url in urls { list = g_list_append(list, strdup(url.absoluteString)) }
        defer { g_list_free_full(list) { free($0) } }
        var error: UnsafeMutablePointer<GError>?
        if g_app_info_launch_uris(info, list, nil, &error) == 0 {
            let message = error.map { String(cString: $0.pointee.message) } ?? "It couldn't be started."
            if let error { g_error_free(error) }
            return message
        }
        return nil
    }

    /// GTK's chooser: every app that can open the file, and a search.
    static func present(for url: URL, parent: ApplicationWindow, completion: @escaping (String?) -> Void) {
        let file = g_file_new_for_path(url.path)
        defer { g_object_unref(UnsafeMutableRawPointer(file)) }
        guard let dialog = gtk_app_chooser_dialog_new(parent.castedPointer(), GTK_DIALOG_MODAL, file) else { return }
        let window = UnsafeMutableRawPointer(dialog).assumingMemoryBound(to: CAdwaita.GtkWindow.self)
        let wrapper = GObjectRef(borrowing: UnsafeMutableRawPointer(dialog))
        SignalHelper.connectInt(wrapper, signal: .custom("response")) { response in
            defer { gtk_window_destroy(window) }
            guard response == GTK_RESPONSE_OK.rawValue,
                  let info = gtk_app_chooser_get_app_info(OpaquePointer(dialog)) else { return }
            defer { g_object_unref(UnsafeMutableRawPointer(info)) }
            completion(launch(info, urls: [url]))
        }
        gtk_window_present(window)
    }
}
