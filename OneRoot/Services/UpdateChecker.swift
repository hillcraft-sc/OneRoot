import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // Linux: URLSession lives here
#endif

/// A published OneRoot release.
struct ReleaseInfo: Equatable, Sendable {
    /// "2.3.0" — the tag without its "v".
    let version: String
    let title: String
    /// The release notes (Markdown).
    let notes: String
    /// The release's page on GitHub.
    let pageURL: URL
    /// The disk image, when the release has one.
    let downloadURL: URL?
    let publishedAt: Date?
}

enum UpdateCheckError: LocalizedError, Equatable {
    case badResponse(Int)
    case unreadable
    case noRelease

    var errorDescription: String? {
        switch self {
        case .badResponse(let status): return "The update server answered with an error (\(status))."
        case .unreadable: return "The update server\u{2019}s answer couldn\u{2019}t be read."
        case .noRelease: return "No released version was found."
        }
    }
}

/// #36: asks GitHub for OneRoot's latest release (the public releases
/// repo, github.com/hillcraft-sc/OneRoot) and compares it with this copy.
/// One plain HTTPS request — no identifiers, no analytics — and nothing is
/// downloaded or installed: an available update is shown with its notes
/// and a link. UI-agnostic; `UpdateCenter` drives it.
struct UpdateChecker {
    /// The releases repo holds both products: the Mac's are tagged `v2.3.0`,
    /// Linux's `linux-v1.0.0`. Each asks only about its own.
    enum Channel: Sendable {
        case mac, linux

        func includes(tag: String) -> Bool {
            switch self {
            case .mac: return !tag.hasPrefix("linux-")
            case .linux: return tag.hasPrefix("linux-v")
            }
        }
    }

    var channel: Channel = .mac

    /// Newest first; drafts are not listed for anonymous requests.
    static let releasesURL = URL(string: "https://api.github.com/repos/hillcraft-sc/OneRoot/releases?per_page=30")
        ?? URL(fileURLWithPath: "/")


    /// The request, injectable for tests.
    var fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
        try await URLSession.shared.data(for: request)
    }

    enum Outcome: Equatable, Sendable {
        case upToDate(latest: String)
        case available(ReleaseInfo)
    }

    func check(currentVersion: String) async throws -> Outcome {
        var request = URLRequest(url: Self.releasesURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("OneRoot/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await fetch(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw http.statusCode == 404 ? UpdateCheckError.noRelease : UpdateCheckError.badResponse(http.statusCode)
        }
        let release = try Self.parseList(data, channel: channel)
        return Self.isNewer(release.version, than: currentVersion) ? .available(release) : .upToDate(latest: release.version)
    }

    /// The newest published release of `channel` in GitHub's release list.
    static func parseList(_ data: Data, channel: Channel) throws -> ReleaseInfo {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [Any] else { throw UpdateCheckError.unreadable }
        for item in items {
            guard let object = item as? [String: Any], let tag = object["tag_name"] as? String, channel.includes(tag: tag),
                  let single = try? JSONSerialization.data(withJSONObject: object),
                  let release = try? parse(single) else { continue }
            return release
        }
        throw UpdateCheckError.noRelease
    }

    /// Reads GitHub's "latest release" answer. Drafts and pre-releases
    /// don't count.
    static func parse(_ data: Data) throws -> ReleaseInfo {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        struct Release: Decodable {
            let tag_name: String
            let name: String?
            let body: String?
            let html_url: URL
            let draft: Bool?
            let prerelease: Bool?
            let published_at: Date?
            let assets: [Asset]?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let release = try? decoder.decode(Release.self, from: data) else { throw UpdateCheckError.unreadable }
        guard release.draft != true, release.prerelease != true else { throw UpdateCheckError.noRelease }
        let bare = release.tag_name.hasPrefix("linux-") ? String(release.tag_name.dropFirst("linux-".count)) : release.tag_name
        let version = bare.hasPrefix("v") ? String(bare.dropFirst()) : bare
        let disk = release.assets?.first { $0.name.lowercased().hasSuffix(".dmg") }
        return ReleaseInfo(
            version: version,
            title: release.name ?? "OneRoot \(version)",
            notes: release.body ?? "",
            pageURL: release.html_url,
            downloadURL: disk?.browser_download_url,
            publishedAt: release.published_at
        )
    }

    /// "2.10.0" is newer than "2.9.1"; "2.2" equals "2.2.0". Anything
    /// after a "-" (2.3.0-beta) makes it older than the plain version.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> (numbers: [Int], isPre: Bool) {
            let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
            let split = trimmed.split(separator: "-", maxSplits: 1)
            let numbers = (split.first ?? "").split(separator: ".").map { Int($0) ?? 0 }
            return (numbers, split.count > 1)
        }
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.numbers.count, b.numbers.count) {
            let x = index < a.numbers.count ? a.numbers[index] : 0
            let y = index < b.numbers.count ? b.numbers[index] : 0
            if x != y { return x > y }
        }
        return !a.isPre && b.isPre
    }
}
