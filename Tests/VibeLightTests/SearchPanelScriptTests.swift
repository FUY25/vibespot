import Foundation
import Testing

@Suite("Search panel script")
struct SearchPanelScriptTests {
    @Test("Tab key delegates to handleTab instead of accepting ghost suggestions")
    func tabKeyDelegatesToHandleTab() throws {
        let script = try loadPanelScript()

        let tabCaseRange = try #require(script.range(of: "case 'Tab':"))
        let arrowRightRange = try #require(script.range(of: "case 'ArrowRight':"))
        let tabCaseBody = String(script[tabCaseRange.lowerBound..<arrowRightRange.lowerBound])

        #expect(tabCaseBody.contains("handleTab();"))
        #expect(!tabCaseBody.contains("acceptGhostSuggestion()"))
        #expect(!tabCaseBody.contains("drillIntoSelectedHistory()"))
    }

    @Test("handleTab only toggles mode for active search queries")
    func handleTabOnlyTogglesModeForActiveQueries() throws {
        let script = try loadPanelScript()
        let handleTabRange = try #require(script.range(of: "window.handleTab = function() {"))
        let initRange = try #require(script.range(of: "// --- Init ---"))
        let handleTabBody = String(script[handleTabRange.lowerBound..<initRange.lowerBound])

        #expect(handleTabBody.contains("if (searchInput.value.trim() && bridge)"))
        #expect(handleTabBody.contains("bridge.postMessage({ type: 'toggleMode' });"))
        #expect(!handleTabBody.contains("acceptGhostSuggestion"))
        #expect(!handleTabBody.contains("drillIntoSelectedHistory"))
    }
}

private func loadPanelScript() throws -> String {
    let fileURL = URL(fileURLWithPath: #filePath)
    let packageRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let scriptURL = packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("VibeLight")
        .appendingPathComponent("Resources")
        .appendingPathComponent("Web")
        .appendingPathComponent("panel.js")

    return try String(contentsOf: scriptURL, encoding: .utf8)
}
