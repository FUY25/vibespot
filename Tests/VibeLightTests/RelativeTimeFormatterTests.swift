import Foundation
import Testing
@testable import VibeLight

@Test
func testJustNow() {
    let now = Date()
    let result = RelativeTimeFormatter.string(from: now.addingTimeInterval(-30), relativeTo: now)
    #expect(result == "just now")
}

@Test
func testMinutesAgo() {
    let now = Date()
    let result = RelativeTimeFormatter.string(from: now.addingTimeInterval(-300), relativeTo: now)
    #expect(result == "5m ago")
}

@Test
func testHoursAgo() {
    let now = Date()
    let result = RelativeTimeFormatter.string(from: now.addingTimeInterval(-7_200), relativeTo: now)
    #expect(result == "2h ago")
}

@Test
func testYesterday() {
    let now = Date()
    let result = RelativeTimeFormatter.string(from: now.addingTimeInterval(-90_000), relativeTo: now)
    #expect(result == "yesterday")
}

@Test
func testDaysAgo() {
    let now = Date()
    let result = RelativeTimeFormatter.string(from: now.addingTimeInterval(-259_200), relativeTo: now)
    #expect(result == "3d ago")
}

@Test
func testOlderThanWeekShowsDate() {
    let now = Date()
    let result = RelativeTimeFormatter.string(from: now.addingTimeInterval(-1_000_000), relativeTo: now)
    #expect(!result.contains("ago"))
    #expect(!result.contains("yesterday"))
}
