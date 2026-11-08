import Adwaita
import Foundation

// OneRoot for Linux (#60): GTK 4 + libadwaita over the shared core.
MainContext.silenceSpuriousScrollbarWarnings()
MainQueueBridge.install()
let oneRoot = MainActor.assumeIsolated { OneRootApp() }
let status = MainActor.assumeIsolated { oneRoot.run() }
exit(Int32(status))
