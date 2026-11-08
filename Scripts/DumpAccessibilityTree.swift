#!/usr/bin/env swift
// Dumps a running app's accessibility tree: what VoiceOver is given. Read-only.
// Used for the accessibility audit (see the repo's accessibility issue) and
// to re-check fixes: run it before and after and compare.
//
//   swiftc -O -o /tmp/axdump Scripts/DumpAccessibilityTree.swift
//   open the app (or run its binary directly), then:
//   /tmp/axdump <pid> [maxDepth] [maxChildrenPerTable] ["press:Menu/Item" ...]
//
// Steps after the numbers run in order, the way a keyboard/VoiceOver user would:
//   "press:View/Advanced Search…"  choose a menu item (opens a window)
//   "select:Appearance"            select a sidebar row in a non-main window
//                                  (a Settings pane)
//   "selectmain:Documents"         select a row in the main window's file list
//   dump                           print the other windows' trees right now
//   nofinal                        skip the closing dump
// e.g.  /tmp/axdump <pid> 20 8 "press:OneRoot/Settings…" "select:SSH" dump nofinal
// Menu items only enable once the app is active and its window is focused.
//
// The terminal running this needs Accessibility permission (System Settings ▸
// Privacy & Security ▸ Accessibility). The output ends with a list of controls
// that have no label (no title, description, linked title element, or — for
// text fields — placeholder), which is the first thing to look at.
//
// Tip: when launching a debug build alongside your real app, pass
// `-com.oneroot.restoreSession NO` so it can't touch the saved session, and
// quit only the process you started.
import ApplicationServices
import AppKit

// Read-only dump of an app's accessibility tree: what VoiceOver is given.
// usage: ax <pid> [maxDepth] [maxChildren]
let pid = pid_t(CommandLine.arguments[1])!
let maxDepth = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 14
let maxChildren = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! : 10

