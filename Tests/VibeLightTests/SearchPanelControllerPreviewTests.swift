import Foundation
import Testing
@testable import VibeLight

@Suite("Search panel controller preview merge")
struct SearchPanelControllerPreviewTests {
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

    private func makeResult(
        tool: String,
        activityStatus: SessionActivityStatus,
        activityPreview: ActivityPreview?
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
            healthStatus: "ok",
            healthDetail: ""
        )
    }
}
