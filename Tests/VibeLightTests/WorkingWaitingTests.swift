import Foundation
import Testing
@testable import VibeLight

@Test
func testRecentFileModificationIsWorking() {
    let now = Date()
    let status = SessionActivityStatus.determine(
        sessionStatus: "live",
        lastFileModification: now.addingTimeInterval(-2),
        lastJSONLEntryType: "assistant",
        now: now
    )
    #expect(status == .working)
}

@Test
func testQuietFileWithToolUseIsWorking() {
    let now = Date()
    let status = SessionActivityStatus.determine(
        sessionStatus: "live",
        lastFileModification: now.addingTimeInterval(-30),
        lastJSONLEntryType: "tool_use",
        now: now
    )
    #expect(status == .working)
}

@Test
func testQuietFileWithAssistantResponseIsWaiting() {
    let now = Date()
    let status = SessionActivityStatus.determine(
        sessionStatus: "live",
        lastFileModification: now.addingTimeInterval(-30),
        lastJSONLEntryType: "assistant",
        now: now
    )
    #expect(status == .waiting)
}

@Test
func testClosedSessionIsClosed() {
    let now = Date()
    let status = SessionActivityStatus.determine(
        sessionStatus: "closed",
        lastFileModification: now.addingTimeInterval(-3600),
        lastJSONLEntryType: "assistant",
        now: now
    )
    #expect(status == .closed)
}

@Test
func testUserMessageMeansWorking() {
    let now = Date()
    let status = SessionActivityStatus.determine(
        sessionStatus: "live",
        lastFileModification: now.addingTimeInterval(-10),
        lastJSONLEntryType: "user",
        now: now
    )
    #expect(status == .working)
}
