import Adwaita
import CMainQueue

/// GTK runs GLib's main loop, which never looks at Swift's main queue — so
/// `DispatchQueue.main.async`, `Task { @MainActor … }` and everything the
/// shared view models schedule that way would never run. This hands the
/// main queue's wake-up descriptor to GLib and drains the queue whenever
/// it fires (what Foundation's run loop does on Linux).
enum MainQueueBridge {
    static func install() {
        let channel = g_io_channel_unix_new(oneroot_main_queue_fd())
        g_io_add_watch(channel, G_IO_IN, { _, _, _ in
            oneroot_drain_main_queue()
            return 1 // keep watching
        }, nil)
    }
}
