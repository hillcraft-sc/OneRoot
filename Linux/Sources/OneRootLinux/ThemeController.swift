import Adwaita
import CAdwaita
import Foundation
@testable import OneRoot

/// The Linux side of theming: the shared `ThemeStore` (what's chosen, and
/// whether Automatic follows the desktop's light or dark scheme) turned into
/// libadwaita's color scheme and a CSS provider (`ThemeCSS`).
@MainActor
final class ThemeController {
    let store: ThemeStore
    private let provider = CSSProvider()
    private var watch: ObservationWatch?
    private var darkConnection: SignalConnection?

    init() {
        let manager = StyleManager.default
        store = ThemeStore(
            systemIsDark: { StyleManager.default.dark },
            applyAppearance: { isDark in
                switch isDark {
                case .some(true): StyleManager.default.forceDark()
                case .some(false): StyleManager.default.forceLight()
                case .none: StyleManager.default.resetColorScheme()
                }
            },
            observesSystemAppearance: false
        )
        // The desktop switched between light and dark: Automatic follows.
        darkConnection = manager.onDarkChanged { [weak store] in store?.systemAppearanceChanged() }
        apply(store.current)
        provider.addToDefaultDisplay()
        watch = ObservationWatch.watch({ [store] in store.current }, emitsInitialValue: false) { [weak self] theme in
            self?.apply(theme)
        }
    }

    private func apply(_ theme: Theme) {
        provider.loadFromString(ThemeCSS.css(for: theme))
    }
}
