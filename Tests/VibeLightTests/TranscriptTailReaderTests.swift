import Foundation
import Testing
@testable import VibeLight

@Test
func testPreviewPrefersWaitingQuestionForHeadlineAndCompactsToTwoExchanges() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "claude_context_session_waiting",
            withExtension: "jsonl",
            subdirectory: "Fixtures"
        )
    )

    let preview = TranscriptTailReader.read(fileURL: fixtureURL, exchangeCount: 2)

    #expect(preview.headline == "Waiting: Which layout do you prefer?")
    #expect(preview.exchanges.count == 2)
    #expect(preview.exchanges[0].role == "user")
    #expect(preview.exchanges[1].role == "assistant")
}

@Test
func testPreviewPrefersErrorSummaryForHeadline() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "claude_context_session_error",
            withExtension: "jsonl",
            subdirectory: "Fixtures"
        )
    )

    let preview = TranscriptTailReader.read(fileURL: fixtureURL, exchangeCount: 2)

    #expect(preview.headline == "Error: swift build failed in SearchPanelController.swift")
    #expect(preview.exchanges.count == 2)
    #expect(preview.exchanges[1].isError)
}

@Test
func testPreviewFilesRemainRecentFirstAndCappedAtFive() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "claude_context_session_waiting",
            withExtension: "jsonl",
            subdirectory: "Fixtures"
        )
    )

    let preview = TranscriptTailReader.read(fileURL: fixtureURL, exchangeCount: 2)

    #expect(preview.files.count == 5)
    #expect(preview.files == [
        "/Users/me/project/Sources/VibeLight/Resources/Web/panel.css",
        "/Users/me/project/Sources/VibeLight/Resources/Web/panel.js",
        "/Users/me/project/Sources/VibeLight/Resources/Web/search.js",
        "/Users/me/project/Sources/VibeLight/UI/WebBridge.swift",
        "/Users/me/project/Sources/VibeLight/Parsers/TranscriptTailReader.swift",
    ])

    let json = TranscriptTailReader.previewToJSONString(preview)
    let data = try #require(json.data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["headline"] as? String == "Waiting: Which layout do you prefer?")
}

@Test
func testPreviewCompactionSkipsAssistantStatusChatter() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "claude_context_session_chatter",
            withExtension: "jsonl",
            subdirectory: "Fixtures"
        )
    )

    let preview = TranscriptTailReader.read(fileURL: fixtureURL, exchangeCount: 2)

    #expect(preview.exchanges.count == 2)
    #expect(preview.exchanges[0].role == "user")
    #expect(preview.exchanges[0].text == "Please make search results keyboard navigable.")
    #expect(preview.exchanges[1].role == "assistant")
    #expect(preview.exchanges[1].text == "I added arrow-key navigation and Enter-to-open behavior.")
}

@Test
func testPreviewExtractsCodexFilePathsWhenArgumentsAreJSONString() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "codex_context_session_arguments_string",
            withExtension: "jsonl",
            subdirectory: "Fixtures"
        )
    )

    let preview = TranscriptTailReader.read(fileURL: fixtureURL, exchangeCount: 2)

    #expect(preview.files == ["/Users/me/project/Sources/VibeLight/Parsers/TranscriptTailReader.swift"])
}

@Test
func testHeadlineSuppressesOlderWaitingWhenNewerStateIsAction() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "claude_context_session_state_newer_action_over_old_waiting",
            withExtension: "jsonl",
            subdirectory: "Fixtures"
        )
    )

    let preview = TranscriptTailReader.read(fileURL: fixtureURL, exchangeCount: 2)

    #expect(preview.headline == "Running targeted tests before final response.")
}

@Test
func testHeadlineSuppressesOlderErrorWhenNewerStateIsWaiting() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "claude_context_session_state_newer_waiting_over_old_error",
            withExtension: "jsonl",
            subdirectory: "Fixtures"
        )
    )

    let preview = TranscriptTailReader.read(fileURL: fixtureURL, exchangeCount: 2)

    #expect(preview.headline == "Waiting: Could you confirm I should keep the current fixture names?")
}

@Test
func testHeadlineSuppressesOlderActionWhenNewerStateIsError() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "claude_context_session_state_newer_error_over_old_action",
            withExtension: "jsonl",
            subdirectory: "Fixtures"
        )
    )

    let preview = TranscriptTailReader.read(fileURL: fixtureURL, exchangeCount: 2)

    #expect(preview.headline == "Error: command timed out during swift build")
}

