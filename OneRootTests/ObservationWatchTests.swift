import Observation
import XCTest
@testable import OneRoot

@Observable
private final class Counter {
    var value = 0
    var other = ""
}

/// The Combine-`sink` replacement (#80); runs on macOS and Linux.
@MainActor
final class ObservationWatchTests: XCTestCase {
    private func settle() async {
        for _ in 0..<5 { await Task.yield(); try? await Task.sleep(for: .milliseconds(5)) }
    }

    func testEmitsTheInitialValueThenEachChange() async {
        let counter = Counter()
        var seen: [Int] = []
        let watch = ObservationWatch.watch({ counter.value }) { seen.append($0) }
        counter.value = 1
        await settle()
        counter.value = 2
        await settle()
        XCTAssertEqual(seen, [0, 1, 2])
        _ = watch
    }

    func testBurstsCoalesceAndUnrelatedPropertiesDontFire() async {
        let counter = Counter()
        var seen: [Int] = []
        let watch = ObservationWatch.watch({ counter.value }, emitsInitialValue: false) { seen.append($0) }
        counter.other = "x"
        await settle()
        counter.value = 1
        counter.value = 2
        counter.value = 3
        await settle()
        XCTAssertEqual(seen, [3], "one call per burst, with the final value")
        _ = watch
    }

    func testCancelAndReleaseStopWatching() async {
        let counter = Counter()
        var seen: [Int] = []
        var watch: ObservationWatch? = ObservationWatch.watch({ counter.value }, emitsInitialValue: false) { seen.append($0) }
        watch?.cancel()
        counter.value = 1
        await settle()
        XCTAssertEqual(seen, [])
        watch = ObservationWatch.watch({ counter.value }, emitsInitialValue: false) { seen.append($0) }
        watch = nil
        counter.value = 2
        await settle()
        XCTAssertEqual(seen, [])
    }
}
