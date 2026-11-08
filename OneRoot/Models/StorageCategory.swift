import Foundation

/// Kinds of file, in a fixed order — the order their colors are assigned
/// in, whatever their sizes.
enum StorageCategory: String, CaseIterable, Identifiable, Codable {
    case images, video, audio, documents, archives, apps, code, other

    var id: Self { self }

    var title: String {
        switch self {
        case .images: return "Images"
        case .video: return "Video"
        case .audio: return "Audio"
        case .documents: return "Documents"
        case .archives: return "Archives"
        case .apps: return "Apps"
        case .code: return "Code"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .images: return "photo"
        case .video: return "film"
        case .audio: return "music.note"
        case .documents: return "doc.text"
        case .archives: return "archivebox"
        case .apps: return "app"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .other: return "questionmark.square.dashed"
        }
    }

    /// The category of common file extensions, without asking the system —
    /// for platforms without UTType (Linux, until its MIME lookup).
    /// The category of a MIME type ("image/png" → Images), or `nil` when
    /// the type alone doesn't say.
    static func of(mimeType type: String) -> StorageCategory? {
        let top = type.split(separator: "/").first.map(String.init) ?? ""
        switch top {
        case "image": return .images
        case "video": return .video
        case "audio": return .audio
        default: break
        }
        let archives = ["zip", "x-tar", "gzip", "x-7z-compressed", "x-rar", "vnd.rar", "x-bzip2", "x-xz", "zstd", "x-iso9660-image", "x-compressed-tar", "x-apple-diskimage"]
        if archives.contains(where: { type == "application/" + $0 }) { return .archives }
        if type == "application/x-executable" || type == "application/vnd.flatpak" || type == "application/x-desktop" || type == "application/vnd.appimage" { return .apps }
        if type == "application/pdf" || type.hasPrefix("application/vnd.oasis.opendocument") || type.hasPrefix("application/vnd.openxmlformats")
            || type == "application/msword" || type == "text/plain" || type == "text/markdown" || type == "application/rtf" {
            return .documents
        }
        if type.hasPrefix("text/x-") || type == "application/json" || type == "application/xml" || type == "text/html"
            || type == "application/javascript" || type == "application/x-shellscript" || type == "text/css" {
            return .code
        }
        return nil
    }

    static func common(forExtension fileExtension: String) -> StorageCategory {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp", "svg", "raw", "cr2", "nef", "dng", "avif", "ico":
            return .images
        case "mp4", "mov", "m4v", "mkv", "avi", "webm", "wmv", "flv", "mpg", "mpeg", "3gp":
            return .video
        case "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "aiff", "aif", "alac", "wma":
            return .audio
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "zst", "dmg", "iso", "img":
            return .archives
        case "app", "exe", "msi", "deb", "rpm", "appimage", "flatpak", "pkg", "apk":
            return .apps
        case "swift", "c", "h", "cpp", "hpp", "m", "py", "js", "ts", "tsx", "jsx", "rs", "go", "java", "kt", "rb", "php",
             "sh", "zsh", "bash", "json", "xml", "yml", "yaml", "toml", "html", "css", "sql", "lua", "pl", "cs":
            return .code
        case "pdf", "txt", "md", "rtf", "doc", "docx", "odt", "pages", "xls", "xlsx", "ods", "numbers", "csv",
             "ppt", "pptx", "odp", "key", "epub":
            return .documents
        default:
            return .other
        }
    }
}
