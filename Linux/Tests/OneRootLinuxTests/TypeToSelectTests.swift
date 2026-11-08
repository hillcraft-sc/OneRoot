import Foundation
import Testing
@testable import OneRootLinux

struct TypeToSelectTests {
    let names = ["alpha", "Apple", "banana", "berry", "cherry"]

    @Test func letters_within_the_timeout_build_a_prefix() {
        var typing = TypeToSelect()
        let start = Date()
        _ = typing.type("b", at: start)
        #expect(typing.type("e", at: start.addingTimeInterval(0.5)) == "be")
    }

    @Test func a_pause_starts_over() {
        var typing = TypeToSelect()
        let start = Date()
        _ = typing.type("b", at: start)
        #expect(typing.type("c", at: start.addingTimeInterval(2)) == "c")
    }

    @Test func first_match_ignores_case() {
        #expect(TypeToSelect.match(prefix: "ap", in: names, current: nil) == 1)
        #expect(TypeToSelect.match(prefix: "z", in: names, current: nil) == nil)
    }

    @Test func a_current_match_that_still_fits_stays() {
        #expect(TypeToSelect.match(prefix: "b", in: names, current: 3) == 3)
        #expect(TypeToSelect.match(prefix: "be", in: names, current: 2) == 3)
    }

    @Test func repeating_a_letter_cycles() {
        #expect(TypeToSelect.match(prefix: "aa", in: names, current: 0) == 1)
        #expect(TypeToSelect.match(prefix: "aa", in: names, current: 1) == 0)
    }

    @Test func empty_input_matches_nothing() {
        #expect(TypeToSelect.match(prefix: "", in: names, current: nil) == nil)
        #expect(TypeToSelect.match(prefix: "a", in: [], current: nil) == nil)
    }
}