@Test
func testHeadlineSuppressesOlderWaitingWhenNewerStateIsNeutralAssistantMessage() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "claude_context_session_state_neutral_newer_than_waiting",
            withExtension: "jsonl",
            subdirectory: "Fixtures"
        )
    )

    let preview = TranscriptTailReader.read(fileURL: fixtureURL, exchangeCount: 2)

    #expect(preview.headline == "Current task: Please proceed with the parser update and tests.")
}

@Test
func testHeadlineDoesNotTreatGenericCompletionUpdateAsWaiting() throws {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jsonl")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let lines = [
        #"{"type":"user","message":{"content":"Please add permission flow tests."}}"#,
        #"{"type":"assistant","message":{"content":"I am implementing permission checks and an approval flow for file edits. Let me know once tests pass."}}"#,
    ]
    try lines.joined(separator: "\n").write(to: tempURL, atomically: true, encoding: .utf8)

    let preview = TranscriptTailReader.read(fileURL: tempURL, exchangeCount: 2)
    #expect(preview.headline == "Current task: Please add permission flow tests.")
}

@Test
func testHeadlineDoesNotPromoteUserErrorWordingToErrorState() throws {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jsonl")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let lines = [
        #"{"type":"user","message":{"content":"Please improve parser diagnostics around transcript tails."}}"#,
        #"{"type":"assistant","message":{"content":"Running targeted parser checks now."}}"#,
        #"{"type":"user","message":{"content":"error: results still failed to load for me after retry."}}"#,
    ]
    try lines.joined(separator: "\n").write(to: tempURL, atomically: true, encoding: .utf8)

    let preview = TranscriptTailReader.read(fileURL: tempURL, exchangeCount: 2)

    #expect(preview.headline?.hasPrefix("Current task: ") == true)
    #expect(preview.headline?.hasPrefix("Error: ") == false)
    #expect(preview.exchanges.contains(where: { $0.role == "user" && $0.isError }) == false)
}

@Test
func testHeadlinePrefersAssistantActionEvenWhenMentioningEarlierFailure() throws {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jsonl")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let lines = [
        #"{"type":"user","message":{"content":"Please rerun tests for search keyboard behavior."}}"#,
        #"{"type":"assistant","message":{"content":"Running focused tests after earlier error: swift build failed."}}"#,
    ]
    try lines.joined(separator: "\n").write(to: tempURL, atomically: true, encoding: .utf8)

    let preview = TranscriptTailReader.read(fileURL: tempURL, exchangeCount: 2)

    #expect(preview.headline == "Running focused tests after earlier error: swift build failed.")
    #expect(preview.exchanges[1].role == "assistant")
    #expect(preview.exchanges[1].isError == false)
}

@Test
func testHeadlineForCodexResponseItemPrefersActionOverOlderError() throws {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jsonl")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let lines = [
        #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"API Error: previous run failed due to timeout"}]}}"#,
        #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Running a narrower retry now."}]}}"#,
    ]
    try lines.joined(separator: "\n").write(to: tempURL, atomically: true, encoding: .utf8)

    let preview = TranscriptTailReader.read(fileURL: tempURL, exchangeCount: 2)

    #expect(preview.headline == "Running a narrower retry now.")
}

@Test
func testPreviewExtractsCodexFilePathsWhenInputIsJSONString() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "codex_context_session_input_string",
            withExtension: "jsonl",
            subdirectory: "Fixtures"
        )
    )

    let preview = TranscriptTailReader.read(fileURL: fixtureURL, exchangeCount: 2)

    #expect(preview.files == ["/Users/me/project/Sources/VibeLight/Parsers/TranscriptTailReader.swift"])
}

@Test
func testHeadlineDoesNotPromoteResolvedAssistantErrorStatusToActiveError() throws {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jsonl")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let lines = [
        #"{"type":"user","message":{"content":"Please finish parser cleanup and keep the current behavior."}}"#,
        #"{"type":"assistant","message":{"content":"I fixed the error: swift build failed in SearchPanelController.swift. All checks are green now."}}"#,
    ]
    try lines.joined(separator: "\n").write(to: tempURL, atomically: true, encoding: .utf8)

    let preview = TranscriptTailReader.read(fileURL: tempURL, exchangeCount: 2)

    #expect(preview.headline?.hasPrefix("Error: ") == false)
    #expect(preview.headline == "Current task: Please finish parser cleanup and keep the current behavior.")
    #expect(preview.exchanges.count == 2)
    #expect(preview.exchanges[1].role == "assistant")
    #expect(preview.exchanges[1].isError == false)
}

