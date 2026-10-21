import Foundation
import Testing
@testable import Flowstate

struct FormattingTests {
    static let cases: [(seconds: TimeInterval, expected: String)] = [
        (0, "0s"),
        (42, "42s"),
        (60, "1m"),
        (3599, "59m"),
        (3600, "1h"),
        (8040, "2h 14m"),
    ]

    @Test(arguments: cases)
    func focusFormatted(seconds: TimeInterval, expected: String) {
        #expect(seconds.focusFormatted == expected)
    }

    @Test func clockFormatted() {
        #expect((129.0).clockFormatted == "02:09")
        #expect((3729.0).clockFormatted == "1:02:09")
    }
}
