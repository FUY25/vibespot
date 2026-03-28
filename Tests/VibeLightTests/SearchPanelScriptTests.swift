import Foundation
import JavaScriptCore
import Testing

@Suite("Search panel script")
struct SearchPanelScriptTests {
    @Test("fuzzy new-session helper behavior matches expected intent rules")
    func fuzzyNewSessionHelperBehavior() throws {
        let context = try makePanelScriptContext()

        #expect(try invokeBool("window.matchesCodexLaunchIntent('co')", in: context))
        #expect(try invokeBool("window.matchesCodexLaunchIntent('new cod')", in: context))
        #expect(!(try invokeBool("window.matchesCodexLaunchIntent('c')", in: context)))

        #expect(try invokeBool("window.matchesClaudeLaunchIntent('cl')", in: context))
        #expect(try invokeBool("window.matchesClaudeLaunchIntent('new cl')", in: context))
        #expect(!(try invokeBool("window.matchesClaudeLaunchIntent('c')", in: context)))

        #expect(try invokeBool("window.looksLikeNewSessionIntent('new cod')", in: context))
        #expect(try invokeBool("window.looksLikeNewSessionIntent('new cl')", in: context))
        #expect(!(try invokeBool("window.looksLikeNewSessionIntent('n')", in: context)))
        #expect(!(try invokeBool("window.looksLikeNewSessionIntent('ne')", in: context)))
        #expect(!(try invokeBool("window.looksLikeNewSessionIntent('c')", in: context)))
    }

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

private func makePanelScriptContext() throws -> JSContext {
    let context = try #require(JSContext())
    context.exceptionHandler = { _, exception in
        if let exception {
            Issue.record("JS exception: \(exception)")
        }
    }

    let bootstrap = #"""
    var window = {};
    window.webkit = { messageHandlers: { bridge: { postMessage: function() {} } } };
    function __makeEl() {
      return {
        value: '',
        innerHTML: '',
        textContent: '',
        className: '',
        style: {},
        children: [],
        selectionStart: 0,
        classList: { add: function(){}, remove: function(){}, toggle: function(){} },
        addEventListener: function(){},
        focus: function(){},
        blur: function(){},
        appendChild: function(child){ this.children.push(child); },
        querySelector: function(){ return null; },
        querySelectorAll: function(){ return []; },
        scrollIntoView: function(){},
        getBoundingClientRect: function(){ return { top: 0, bottom: 0, height: 0 }; }
      };
    }
    var __els = {};
    var document = {
      getElementById: function(id) {
        if (!__els[id]) __els[id] = __makeEl();
        return __els[id];
      },
      addEventListener: function(){},
      createElement: function(){ return __makeEl(); },
      body: { appendChild: function(){} }
    };
    function getComputedStyle() { return { fontFamily: 'monospace' }; }
    function setTimeout() { return 1; }
    function clearTimeout() {}
    """#

    _ = context.evaluateScript(bootstrap)
    _ = context.evaluateScript(try loadPanelScript())
    return context
}

private func invokeBool(_ script: String, in context: JSContext) throws -> Bool {
    let value = try #require(context.evaluateScript(script))
    return value.toBool()
}
