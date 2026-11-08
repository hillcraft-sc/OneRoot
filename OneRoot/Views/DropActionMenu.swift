import AppKit

/// What to do with files dropped while ⌃ was held.
enum DropAction: Int {
    case move, copy, alias
}

/// Holding ⌃ while dropping files asks what to do — **Move Here**, **Copy
/// Here**, **Make Alias Here**, or Cancel — the way a right-drag does on
/// Windows. (A real right-drag doesn't fit macOS: context menus open on
/// right mouse *down*, so there's no drag to start.) Works for drags from
/// Finder and other apps too. Used by the file list (list and grid) and
/// the folder hierarchy.
@MainActor
enum DropActionMenu {
    /// ⌃ held right now.
    static var isRequested: Bool {
        NSEvent.modifierFlags.contains(.control)
    }

    /// What a drop target's validate method should report. ⌃ narrows the
    /// drag source's operations to Link, so asking has to propose Link or
    /// AppKit refuses the drop.
    static func operation(for info: NSDraggingInfo) -> NSDragOperation {
        let mask = info.draggingSourceOperationMask
        if isRequested, mask.contains(.link) { return .link }
        return mask.contains(.move) ? .move : .copy
    }

    /// Whether this drop should ask (⌃ held, and the source allows it).
    static func shouldAsk(for info: NSDraggingInfo) -> Bool {
        isRequested && info.draggingSourceOperationMask.contains(.link)
    }

    /// Shows the menu at the pointer once the drop has finished (so the
    /// drag session isn't held open while the menu tracks) and calls
    /// `choose` with the pick; Cancel or clicking away calls nothing.
    static func ask(_ choose: @escaping (DropAction) -> Void) {
        let location = NSEvent.mouseLocation
        DispatchQueue.main.async {
            let target = MenuTarget(choose)
            let menu = NSMenu()
            menu.autoenablesItems = false
            for (title, action) in [("Move Here", DropAction.move), ("Copy Here", .copy), ("Make Alias Here", .alias)] {
                let item = NSMenuItem(title: title, action: #selector(MenuTarget.choose(_:)), keyEquivalent: "")
                item.target = target
                item.tag = action.rawValue
                menu.addItem(item)
            }
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Cancel", action: nil, keyEquivalent: ""))
            menu.popUp(positioning: nil, at: location, in: nil)
            withExtendedLifetime(target) {}
        }
    }

    private final class MenuTarget: NSObject {
        let choose: (DropAction) -> Void
        init(_ choose: @escaping (DropAction) -> Void) { self.choose = choose }

        @objc func choose(_ sender: NSMenuItem) {
            guard let action = DropAction(rawValue: sender.tag) else { return }
            choose(action)
        }
    }
}
