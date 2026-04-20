import Foundation
import Testing
@testable import Flare

@Suite("Search panel visible refresh")
struct SearchPanelControllerRefreshTests {
    @Test("history queries do not arm visible live refresh even when a live row is shown")
    func historyQueriesDoNotArmVisibleLiveRefresh() {
        let results = [makeResult(sessionId: "live-1", status: "live", lastActivityAt: 200)]

        #expect(
            SearchPanelController.shouldArmVisibleLiveRefresh(
                query: "needle",
                liveOnlySearch: false,
                results: results
            ) == false
        )
    }

    @Test("live rows can arm visible live refresh for live-only searches")
    func liveRowsCanArmVisibleLiveRefresh() {
        let results = [makeResult(sessionId: "live-1", status: "live", lastActivityAt: 200)]

        #expect(
            SearchPanelController.shouldArmVisibleLiveRefresh(
                query: "",
                liveOnlySearch: true,
                results: results
            )
        )
        #expect(
            SearchPanelController.shouldArmVisibleLiveRefresh(
                query: "build",
                liveOnlySearch: true,
                results: results
            )
        )
    }

    @Test("session index can refresh rows by session id without transcript search")
    func sessionIndexCanRefreshRowsBySessionID() throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("refresh-test-\(UUID().uuidString).sqlite3")
            .path
        let index = try SessionIndex(dbPath: dbPath)

        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let staleActivityAt = Date(timeIntervalSince1970: 1_700_000_100)
        let freshActivityAt = Date(timeIntervalSince1970: 1_700_000_500)

        try index.upsertSession(
            id: "live-1",
            tool: "codex",
            title: "Live Session",
            project: "/tmp/live",
            projectName: "live",
            gitBranch: "main",
            status: "live",
            startedAt: startedAt,
            pid: 42,
            tokenCount: 10,
            lastActivityAt: staleActivityAt
        )
        try index.insertTranscript(
            sessionId: "live-1",
            role: "assistant",
            content: "history only transcript needle",
            timestamp: staleActivityAt
        )
        try index.upsertSession(
            id: "live-1",
            tool: "codex",
            title: "Live Session Updated",
            project: "/tmp/live",
            projectName: "live",
            gitBranch: "main",
            status: "live",
            startedAt: startedAt,
            pid: 42,
            tokenCount: 11,
            lastActivityAt: freshActivityAt
        )

        let refreshed = try index.results(matchingSessionIDs: ["live-1"])

        #expect(refreshed.map(\.sessionId) == ["live-1"])
        #expect(refreshed.first?.title == "Live Session Updated")
        #expect(refreshed.first?.lastActivityAt == freshActivityAt)
        #expect(refreshed.first?.snippet == nil)
    }

    @MainActor
    @Test("search failures surface recovery guidance")
    func searchFailuresSurfaceRecoveryGuidance() throws {
        struct SearchFailure: LocalizedError {
            var errorDescription: String? { "database disk image is malformed" }
        }

        let controller = SearchPanelController()
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("search-failure-\(UUID().uuidString).sqlite3")
            .path
        controller.sessionIndex = try SessionIndex(dbPath: dbPath)
        controller.searchExecutorOverrideForTesting = { _, _ in
            throw SearchFailure()
        }

        var receivedMessage: String?
        controller.onSearchFailure = { message in
            receivedMessage = message
        }

        let bridge = WebBridge()
        controller.webBridge(bridge, didReceiveSearch: "broken index")

        #expect(receivedMessage?.localizedCaseInsensitiveContains("reindex sessions") == true)
        #expect(receivedMessage?.localizedCaseInsensitiveContains("malformed") == true)
    }

    private func makeResult(
        sessionId: String,
        status: String,
        lastActivityAt: TimeInterval
    ) -> SearchResult {
        let date = Date(timeIntervalSince1970: lastActivityAt)
        return SearchResult(
            sessionId: sessionId,
            tool: "codex",
            title: "Result \(sessionId)",
            project: "/tmp/\(sessionId)",
            projectName: sessionId,
            gitBranch: "main",
            status: status,
            startedAt: date.addingTimeInterval(-120),
            pid: status == "live" ? 42 : nil,
            tokenCount: 1,
            lastActivityAt: date,
            activityPreview: nil,
            activityStatus: status == "live" ? .working : .closed,
            snippet: nil
        )
    }
}
