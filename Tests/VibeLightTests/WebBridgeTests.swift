// Tests/VibeLightTests/WebBridgeTests.swift
import Testing
import Foundation
@testable import VibeLight

@Suite("WebBridge message parsing")
struct WebBridgeTests {
    @Test("parses search message")
    func parseSearchMessage() {
        let body: [String: Any] = ["type": "search", "query": "hello"]
        let message = WebBridge.Message.parse(body)
        #expect(message == .search(query: "hello"))
    }

    @Test("parses select message")
    func parseSelectMessage() {
        let body: [String: Any] = ["type": "select", "sessionId": "abc-123", "status": "live", "tool": "claude"]
        let message = WebBridge.Message.parse(body)
        #expect(message == .select(sessionId: "abc-123", status: "live", tool: "claude"))
    }

    @Test("parses escape message")
    func parseEscapeMessage() {
        let body: [String: Any] = ["type": "escape"]
        let message = WebBridge.Message.parse(body)
        #expect(message == .escape)
    }

    @Test("parses resize message")
    func parseResizeMessage() {
        let body: [String: Any] = ["type": "resize", "height": 400.0]
        let message = WebBridge.Message.parse(body)
        #expect(message == .resize(height: 400.0))
    }

    @Test("parses resize message when height is Int")
    func parseResizeMessageIntHeight() {
        let body: [String: Any] = ["type": "resize", "height": 400]
        let message = WebBridge.Message.parse(body)
        #expect(message == .resize(height: 400.0))
    }

    @Test("returns nil for unknown message type")
    func unknownMessage() {
        let body: [String: Any] = ["type": "unknown"]
        let message = WebBridge.Message.parse(body)
        #expect(message == nil)
    }

    @Test("returns nil for search message missing query")
    func parseSearchMessageMissingQuery() {
        let body: [String: Any] = ["type": "search"]
        let message = WebBridge.Message.parse(body)
        #expect(message == nil)
    }

    @Test("returns nil for select message missing sessionId")
    func parseSelectMessageMissingSessionID() {
        let body: [String: Any] = ["type": "select", "status": "live", "tool": "claude"]
        let message = WebBridge.Message.parse(body)
        #expect(message == nil)
    }

    @Test("returns nil for select message with empty sessionId")
    func parseSelectMessageEmptySessionID() {
        let body: [String: Any] = ["type": "select", "sessionId": "", "status": "live", "tool": "claude"]
        let message = WebBridge.Message.parse(body)
        #expect(message == nil)
    }

    @Test("parses preview message")
    func parsePreviewMessage() {
        let body: [String: Any] = ["type": "preview", "sessionId": "sess-1"]
        let message = WebBridge.Message.parse(body)
        #expect(message == .preview(sessionId: "sess-1"))
    }

    @Test("parses previewVisible message")
    func parsePreviewVisibleMessage() {
        let bodyTrue: [String: Any] = ["type": "previewVisible", "visible": true]
        #expect(WebBridge.Message.parse(bodyTrue) == .previewVisible(visible: true))

        let bodyFalse: [String: Any] = ["type": "previewVisible", "visible": false]
        #expect(WebBridge.Message.parse(bodyFalse) == .previewVisible(visible: false))
    }

    @Test("returns nil for previewVisible missing visible field")
    func parsePreviewVisibleMissingField() {
        let body: [String: Any] = ["type": "previewVisible"]
        #expect(WebBridge.Message.parse(body) == nil)
    }

    @MainActor
    @Test("resultToJSON includes health fields and startedAt")
    func resultToJSONIncludesHealthAndStartedAt() {
        let startedAt = Date(timeIntervalSince1970: 1_711_600_000)
        let result = SearchResult(
            sessionId: "h-1",
            tool: "claude",
            title: "test",
            project: "/tmp",
            projectName: "test",
            gitBranch: "",
            status: "live",
            startedAt: startedAt,
            pid: 1,
            tokenCount: 100,
            lastActivityAt: Date(timeIntervalSince1970: 1_711_600_100),
            activityPreview: nil,
            activityStatus: .working,
            snippet: nil,
            healthStatus: "error",
            healthDetail: "API 400"
        )

        let json = WebBridge.resultToJSON(result)
        #expect(json["healthStatus"] as? String == "error")
        #expect(json["healthDetail"] as? String == "API 400")
        #expect(json["startedAt"] as? String == ISO8601DateFormatter().string(from: startedAt))
    }
}
