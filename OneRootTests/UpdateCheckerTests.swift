import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking // Linux: HTTPURLResponse lives here
#endif
@testable import OneRoot

/// The update check (#36). No network: the request is faked.
final class UpdateCheckerTests: XCTestCase {
    private static func release(tag: String = "v2.3.0", draft: Bool = false, prerelease: Bool = false, assets: String = #"[{"name":"OneRoot-2.3.0.dmg","browser_download_url":"https://github.com/hillcraft-sc/OneRoot/releases/download/v2.3.0/OneRoot-2.3.0.dmg"}]"#) -> Data {
        Data("""
        {"tag_name":"\(tag)","name":"OneRoot 2.3.0","body":"**New**\\n- Merge folders","html_url":"https://github.com/hillcraft-sc/OneRoot/releases/tag/\(tag)",
         "draft":\(draft),"prerelease":\(prerelease),"published_at":"2026-11-02T12:00:00Z","assets":\(assets)}
        """.utf8)
    }

    /// The list GitHub answers with: one release inside an array.
    private static func list(_ releases: Data...) -> Data {
        var out = Data("[".utf8)
        for (index, release) in releases.enumerated() {
            if index > 0 { out.append(Data(",".utf8)) }
            out.append(release)
        }
        out.append(Data("]".utf8))
        return out
    }

    private func checker(_ data: Data, status: Int = 200, channel: UpdateChecker.Channel = .mac) -> UpdateChecker {
        var checker = UpdateChecker()
        checker.channel = channel
        checker.fetch = { request in
            XCTAssertEqual(request.url, UpdateChecker.releasesURL)
            return (data, HTTPURLResponse(url: UpdateChecker.releasesURL, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        return checker
    }

    func testEachChannelSeesOnlyItsOwnReleases() async throws {
        let mac = Self.release(tag: "v2.3.0")
        let linux = Self.release(tag: "linux-v1.0.0")
        let both = Self.list(linux, mac)
        let macOutcome = try await checker(both).check(currentVersion: "2.2.0")
        guard case .available(let macRelease) = macOutcome else { return XCTFail("\(macOutcome)") }
        XCTAssertEqual(macRelease.version, "2.3.0", "a Linux release never reaches the Mac")
        let linuxOutcome = try await checker(both, channel: .linux).check(currentVersion: "0.1.0")
        guard case .available(let linuxRelease) = linuxOutcome else { return XCTFail("\(linuxOutcome)") }
        XCTAssertEqual(linuxRelease.version, "1.0.0", "tag linux-v1.0.0 reads as 1.0.0")
        let same = try await checker(both, channel: .linux).check(currentVersion: "1.0.0")
        XCTAssertEqual(same, .upToDate(latest: "1.0.0"))
        do {
            _ = try await checker(Self.list(mac), channel: .linux).check(currentVersion: "0.1.0")
            XCTFail("expected noRelease")
        } catch {
            XCTAssertEqual(error as? UpdateCheckError, .noRelease)
        }
    }

    func testSkipsPreReleasesAndDraftsInTheList() async throws {
        let list = Self.list(Self.release(tag: "linux-v1.1.0", prerelease: true), Self.release(tag: "linux-v1.0.0"))
        let outcome = try await checker(list, channel: .linux).check(currentVersion: "0.1.0")
        guard case .available(let release) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(release.version, "1.0.0")
    }

    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("2.3.0", than: "2.2.0"))
        XCTAssertTrue(UpdateChecker.isNewer("2.10.0", than: "2.9.1"))
        XCTAssertTrue(UpdateChecker.isNewer("v3", than: "2.99"))
        XCTAssertFalse(UpdateChecker.isNewer("2.2", than: "2.2.0"))
        XCTAssertFalse(UpdateChecker.isNewer("2.2.0", than: "2.2.1"))
        XCTAssertFalse(UpdateChecker.isNewer("2.3.0-beta", than: "2.3.0"))
        XCTAssertTrue(UpdateChecker.isNewer("2.3.0", than: "2.3.0-beta"))
    }

    func testParsesTheRelease() throws {
        let release = try UpdateChecker.parse(Self.release())
        XCTAssertEqual(release.version, "2.3.0")
        XCTAssertEqual(release.title, "OneRoot 2.3.0")
        XCTAssertEqual(release.downloadURL?.lastPathComponent, "OneRoot-2.3.0.dmg")
        XCTAssertEqual(release.pageURL.absoluteString, "https://github.com/hillcraft-sc/OneRoot/releases/tag/v2.3.0")
        XCTAssertNotNil(release.publishedAt)
        XCTAssertTrue(release.notes.contains("Merge folders"))
    }

    func testDraftsPreReleasesAndJunkDontCount() {
        XCTAssertThrowsError(try UpdateChecker.parse(Self.release(draft: true)))
        XCTAssertThrowsError(try UpdateChecker.parse(Self.release(prerelease: true)))
        XCTAssertThrowsError(try UpdateChecker.parse(Data("<html>".utf8)))
        XCTAssertNil(try UpdateChecker.parse(Self.release(assets: "[]")).downloadURL, "no disk image: Download opens the release page")
    }

    func testCheckOutcomes() async throws {
        let newer = try await checker(Self.list(Self.release())).check(currentVersion: "2.2.0")
        guard case .available(let release) = newer else { return XCTFail("\(newer)") }
        XCTAssertEqual(release.version, "2.3.0")
        let same = try await checker(Self.list(Self.release())).check(currentVersion: "2.3.0")
        XCTAssertEqual(same, .upToDate(latest: "2.3.0"))
        do {
            _ = try await checker(Data("[]".utf8), status: 500).check(currentVersion: "2.2.0")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? UpdateCheckError, .badResponse(500))
        }
    }

    // MARK: UpdateCenter

    @MainActor
    func testAutomaticCheckRunsOncePerDayAndRespectsSkipAndTheSetting() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        var clock = Date(timeIntervalSince1970: 2_000_000_000)
        let calls = Counter()
        var checker = UpdateChecker()
        checker.fetch = { _ in
            await calls.increment()
            return (Self.list(Self.release()), HTTPURLResponse(url: UpdateChecker.releasesURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let center = UpdateCenter(checker: checker, defaults: defaults, currentVersion: "2.2.0", now: { clock })
        XCTAssertNil(center.checkAutomaticallyIfDue(), "off by default")
        defaults.set(true, forKey: UpdateCenter.checksAutomaticallyKey)
        await center.checkAutomaticallyIfDue()?.value
        XCTAssertEqual(center.presentRequestCount, 1)
        XCTAssertNil(center.checkAutomaticallyIfDue(), "not again the same day")

        guard case .available(let release) = center.state else { return XCTFail("\(center.state)") }
        center.skip(release)
        clock = clock.addingTimeInterval(25 * 60 * 60)
        await center.checkAutomaticallyIfDue()?.value
        XCTAssertEqual(center.presentRequestCount, 1, "a skipped version isn't shown again")

        defaults.set(false, forKey: UpdateCenter.checksAutomaticallyKey)
        clock = clock.addingTimeInterval(25 * 60 * 60)
        XCTAssertNil(center.checkAutomaticallyIfDue(), "off in Settings")
        let total = await calls.value
        XCTAssertEqual(total, 2)

        await center.checkNow().value
        guard case .available = center.state else { return XCTFail("Check for Updates always reports: \(center.state)") }
    }
}

private actor Counter {
    var value = 0
    func increment() { value += 1 }
}