@Test
func testReadBackfillsTailWindowWhenInitialChunkHasOnlyNoise() throws {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jsonl")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    var lines = [
        #"{"type":"user","message":{"content":"Please make search result navigation keyboard friendly."}}"#,
        #"{"type":"assistant","message":{"content":"I added keyboard navigation for arrow keys and Enter to open results."}}"#,
    ]

    for index in 0..<160 {
        lines.append("{\"type\":\"assistant\",\"message\":{\"content\":\"Running focused parser checks \(index).\"}}")
    }
    try lines.joined(separator: "\n").write(to: tempURL, atomically: true, encoding: .utf8)

    let preview = TranscriptTailReader.read(fileURL: tempURL, exchangeCount: 2)

    #expect(preview.exchanges.count == 2)
    #expect(preview.headline == "Current task: Please make search result navigation keyboard friendly.")
    if preview.exchanges.count == 2 {
        #expect(preview.exchanges[0].role == "user")
        #expect(preview.exchanges[0].text == "Please make search result navigation keyboard friendly.")
        #expect(preview.exchanges[1].role == "assistant")
        #expect(preview.exchanges[1].text == "I added keyboard navigation for arrow keys and Enter to open results.")
    }
}

@Test
func testHeadlinePrefersActiveErrorOverActionWhenSameAssistantLineContainsBoth() throws {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jsonl")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let lines = [
        #"{"type":"user","message":{"content":"Please rerun the focused build for the parser."}}"#,
        #"{"type":"assistant","message":{"content":"Running swift build now. Command timed out."}}"#,
    ]
    try lines.joined(separator: "\n").write(to: tempURL, atomically: true, encoding: .utf8)

    let preview = TranscriptTailReader.read(fileURL: tempURL, exchangeCount: 2)

    #expect(preview.headline == "Error: Running swift build now. Command timed out.")
    #expect(preview.exchanges.last?.isError == true)
}

@Test
func testHeadlinePrefersFreshFailureOverHistoricalErrorMention() throws {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jsonl")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let lines = [
        #"{"type":"user","message":{"content":"Please retry the parser build."}}"#,
        #"{"type":"assistant","message":{"content":"Running retry after earlier error. Command timed out again."}}"#,
    ]
    try lines.joined(separator: "\n").write(to: tempURL, atomically: true, encoding: .utf8)

    let preview = TranscriptTailReader.read(fileURL: tempURL, exchangeCount: 2)

    #expect(preview.headline == "Error: Running retry after earlier error. Command timed out again.")
    #expect(preview.exchanges.last?.isError == true)
}

@Test
func testHeadlinePrefersFreshBuildFailureAfterHistoricalErrorMention() throws {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jsonl")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let lines = [
        #"{"type":"user","message":{"content":"Please retry the parser build."}}"#,
        #"{"type":"assistant","message":{"content":"After fixing one compile issue, build failed in SearchPanelController.swift."}}"#,
    ]
    try lines.joined(separator: "\n").write(to: tempURL, atomically: true, encoding: .utf8)

    let preview = TranscriptTailReader.read(fileURL: tempURL, exchangeCount: 2)

    #expect(preview.headline == "Error: After fixing one compile issue, build failed in SearchPanelController.swift.")
    #expect(preview.exchanges.last?.isError == true)
}

@Test
func testExtractLastUserPromptBackfillsPastNoisyTail() throws {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jsonl")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    var lines = [
        #"{"type":"user","message":{"content":"Please make the preview headline smarter for active work."}}"#,
    ]
    for index in 0..<220 {
        lines.append("{\"type\":\"assistant\",\"message\":{\"content\":\"Running focused parser checks \(index).\"}}")
    }
    try lines.joined(separator: "\n").write(to: tempURL, atomically: true, encoding: .utf8)

    let prompt = TranscriptTailReader.extractLastUserPrompt(fileURL: tempURL)
    #expect(prompt == "Please make the preview headline smarter for active work.")
}

@Test
func testReadBackfillsForCurrentTaskHeadlineWhenRecentAssistantUpdatesFillExchangeQuota() throws {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jsonl")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    var lines = [
        #"{"type":"user","message":{"content":"Please keep the parser headline focused on the current task."}}"#,
    ]
    for index in 0..<180 {
        lines.append("{\"type\":\"assistant\",\"message\":{\"content\":\"I refined helper \(index) to keep the preview pipeline stable and readable for the panel refresh path.\"}}")
    }
    try lines.joined(separator: "\n").write(to: tempURL, atomically: true, encoding: .utf8)

    let preview = TranscriptTailReader.read(fileURL: tempURL, exchangeCount: 2)

    #expect(preview.exchanges.count == 2)
    #expect(preview.headline == "Current task: Please keep the parser headline focused on the current task.")
}
