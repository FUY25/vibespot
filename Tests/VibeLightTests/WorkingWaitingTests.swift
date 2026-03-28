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
func testAssistantPermissionQuestionCountsAsWaiting() {
    let now = Date()
    let status = SessionActivityStatus.determine(
        sessionStatus: "live",
        lastFileModification: now.addingTimeInterval(-30),
        lastJSONLEntryType: "assistant",
        activityPreview: ActivityPreview(text: "Can you approve write access for this edit?", kind: .assistant),
        now: now
    )
    #expect(status == .waiting)
}

@Test
func testToolUseWithAssistantPromptPreviewFallsBackToWaiting() {
    let now = Date()
    let status = SessionActivityStatus.determine(
        sessionStatus: "live",
        lastFileModification: now.addingTimeInterval(-30),
        lastJSONLEntryType: "tool_use",
        activityPreview: ActivityPreview(text: "Could you confirm I should keep the current fixture names?", kind: .assistant),
        now: now
    )
    #expect(status == .waiting)
}

@Test
func testSessionMetricsPrefersAssistantInputPromptOverTrailingToolUse() throws {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try "tmp".write(to: tempURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let timestamp = Date()
    let messages = [
        ParsedMessage(
            role: "assistant",
            content: "Which layout do you prefer?",
            timestamp: timestamp,
            toolCalls: ["Read panel.css"],
            sessionId: nil,
            gitBranch: nil,
            cwd: nil
        )
    ]

    let metrics = IndexingHelpers.sessionMetrics(from: messages, filePath: tempURL.path)
    #expect(metrics.lastEntryType == "assistant")
    #expect(metrics.activityPreview?.kind == .assistant)
    #expect(metrics.activityPreview?.text.contains("Which layout do you prefer?") == true)
}

@Test
func testSessionMetricsDoesNotTreatPermissionImplementationUpdateAsWaiting() throws {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try "tmp".write(to: tempURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let timestamp = Date()
    let messages = [
        ParsedMessage(
            role: "assistant",
            content: "I am implementing permission checks and an approval flow for file edits. I will let you know once tests pass.",
            timestamp: timestamp,
            toolCalls: ["swift test --filter WorkingWaitingTests"],
            sessionId: nil,
            gitBranch: nil,
            cwd: nil
        )
    ]

    let metrics = IndexingHelpers.sessionMetrics(from: messages, filePath: tempURL.path)
    #expect(metrics.lastEntryType == "tool_use")
    #expect(metrics.activityPreview?.kind == .tool)
    #expect(metrics.activityPreview?.text.contains("Running") == true)
}

@Test
func testAssistantMessageNeedsUserInputScansAllQuestions() {
    let text = "I finished checking logs. Is the transcript parser output visible now? Which mode do you prefer?"
    #expect(IndexingHelpers.assistantMessageNeedsUserInput(text))
}

@Test
func testToolCallWithWriteFlagIsNotClassifiedAsFileEdit() {
    let preview = IndexingHelpers.previewForToolCall("Bash: npm run lint -- --write")
    #expect(preview.kind == .tool)
    #expect(preview.text.contains("Running"))
}

@Test
func testAssistantYesNoApprovalQuestionCountsAsWaiting() {
    #expect(IndexingHelpers.assistantMessageNeedsUserInput("Is this layout okay?"))
    #expect(IndexingHelpers.assistantMessageNeedsUserInput("Did that fix it?"))
}

@Test
func testDeclarativeGrantAccessStatusDoesNotCountAsWaiting() {
    let text = "I updated the grant access flow for the OAuth callback."
    #expect(IndexingHelpers.assistantMessageNeedsUserInput(text) == false)
}

@Test
func testDeclarativeAllowWriteStatusDoesNotCountAsWaiting() {
    let text = "I updated the allow write flow for patch application."
    #expect(IndexingHelpers.assistantMessageNeedsUserInput(text) == false)
}

@Test
func testPreviewForApplyPatchToolCallClassifiesAsFileEdit() {
    let preview = IndexingHelpers.previewForToolCall("apply_patch: Sources/VibeLight/UI/WebBridge.swift")
    #expect(preview.kind == .fileEdit)
    #expect(preview.text.contains("Editing"))
    #expect(preview.text.contains("apply_patch"))
}

@Test
func testPreviewForWriteToolCallClassifiesAsFileEdit() {
    let preview = IndexingHelpers.previewForToolCall("write: /tmp/WebBridge.swift")
    #expect(preview.kind == .fileEdit)
    #expect(preview.text.contains("Editing"))
    #expect(preview.text.contains("/tmp/WebBridge.swift"))
}

@Test
func testSessionMetricsTrailingApplyPatchToolUseStaysWorkingEvenWhenStale() throws {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try "tmp".write(to: tempURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let messages = [
        ParsedMessage(
            role: "assistant",
            content: "",
            timestamp: Date(),
            toolCalls: ["apply_patch: Sources/VibeLight/UI/WebBridge.swift"],
            sessionId: nil,
            gitBranch: nil,
            cwd: nil
        )
    ]

    let metrics = IndexingHelpers.sessionMetrics(from: messages, filePath: tempURL.path)
    #expect(metrics.lastEntryType == "tool_use")
    #expect(metrics.activityPreview?.kind == .fileEdit)
    #expect(metrics.activityPreview?.text.contains("Editing") == true)

    let status = SessionActivityStatus.determine(
        sessionStatus: "live",
        lastFileModification: Date().addingTimeInterval(-300),
        lastJSONLEntryType: metrics.lastEntryType,
        activityPreview: metrics.activityPreview,
        now: Date()
    )
    #expect(status == .working)
}

@Test
func testSessionMetricsTrailingWriteToolUseStaysWorkingWithoutAssistantPromptEvidence() throws {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try "tmp".write(to: tempURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let messages = [
        ParsedMessage(
            role: "assistant",
            content: "",
            timestamp: Date(),
            toolCalls: ["write: /tmp/WebBridge.swift"],
            sessionId: nil,
            gitBranch: nil,
            cwd: nil
        )
    ]

    let metrics = IndexingHelpers.sessionMetrics(from: messages, filePath: tempURL.path)
    #expect(metrics.lastEntryType == "tool_use")
    #expect(metrics.activityPreview?.kind == .fileEdit)
    #expect(metrics.activityPreview?.text.contains("write: /tmp/WebBridge.swift") == true)

    let status = SessionActivityStatus.determine(
        sessionStatus: "live",
        lastFileModification: Date().addingTimeInterval(-75),
        lastJSONLEntryType: metrics.lastEntryType,
        activityPreview: metrics.activityPreview,
        now: Date()
    )
    #expect(status == .working)
}
