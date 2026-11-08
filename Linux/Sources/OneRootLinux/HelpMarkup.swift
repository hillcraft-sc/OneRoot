import Foundation

/// Help text is written with `**bold**` and `` `code` `` (as on the Mac);
/// GTK labels want Pango markup. Everything else is escaped.
enum HelpMarkup {
    static func pango(_ text: String) -> String {
        var out = ""
        var bold = false
        var code = false
        var index = text.startIndex
        while index < text.endIndex {
            let rest = text[index...]
            if rest.hasPrefix("**") {
                out += bold ? "</b>" : "<b>"
                bold.toggle()
                index = text.index(index, offsetBy: 2)
                continue
            }
            let character = text[index]
            if character == "`" {
                out += code ? "</tt>" : "<tt>"
                code.toggle()
            } else {
                switch character {
                case "&": out += "&amp;"
                case "<": out += "&lt;"
                case ">": out += "&gt;"
                default: out.append(character)
                }
            }
            index = text.index(after: index)
        }
        if code { out += "</tt>" }
        if bold { out += "</b>" }
        return out
    }
}
