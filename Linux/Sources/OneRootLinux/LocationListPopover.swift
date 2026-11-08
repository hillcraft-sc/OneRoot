import Adwaita
import CAdwaita
import Foundation

/// A small popover under a widget: a scrolling list of titled rows, each
/// running its action. Used for a crumb's subfolders and menu, and the
/// Back/Forward history. One at a time.
@MainActor
enum LocationListPopover {
    struct Item {
        let title: String
        let icon: String?
        let action: @MainActor () -> Void
        init(_ title: String, icon: String? = nil, action: @escaping @MainActor () -> Void) {
            self.title = title
            self.icon = icon
            self.action = action
        }
    }

    private static var current: Popover?

    static func show(_ items: [Item], from anchor: Widget, label: String) {
        if let old = current { old.popdown(); old.unparent(); current = nil }
        let popover = Popover()
        popover.hasArrow = false
        popover.autohide = true
        popover.position = GTK_POS_BOTTOM
        popover.halign = GTK_ALIGN_START
        let list = ListBox()
        list.selectionMode = GTK_SELECTION_NONE
        list.addCSSClass("navigation-sidebar")
        list.setAccessibleLabel(label)
        for item in items {
            let row = ListBoxRow()
            let content = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
            if let icon = item.icon { content.append(Image(iconName: icon)) }
            let text = Label(item.title)
            text.xalign = 0
            text.ellipsize = PANGO_ELLIPSIZE_MIDDLE
            text.maxWidthChars = 40
            text.hexpand = true
            content.append(text)
            row.child = content
            list.append(row)
        }
        list.onRowActivated { [weak popover] row in
            guard row.index < items.count else { return }
            popover?.popdown()
            items[row.index].action()
        }
        let scroller = ScrolledWindow(child: list)
        scroller.setPolicy(horizontal: GTK_POLICY_NEVER, vertical: GTK_POLICY_AUTOMATIC)
        scroller.propagateNaturalHeight = true
        gtk_scrolled_window_set_max_content_height(OpaquePointer(scroller.widgetPointer), 360)
        scroller.setSizeRequest(width: 240)
        popover.child = scroller
        gtk_widget_set_parent(popover.widgetPointer, anchor.widgetPointer)
        popover.popup()
        current = popover
    }
}
