import Foundation
import Observation

/// Visualize's state for one window: the report for the folder it's
/// showing, scanned in the background as you go. A new folder cancels the
/// scan in progress; folders already scanned this session show at once
/// (Rescan to refresh). The card asks for a folder only while it's on
/// screen, so nothing is scanned with Visualize hidden.
@MainActor
@Observable
final class VisualizeViewModel {
    enum Breakdown: String, CaseIterable, Identifiable {
        case folders, types, age, tags, cloud
        var id: Self { self }
        var title: String {
            switch self {
            case .folders: return "Folders"
            case .types: return "Types"
            case .age: return "Age"
            case .tags: return "Tags"
            case .cloud: return "Cloud"
            }
        }
    }

    private(set) var report: StorageReport?
    private(set) var isScanning = false
    private(set) var errorMessage: String?
    var breakdown: Breakdown = .folders
    /// The group whose largest files are listed (Types, Age, Tags, Cloud).
    var selectedGroup: String?

    private let scanner: StorageScanner
    private var scanTask: Task<Void, Never>?
    private(set) var folder: URL?

    /// Reports from this session, by folder — so going back is instant.
    private static var cache: [String: StorageReport] = [:]
    private static var cacheOrder: [String] = []
    private static let cacheLimit = 12

    init(scanner: StorageScanner = StorageScanner()) {
        self.scanner = scanner
    }

    /// Shows `folder`: from this session's scans if it has one, otherwise
    /// scans it (after `delay`, so arrowing through folders doesn't start a
    /// scan for each).
    func show(_ folder: URL?, delay: Duration = .milliseconds(400)) {
        guard folder?.standardizedFileURL != self.folder?.standardizedFileURL else { return }
        self.folder = folder
        selectedGroup = nil
        errorMessage = nil
        cancelScan()
        guard let folder else {
            report = nil
            return
        }
        if let cached = Self.cache[folder.standardizedFileURL.path] {
            report = cached
            return
        }
        report = nil
        startScan(folder, delay: delay)
    }

    func rescan() {
        guard let folder else { return }
        Self.cache[folder.standardizedFileURL.path] = nil
        cancelScan()
        errorMessage = nil
        startScan(folder, delay: .zero)
    }

    /// Stops the scan, keeping what it found so far.
    func stop() {
        cancelScan()
    }

    private func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    private func startScan(_ folder: URL, delay: Duration) {
        isScanning = true
        scanTask = Task { [weak self, scanner] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            do {
                for try await partial in scanner.scan(folder) {
                    guard !Task.isCancelled else { return }
                    self?.report = partial
                }
                guard !Task.isCancelled, let self else { return }
                self.isScanning = false
                if let report = self.report, report.isComplete { Self.remember(report) }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isScanning = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private static func remember(_ report: StorageReport) {
        let key = report.root.standardizedFileURL.path
        cache[key] = report
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        while cacheOrder.count > cacheLimit {
            cache[cacheOrder.removeFirst()] = nil
        }
    }

    /// For tests.
    static func clearCache() {
        cache = [:]
        cacheOrder = []
    }
}
