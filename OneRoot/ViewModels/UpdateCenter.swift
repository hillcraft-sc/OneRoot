import Foundation
import Observation

/// Drives the update check (#36): automatically at most once a day when
/// Settings ▸ General ▸ "Check for updates automatically" is on (it's off
/// by default), and on demand from OneRoot ▸ Check for Updates…. Shows its
/// result in the Software Update window (`UpdateView`).
@MainActor
@Observable
final class UpdateCenter {
    static let shared = UpdateCenter()

    static let checksAutomaticallyKey = "com.oneroot.updates.checkAutomatically"
    static let lastCheckKey = "com.oneroot.updates.lastCheck"
    static let skippedVersionKey = "com.oneroot.updates.skippedVersion"
    static let automaticInterval: TimeInterval = 24 * 60 * 60

    enum State: Equatable {
        case idle
        case checking
        case upToDate(String)
        case available(ReleaseInfo)
        case failed(String)
    }

    private(set) var state: State = .idle
    /// Fires when an automatic check found something to show; a main
    /// window opens the Software Update window.
    private(set) var presentRequestCount = 0

    private let checker: UpdateChecker
    private let defaults: UserDefaults
    private let now: () -> Date
    let currentVersion: String

    init(
        checker: UpdateChecker = UpdateChecker(),
        defaults: UserDefaults = .standard,
        currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
        now: @escaping () -> Date = Date.init
    ) {
        self.checker = checker
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.now = now
    }

    var checksAutomatically: Bool {
        defaults.bool(forKey: Self.checksAutomaticallyKey)
    }

    /// Check for Updates…: always asks, and shows whatever the answer is.
    @discardableResult
    func checkNow() -> Task<Void, Never> {
        state = .checking
        return Task { await run(reportUpToDate: true) }
    }

    /// At launch: asks only if it's on and a day has passed, and only
    /// speaks up for a version you haven't skipped.
    @discardableResult
    func checkAutomaticallyIfDue() -> Task<Void, Never>? {
        guard checksAutomatically, state != .checking else { return nil }
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date, now().timeIntervalSince(last) < Self.automaticInterval {
            return nil
        }
        return Task {
            await run(reportUpToDate: false)
            if case .available(let release) = state, release.version != defaults.string(forKey: Self.skippedVersionKey) {
                presentRequestCount &+= 1
            }
        }
    }

    /// Skip This Version: no automatic reminder until a newer one.
    func skip(_ release: ReleaseInfo) {
        defaults.set(release.version, forKey: Self.skippedVersionKey)
        state = .idle
    }

    private func run(reportUpToDate: Bool) async {
        do {
            let outcome = try await checker.check(currentVersion: currentVersion)
            defaults.set(now(), forKey: Self.lastCheckKey)
            switch outcome {
            case .available(let release):
                state = .available(release)
            case .upToDate(let latest):
                state = reportUpToDate ? .upToDate(latest) : .idle
            }
        } catch {
            state = reportUpToDate ? .failed(error.localizedDescription) : .idle
        }
    }
}
