import Adwaita
import CAdwaita
import Foundation

/// Ctrl+?: the shortcut reference as a quick popover under the path bar (the
/// Mac's shortcut quick view), with a button on to the full Help topic.
@MainActor
enum ShortcutsPopover {
    private static var current: Popover?

    static func show(from anchor: Widget, openHelp: @escaping @MainActor () -> Void) {
        if let old = current { old.popdown(); old.unparent(); current = nil }
        let popover = Popover()
        popover.hasArrow = false
        popover.autohide = true
        popover.position = GTK_POS_BOTTOM

        let content = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 2)
        content.marginStart = 14
        content.marginEnd = 14
        content.marginTop = 10
        content.marginBottom = 10
        for section in LinuxShortcuts.sections {
            let heading = Label(section.title)
            heading.xalign = 0
            heading.addCSSClass("heading")
            heading.marginTop = 8
            content.append(heading)
            for (keys, what) in section.shortcuts {
                let row = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 12)
                let key = Label(keys)
                key.xalign = 0
                key.widthChars = 22
                key.addCSSClass("monospace")
                key.addCSSClass("caption")
                let text = Label(what)
                text.xalign = 0
                text.wrap = true
                text.hexpand = true
                text.addCSSClass("caption")
                row.append(key)
                row.append(text)
                row.setAccessibleLabel("\(keys): \(what)")
                content.append(row)
            }
        }
        let scroller = ScrolledWindow(child: content)
        scroller.setPolicy(horizontal: GTK_POLICY_NEVER, vertical: GTK_POLICY_AUTOMATIC)
        scroller.setSizeRequest(width: 560, height: 420)

        let more = Button(label: "Open Help\u{2026}")
        more.addCSSClass(.flat)
        more.halign = GTK_ALIGN_END
        more.marginEnd = 8
        more.marginBottom = 6
        more.onClicked { [weak popover] in
            popover?.popdown()
            openHelp()
        }
        let box = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
        box.append(scroller)
        box.append(more)
        popover.child = box
        gtk_widget_set_parent(popover.widgetPointer, anchor.widgetPointer)
        popover.popup()
        current = popover
    }
}
