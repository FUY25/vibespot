import Foundation
import Testing
@testable import VibeLight

@Suite("Search panel controller preview merge")
struct SearchPanelControllerPreviewTests {
    @MainActor
    @Test("error dominance overrides runtime working waiting and transcript tail state")
    func errorDominanceOverridesRuntimeAndTailState() {
        let basePreview = PreviewData(
            state: .task,
            detail: "Tail detail",
            exchanges: [],
            files: []
        )
        let errorDetail = "API failed in runner"

        let workingResult = makeResult(
            tool: "codex",
            activityStatus: .working,
            activityPreview: ActivityPreview(text: "▶ Running swift build", kind: .tool),
            healthStatus: "error",
            healthDetail: errorDetail
        )
        let waitingResult = makeResult(
            tool: "claude",
            activityStatus: .waiting,
            activityPreview: ActivityPreview(text: "Which layout do you prefer?", kind: .assistant),
            healthStatus: "error",
            healthDetail: errorDetail
        )
        let closedResult = makeResult(
            tool: "claude",
            activityStatus: .closed,
            activityPreview: nil,
            healthStatus: "error",
            healthDetail: errorDetail
        )

        let mergedWorking = SearchPanelController.mergePreviewState(transcriptPreview: basePreview, with: workingResult)
        let mergedWaiting = SearchPanelController.mergePreviewState(transcriptPreview: basePreview, with: waitingResult)
        let mergedClosed = SearchPanelController.mergePreviewState(transcriptPreview: basePreview, with: closedResult)

        #expect(mergedWorking.state == .error)
        #expect(mergedWorking.detail == errorDetail)
        #expect(mergedWaiting.state == .error)
        #expect(mergedWaiting.detail == errorDetail)
        #expect(mergedClosed.state == .error)
        #expect(mergedClosed.detail == errorDetail)
    }

    @MainActor
    @Test("live Claude waiting prompt merges into Question state with prompt detail")
    func liveClaudeWaitingPromptMergesIntoQuestionState() {
        let transcriptPreview = PreviewData(
            state: .task,
            detail: "Refactor preview panel layout",
            exchanges: [],
            files: []
        )
        let result = makeResult(
            tool: "claude",
            activityStatus: .waiting,
            activityPreview: ActivityPreview(text: "Which layout do you prefer?", kind: .assistant)
        )

        let merged = SearchPanelController.mergePreviewState(
            transcriptPreview: transcriptPreview,
            with: result
        )

        #expect(merged.state == .question)
        #expect(merged.detail == "Which layout do you prefer?")
    }

    @MainActor
    @Test("live Codex tool activity merges into Working state with cleaned detail")
    func liveCodexToolActivityMergesIntoWorkingState() {
        let transcriptPreview = PreviewData(
            state: .task,
            detail: "Ship build pipeline",
            exchanges: [],
            files: []
        )
        let result = makeResult(
            tool: "codex",
            activityStatus: .working,
            activityPreview: ActivityPreview(text: "▶ Running swift build", kind: .tool)
        )

        let merged = SearchPanelController.mergePreviewState(
            transcriptPreview: transcriptPreview,
            with: result
        )

        #expect(merged.state == .working)
        #expect(merged.detail == "Running swift build")
    }

    @MainActor
    @Test("working state with nil or empty activity preview still uses tail detail fallback")
    func workingStateWithNilOrEmptyActivityPreviewUsesTailDetailFallback() {
        let transcriptPreview = PreviewData(
            state: .task,
            detail: "Tail fallback detail",
            exchanges: [],
            files: []
        )
        let nilPreviewResult = makeResult(
            tool: "codex",
            activityStatus: .working,
            activityPreview: nil
        )
        let emptyPreviewResult = makeResult(
            tool: "codex",
            activityStatus: .working,
            activityPreview: ActivityPreview(text: "   ", kind: .tool)
        )

        let mergedNil = SearchPanelController.mergePreviewState(
            transcriptPreview: transcriptPreview,
            with: nilPreviewResult
        )
        let mergedEmpty = SearchPanelController.mergePreviewState(
            transcriptPreview: transcriptPreview,
            with: emptyPreviewResult
        )

        #expect(mergedNil.state == .working)
        #expect(mergedNil.detail == "Tail fallback detail")
        #expect(mergedEmpty.state == .working)
        #expect(mergedEmpty.detail == "Tail fallback detail")
    }

    @MainActor
    @Test("waiting state with non-question detail remains Waiting")
    func waitingStateWithNonQuestionDetailRemainsWaiting() {
        let transcriptPreview = PreviewData(
            state: .task,
            detail: "Tail fallback detail",
            exchanges: [],
            files: []
        )
        let result = makeResult(
            tool: "claude",
            activityStatus: .waiting,
            activityPreview: ActivityPreview(text: "Awaiting your confirmation", kind: .assistant)
        )

        let merged = SearchPanelController.mergePreviewState(
            transcriptPreview: transcriptPreview,
            with: result
        )

        #expect(merged.state == .waiting)
        #expect(merged.detail == "Awaiting your confirmation")
    }

    private func makeResult(
        tool: String,
        activityStatus: SessionActivityStatus,
        activityPreview: ActivityPreview?,
        healthStatus: String = "ok",
        healthDetail: String = ""
    ) -> SearchResult {
        let now = Date(timeIntervalSince1970: 1_711_600_000)
        return SearchResult(
            sessionId: "sess-merge",
            tool: tool,
            title: "Merge Preview",
            project: "/tmp/merge",
            projectName: "merge",
            gitBranch: "",
            status: "live",
            startedAt: now,
            pid: 42,
            tokenCount: 100,
            lastActivityAt: now,
            activityPreview: activityPreview,
            activityStatus: activityStatus,
            snippet: nil,
            healthStatus: healthStatus,
            healthDetail: healthDetail
        )
    }
}
