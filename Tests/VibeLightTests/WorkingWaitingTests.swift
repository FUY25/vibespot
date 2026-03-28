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
        activityPreview: ActivityPreview(text: "Running bash command", kind: .tool),
        now: now
    )
    #expect(status == .working)
}

@Test
func testQuietFileEditPromptToolUseIsWaiting() {
    let now = Date()
    let status = SessionActivityStatus.determine(
        sessionStatus: "live",
        lastFileModification: now.addingTimeInterval(-30),
        lastJSONLEntryType: "tool_use",
        activityPreview: ActivityPreview(text: "Claude needs permission to edit WebBridge.swift", kind: .fileEdit),
        now: now
    )
    #expect(status == .waiting)
}

@Test
func testQuietFileWithAssistantResponseIsWaiting() {
    let now = Date()
    let status = SessionActivityStatus.determine(
        sessionStatus: "live",
        lastFileModification: now.addingTimeInterval(-30),
        lastJSONLEntryType: "assistant",
        activityPreview: ActivityPreview(text: "Waiting for user", kind: .assistant),
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
        activityPreview: nil,
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
        activityPreview: nil,
        now: now
    )
    #expect(status == .working)
}

@Test
func testRecentFileEditToolUseStillCountsAsWorking() {
    let now = Date()
    let status = SessionActivityStatus.determine(
        sessionStatus: "live",
        lastFileModification: now.addingTimeInterval(-2),
        lastJSONLEntryType: "tool_use",
        activityPreview: ActivityPreview(text: "Requesting edit access", kind: .fileEdit),
        now: now
    )
    #expect(status == .working)
}
