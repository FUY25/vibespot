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

    @Test("result rows show full path with model context metadata")
    func resultRowsShowFullPathWithModelContextMetadata() throws {
        let context = try makePanelScriptContext()
        let payload = #"""
        [{
          "sessionId": "sess-1",
          "tool": "claude",
          "title": "Ship telemetry",
          "project": "/Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation",
          "projectName": "vibelight",
          "gitBranch": "main",
          "status": "live",
          "startedAt": "2026-03-28T09:30:00Z",
          "tokenCount": 84800,
          "lastActivityAt": "2026-03-28T09:42:00Z",
          "activityStatus": "waiting",
          "relativeTime": "2m ago",
          "healthStatus": "ok",
          "healthDetail": "",
          "effectiveModel": "claude-sonnet-4",
          "contextWindowTokens": 200000,
          "contextUsedEstimate": 84800,
          "contextPercentEstimate": 18,
          "contextConfidence": "medium",
          "contextSource": "transcript"
        }]
        """#

        _ = context.evaluateScript("window.updateResults(\(payload));")

        #expect(try invokeString("__queryFirstText(__els.results.children[0], 'row__path')", in: context) == "/Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation")
        #expect(try invokeString("__queryFirstText(__els.results.children[0], 'row__model-meta')", in: context) == "claude-sonnet-4 · 2m ago")
        #expect(try invokeString("__queryFirstText(__els.results.children[0], 'row__context-label')", in: context) == "~18% 84.8k")
        #expect(try invokeString("__queryFirstStyle(__els.results.children[0], 'row__context-rail-fill', 'width')", in: context) == "18%")
    }

    @Test("mouseenter selects hovered row")
    func mouseEnterSelectsHoveredRow() throws {
        let context = try makePanelScriptContext()
        let payload = #"""
        [{
          "sessionId": "sess-1",
          "tool": "claude",
          "title": "First",
          "project": "/tmp/first",
          "projectName": "first",
          "gitBranch": "",
          "status": "live",
          "startedAt": "2026-03-28T09:30:00Z",
          "tokenCount": 1200,
          "lastActivityAt": "2026-03-28T09:42:00Z",
          "activityStatus": "waiting",
          "relativeTime": "2m ago",
          "healthStatus": "ok",
          "healthDetail": ""
        }, {
          "sessionId": "sess-2",
          "tool": "codex",
          "title": "Second",
          "project": "/tmp/second",
          "projectName": "second",
          "gitBranch": "",
          "status": "live",
          "startedAt": "2026-03-28T09:30:00Z",
          "tokenCount": 2300,
          "lastActivityAt": "2026-03-28T09:41:00Z",
          "activityStatus": "waiting",
          "relativeTime": "3m ago",
          "healthStatus": "ok",
          "healthDetail": ""
        }]
        """#

        _ = context.evaluateScript("window.updateResults(\(payload));")
        #expect(try invokeBool("__hasClass(__els.results.children[0], 'row--selected')", in: context))
        #expect(!(try invokeBool("__hasClass(__els.results.children[1], 'row--selected')", in: context)))

        _ = context.evaluateScript("__dispatch(__els.results.children[1], 'mouseenter');")

        #expect(!(try invokeBool("__hasClass(__els.results.children[0], 'row--selected')", in: context)))
        #expect(try invokeBool("__hasClass(__els.results.children[1], 'row--selected')", in: context))
    }

    @Test("context label falls back to unknown percent when percent estimate is missing")
    func contextLabelFallsBackToUnknownPercent() throws {
        let context = try makePanelScriptContext()
        let payload = #"""
        [{
          "sessionId": "sess-1",
          "tool": "claude",
          "title": "Need context fallback",
          "project": "/tmp/project",
          "projectName": "project",
          "gitBranch": "",
          "status": "live",
          "startedAt": "2026-03-28T09:30:00Z",
          "tokenCount": 61000,
          "lastActivityAt": "2026-03-28T09:42:00Z",
          "activityStatus": "waiting",
          "relativeTime": "2m ago",
          "healthStatus": "ok",
          "healthDetail": "",
          "effectiveModel": "claude-sonnet-4",
          "contextUsedEstimate": 61000,
          "contextConfidence": "unknown"
        }]
        """#

        _ = context.evaluateScript("window.updateResults(\(payload));")
        #expect(try invokeString("__queryFirstText(__els.results.children[0], 'row__context-label')", in: context) == "? 61k")
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
    function __normalizeClassName(el) {
      var names = [];
      for (var key in el.__classes) {
        if (el.__classes[key]) names.push(key);
      }
      el.className = names.join(' ');
    }
    function __makeClassList(el) {
      return {
        add: function(name) {
          el.__classes[name] = true;
          __normalizeClassName(el);
        },
        remove: function(name) {
          delete el.__classes[name];
          __normalizeClassName(el);
        },
        toggle: function(name, force) {
          if (arguments.length > 1) {
            if (force) {
              this.add(name);
            } else {
              this.remove(name);
            }
            return force;
          }
          if (el.__classes[name]) {
            this.remove(name);
            return false;
          }
          this.add(name);
          return true;
        },
        contains: function(name) {
          return !!el.__classes[name];
        }
      };
    }
    function __matchesClass(el, name) {
      return !!(el && el.__classes && el.__classes[name]);
    }
    function __walk(el, visit) {
      if (!el || !el.children) return;
      for (var i = 0; i < el.children.length; i++) {
        var child = el.children[i];
        visit(child);
        __walk(child, visit);
      }
    }
    function __queryByClass(el, className, firstOnly) {
      var results = [];
      __walk(el, function(child) {
        if (__matchesClass(child, className)) {
          results.push(child);
        }
      });
      return firstOnly ? (results[0] || null) : results;
    }
    function __makeEl(tagName) {
      var el = {
        tagName: tagName || 'div',
        value: '',
        textContent: '',
        style: {},
        children: [],
        dataset: {},
        attributes: {},
        __classes: {},
        __listeners: {},
        offsetHeight: 0,
        offsetWidth: 0,
        scrollHeight: 0,
        selectionStart: 0,
        classList: null,
        addEventListener: function(type, handler){
          if (!this.__listeners[type]) this.__listeners[type] = [];
          this.__listeners[type].push(handler);
        },
        focus: function(){},
        blur: function(){},
        appendChild: function(child){
          child.parentNode = this;
          this.children.push(child);
          this.scrollHeight = this.children.length * 56;
        },
        querySelector: function(selector){
          if (selector.charAt(0) !== '.') return null;
          return __queryByClass(this, selector.slice(1), true);
        },
        querySelectorAll: function(selector){
          if (selector.charAt(0) !== '.') return [];
          return __queryByClass(this, selector.slice(1), false);
        },
        scrollIntoView: function(){},
        getBoundingClientRect: function(){ return { top: 0, bottom: 0, height: 0 }; },
        removeAttribute: function(name){ delete this.attributes[name]; },
        setAttribute: function(name, value){ this.attributes[name] = value; }
      };
      Object.defineProperty(el, 'className', {
        get: function() {
          var names = [];
          for (var key in this.__classes) {
            if (this.__classes[key]) names.push(key);
          }
          return names.join(' ');
        },
        set: function(value) {
          this.__classes = {};
          var parts = (value || '').split(/\s+/);
          for (var i = 0; i < parts.length; i++) {
            if (parts[i]) this.__classes[parts[i]] = true;
          }
        }
      });
      Object.defineProperty(el, 'innerHTML', {
        get: function() {
          return '';
        },
        set: function(value) {
          this.children = [];
          this.textContent = value || '';
          this.scrollHeight = 0;
        }
      });
      return el;
    }
    var __els = {};
    function __registerBaseClass(el) {
      if (el.className) {
        el.__classes[el.className] = true;
      }
      el.classList = __makeClassList(el);
      __normalizeClassName(el);
      return el;
    }
    var document = {
      getElementById: function(id) {
        if (!__els[id]) __els[id] = __registerBaseClass(__makeEl('div'));
        return __els[id];
      },
      addEventListener: function(){},
      createElement: function(tagName){ return __registerBaseClass(__makeEl(tagName)); },
      body: { appendChild: function(){} }
    };
    __els.results = document.getElementById('results');
    __els.panel = document.getElementById('panel');
    __els.panel.offsetHeight = 500;
    __els.searchInput = document.getElementById('searchInput');
    __els.actionHint = document.getElementById('actionHint');
    function getComputedStyle() { return { fontFamily: 'monospace' }; }
    function setTimeout() { return 1; }
    function clearTimeout() {}
    function requestAnimationFrame(cb) { cb(); }
    function __dispatch(el, type) {
      var handlers = (el && el.__listeners && el.__listeners[type]) || [];
      for (var i = 0; i < handlers.length; i++) {
        handlers[i].call(el, { type: type, currentTarget: el, preventDefault: function(){} });
      }
    }
    function __hasClass(el, className) {
      return __matchesClass(el, className);
    }
    function __queryFirstText(el, className) {
      var match = __queryByClass(el, className, true);
      return match ? match.textContent : null;
    }
    function __queryFirstStyle(el, className, property) {
      var match = __queryByClass(el, className, true);
      return match && match.style ? match.style[property] || '' : '';
    }
    """#

    _ = context.evaluateScript(bootstrap)
    _ = context.evaluateScript(try loadPanelScript())
    return context
}

private func invokeBool(_ script: String, in context: JSContext) throws -> Bool {
    let value = try #require(context.evaluateScript(script))
    return value.toBool()
}

private func invokeString(_ script: String, in context: JSContext) throws -> String {
    let value = try #require(context.evaluateScript(script))
    return try #require(value.toString())
}