func attr(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func text(_ element: AXUIElement, _ name: String) -> String {
    if let s = attr(element, name) as? String, !s.isEmpty { return s }
    if let n = attr(element, name) as? NSNumber { return n.stringValue }
    return ""
}

let controlRoles: Set<String> = ["AXButton", "AXMenuButton", "AXPopUpButton", "AXSlider", "AXCheckBox", "AXRadioButton", "AXTextField", "AXImage", "AXDisclosureTriangle", "AXIncrementor", "AXComboBox", "AXTabGroup", "AXScrollBar"]
var unlabeled: [String] = []
var counts: [String: Int] = [:]

func walk(_ element: AXUIElement, depth: Int, path: String) {
    let role = text(element, "AXRole"), subrole = text(element, "AXSubrole")
    let title = text(element, "AXTitle"), desc = text(element, "AXDescription"), value = text(element, "AXValue")
    let help = text(element, "AXHelp"), identifier = text(element, "AXIdentifier")
    let enabled = (attr(element, "AXEnabled") as? NSNumber)?.boolValue ?? true
    counts[role, default: 0] += 1

    var linked = ""
    if let titleElement = attr(element, "AXTitleUIElement") {
        let te = titleElement as! AXUIElement
        linked = !text(te, "AXValue").isEmpty ? text(te, "AXValue") : text(te, "AXTitle")
    }
    let placeholder = text(element, "AXPlaceholderValue")
    let label = !title.isEmpty ? title : (!desc.isEmpty ? desc : (!linked.isEmpty ? linked : ""))
    let shown = [role + (subrole.isEmpty ? "" : "/" + subrole), label.isEmpty ? "" : "“\(label)”", value.isEmpty || value == label ? "" : "value=\(value.prefix(40))", linked.isEmpty || !title.isEmpty || !desc.isEmpty ? "" : "(label via linked element)", placeholder.isEmpty ? "" : "placeholder=“\(placeholder)”", help.isEmpty ? "" : "help=“\(help.prefix(40))”", enabled ? "" : "(disabled)"].filter { !$0.isEmpty }.joined(separator: " ")
    print(String(repeating: "  ", count: depth) + shown)

    if controlRoles.contains(role), label.isEmpty, !(role == "AXTextField" && !placeholder.isEmpty) {
        // A text field's placeholder/value serves as its label to some degree; report it separately below.
        unlabeled.append("\(path) > \(role)\(subrole.isEmpty ? "" : "/" + subrole)\(help.isEmpty ? "" : "  [only a help tooltip: “\(help.prefix(50))”]")\(value.isEmpty ? "" : "  value=\(value.prefix(30))")")
    }
    guard depth < maxDepth, let children = attr(element, "AXChildren") as? [AXUIElement] else { return }
    // Large tables/outlines: sample the first rows only.
    let limited = role == "AXTable" || role == "AXOutline" || role == "AXList" || role == "AXRow" || role == "AXCollection" ? Array(children.prefix(maxChildren)) : children
    if limited.count < children.count { print(String(repeating: "  ", count: depth + 1) + "… (\(children.count - limited.count) more of \(children.count))") }
    for child in limited { walk(child, depth: depth + 1, path: path + (label.isEmpty ? "" : " > “\(label)”")) }
}

let app = AXUIElementCreateApplication(pid)

/// Steps run in the order given, the way a keyboard/VoiceOver user would:
///   press:Menu/Item   choose a menu item (opens a window)
///   select:Row text   select a sidebar row in a non-main window (a Settings pane)
///   dump              print every non-main window's tree as it is right now
///   nofinal           skip the closing dump of all windows
func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, "AXChildren") as? [AXUIElement]) ?? [] }
func allRows(_ e: AXUIElement, into rows: inout [AXUIElement]) {
    if text(e, "AXRole") == "AXRow" { rows.append(e); return }
    for c in children(e) { allRows(c, into: &rows) }
}
func otherWindows() -> [AXUIElement] {
    ((attr(app, "AXWindows") as? [AXUIElement]) ?? []).filter { text($0, "AXTitle") != "OneRoot" }
}
var skipFinal = false
for argument in CommandLine.arguments.dropFirst(4) {
    if argument == "nofinal" { skipFinal = true }
    else if argument == "dump" {
        for window in otherWindows() { print("--- window now: \(text(window, "AXTitle"))"); walk(window, depth: 0, path: "window") }
    } else if argument.hasPrefix("select:") {
        let wanted = String(argument.dropFirst(7))
        var rows: [AXUIElement] = []
        for window in otherWindows() { allRows(window, into: &rows) }
        func rowText(_ r: AXUIElement) -> String { children(r).flatMap { children($0) }.map { text($0, "AXValue") }.first { !$0.isEmpty } ?? "" }
        if let row = rows.first(where: { rowText($0) == wanted }) {
            print("selecting “\(wanted)”: \(AXUIElementSetAttributeValue(row, "AXSelected" as CFString, kCFBooleanTrue) == .success ? "ok" : "failed")")
            Thread.sleep(forTimeInterval: 1.5)
        } else { print("!! no row “\(wanted)”") }
    } else if argument.hasPrefix("selectmain:") {
        // Select a row in the main window's file list (or sidebar) by its name.
        let wanted = String(argument.dropFirst(11))
        var rows: [AXUIElement] = []
        for window in ((attr(app, "AXWindows") as? [AXUIElement]) ?? []) where text(window, "AXTitle") == "OneRoot" { allRows(window, into: &rows) }
        func firstText(_ r: AXUIElement) -> String { children(r).flatMap { children($0) }.map { text($0, "AXValue") }.first { !$0.isEmpty } ?? "" }
        if let row = rows.first(where: { firstText($0) == wanted && text($0, "AXSubrole") == "AXTableRow" }) {
            print("selecting “\(wanted)” in the list: \(AXUIElementSetAttributeValue(row, "AXSelected" as CFString, kCFBooleanTrue) == .success ? "ok" : "failed")")
            Thread.sleep(forTimeInterval: 2.0)
        } else { print("!! no list row “\(wanted)”") }
    } else if argument.hasPrefix("press:") {
        let parts = argument.dropFirst(6).split(separator: "/").map(String.init)
        guard parts.count == 2, let bar = children(app).first(where: { text($0, "AXRole") == "AXMenuBar" }),
              let menuBarItem = children(bar).first(where: { text($0, "AXTitle") == parts[0] }),
              let menu = children(menuBarItem).first,
              let item = children(menu).first(where: { text($0, "AXTitle") == parts[1] }) else {
            print("!! could not find menu item \(argument)"); continue
        }
        print("pressing \(parts[0]) ▸ \(parts[1]): \(AXUIElementPerformAction(item, kAXPressAction as CFString).rawValue == 0 ? "ok" : "failed")")
        Thread.sleep(forTimeInterval: 2.5)
    }
}
print("=== accessibility tree ===")
// Menus are a known quantity (210 items); skip them so the windows are readable.
if !skipFinal { for window in (attr(app, "AXWindows") as? [AXUIElement]) ?? [] { walk(window, depth: 0, path: "window") } }
print("\n=== controls with NO accessibility label (title or description) ===")
for line in unlabeled { print("• " + line) }
if unlabeled.isEmpty { print("(none)") }
print("\n=== element counts ===")
for (k, v) in counts.sorted(by: { $0.value > $1.value }) { print("\(k): \(v)") }
