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
}
