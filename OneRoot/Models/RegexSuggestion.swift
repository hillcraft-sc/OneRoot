import Foundation

/// A named, common regex pattern offered as a starting point next to
/// Advanced Search's pattern field when it's in `.regex` mode — picking one
/// just fills the field with `pattern`, which stays a plain editable text
/// field afterward (see issue: "regex suggestions that are editable").
/// Patterns use ICU regex syntax (`NSRegularExpression`'s flavor), which is
/// what `SearchService` actually compiles them with.
struct RegexSuggestion: Identifiable {
    var id: String { name }
    let name: String
    let pattern: String

    static let all: [RegexSuggestion] = [
        RegexSuggestion(name: "Image files", pattern: #"\.(jpe?g|png|gif|bmp|tiff?|heic|webp)$"#),
        RegexSuggestion(name: "Video files", pattern: #"\.(mp4|mov|avi|mkv|m4v|wmv)$"#),
        RegexSuggestion(name: "Audio files", pattern: #"\.(mp3|wav|aac|flac|m4a|ogg)$"#),
        RegexSuggestion(name: "Archives", pattern: #"\.(zip|tar|gz|tgz|rar|7z)$"#),
        RegexSuggestion(name: "Documents", pattern: #"\.(pdf|docx?|xlsx?|pptx?|txt|rtf)$"#),
        RegexSuggestion(name: "Source code", pattern: #"\.(swift|py|js|ts|java|c|cpp|h|go|rs)$"#),
        RegexSuggestion(name: "Dotfiles / hidden", pattern: #"^\."#),
        RegexSuggestion(name: "Numbered backup (e.g. \"file (2)\")", pattern: #" \(\d+\)$"#),
        RegexSuggestion(name: "Date stamp (YYYY-MM-DD)", pattern: #"\d{4}-\d{2}-\d{2}"#),
        RegexSuggestion(name: "Email address", pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#),
        RegexSuggestion(name: "UUID", pattern: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#),
        RegexSuggestion(name: "IP address", pattern: #"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"#)
    ]
}
