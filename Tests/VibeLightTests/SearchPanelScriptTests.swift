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

    @Test("Tab keydown toggles mode through the real bridge path without mutating search")
    func tabKeydownTogglesModeThroughRealBridgePath() throws {
        let context = try makePanelScriptContext()
        _ = context.evaluateScript(
            """
            __els.searchInput.value = 'ship';
            __els.searchInput.selectionStart = __els.searchInput.value.length;
            __els.ghostSuggestion.innerHTML = '';
            var spacer = document.createElement('span');
            spacer.className = 'ghost-suggestion__spacer';
            spacer.textContent = 'ship';
            var completion = document.createElement('span');
            completion.className = 'ghost-suggestion__completion';
            completion.textContent = '-telemetry';
            __els.ghostSuggestion.appendChild(spacer);
            __els.ghostSuggestion.appendChild(completion);
            """
        )
        _ = context.evaluateScript("__dispatchDocumentKeydown('Tab');")

        #expect(try invokeBool("window.__lastKeydownPrevented === true", in: context))
        #expect(try invokeString("__els.searchInput.value", in: context) == "ship")
        #expect(try invokeInt("window.__bridgeMessages.length", in: context) == 1)
        #expect(try invokeString("window.__bridgeMessages[0].type", in: context) == "toggleMode")
    }

    @Test("Tab keydown with empty query does not toggle mode")
    func tabKeydownWithEmptyQueryDoesNotToggleMode() throws {
        let context = try makePanelScriptContext()
        _ = context.evaluateScript(
            """
            __els.searchInput.value = '';
            __els.searchInput.selectionStart = 0;
            """
        )
        _ = context.evaluateScript("__dispatchDocumentKeydown('Tab');")

        #expect(try invokeBool("window.__lastKeydownPrevented === true", in: context))
        #expect(try invokeString("__els.searchInput.value", in: context) == "")
        #expect(try invokeInt("window.__bridgeMessages.length", in: context) == 0)
    }

    @Test("stale preview hides when its session disappears after refresh")
    func stalePreviewHidesWhenSessionDisappearsAfterRefresh() throws {
        let context = try makePanelScriptContext()
        let initialPayload = #"""
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
        let filteredPayload = #"""
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
        }]
        """#
        let previewPayload = #"""
        {
          "exchanges": [{ "role": "assistant", "text": "Preview text" }],
          "files": []
        }
        """#

        _ = context.evaluateScript("window.updateResults(\(initialPayload));")
        _ = context.evaluateScript("__dispatch(__els.results.children[1], 'mouseenter');")
        _ = context.evaluateScript("__runAllTimeouts();")
        _ = context.evaluateScript("window.updatePreview(\(previewPayload));")

        #expect(try invokeBool("__hasClass(__els.previewCard, 'preview--visible')", in: context))
        #expect(try invokeBool(
            "window.__bridgeMessages.some(function(msg) { return msg.type === 'previewVisible' && msg.visible === true; })",
            in: context
        ))

        _ = context.evaluateScript("window.updateResults(\(filteredPayload));")

        #expect(!(try invokeBool("__hasClass(__els.previewCard, 'preview--visible')", in: context)))
        #expect(try invokeBool(
            "window.__bridgeMessages.some(function(msg) { return msg.type === 'previewVisible' && msg.visible === false; })",
            in: context
        ))
    }

    @Test("search input debounce cancels stale queries")
    func searchInputDebounceCancelsStaleQueries() throws {
        let context = try makePanelScriptContext()
        _ = context.evaluateScript(
            """
            __els.searchInput.value = 'c';
            __dispatch(__els.searchInput, 'input');
            __els.searchInput.value = 'co';
            __dispatch(__els.searchInput, 'input');
            __runAllTimeouts();
            """
        )

        #expect(try invokeInt("window.__bridgeMessages.length", in: context) == 1)
        #expect(try invokeString("window.__bridgeMessages[0].type", in: context) == "search")
        #expect(try invokeString("window.__bridgeMessages[0].query", in: context) == "co")
    }

    @Test("filtering away a hovered row cancels its pending preview dwell")
    func filteringAwayHoveredRowCancelsPendingPreviewDwell() throws {
        let context = try makePanelScriptContext()
        let initialPayload = #"""
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
        let filteredPayload = #"""
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
        }]
        """#

        _ = context.evaluateScript("window.updateResults(\(initialPayload));")
        _ = context.evaluateScript("__dispatch(__els.results.children[1], 'mouseenter');")
        _ = context.evaluateScript("window.updateResults(\(filteredPayload));")
        _ = context.evaluateScript("__runAllTimeouts();")

        #expect(try invokeBool("window.__bridgeMessages.some(function(msg) { return msg.type === 'preview' && msg.sessionId === 'sess-2'; })", in: context) == false)
    }

    @Test("same-row refresh preserves pending preview dwell")
    func sameRowRefreshPreservesPendingPreviewDwell() throws {
        let context = try makePanelScriptContext()
        let payload = #"""
        [{
          "sessionId": "sess-stable",
          "tool": "claude",
          "title": "Stable Session",
          "project": "/tmp/stable",
          "projectName": "stable",
          "gitBranch": "",
          "status": "closed",
          "startedAt": "2026-03-28T09:30:00Z",
          "tokenCount": 1200,
          "lastActivityAt": "2026-03-28T09:42:00Z",
          "activityStatus": "closed",
          "relativeTime": "2m ago",
          "healthStatus": "ok",
          "healthDetail": ""
        }]
        """#

        _ = context.evaluateScript("window.updateResults(\(payload));")
        _ = context.evaluateScript("__dispatch(__els.results.children[0], 'mouseenter');")
        _ = context.evaluateScript("window.updateResults(\(payload));")
        _ = context.evaluateScript("__runAllTimeouts();")

        #expect(try invokeBool(
            "window.__bridgeMessages.some(function(msg) { return msg.type === 'preview' && msg.sessionId === 'sess-stable'; })",
            in: context
        ))
    }

    @Test("preview renders state detail rounds and files in adaptive sections")
    func previewRendersStateDetailRoundsAndFilesInAdaptiveSections() throws {
        let context = try makePanelScriptContext()
        let payload = #"""
        {
          "state": "Question",
          "detail": "Which layout do you prefer?",
          "exchanges": [
            { "role": "user", "text": "Please make the preview state clearer.", "isError": false },
            { "role": "assistant", "text": "I grouped the preview into state, detail, rounds, and files.", "isError": false }
          ],
          "files": [
            "/tmp/Sources/VibeLight/Resources/Web/panel.js"
          ]
        }
        """#

        _ = context.evaluateScript("window.updatePreview(\(payload));")

        #expect(try invokeInt("__queryByClass(__els.previewCard, 'preview__round', false).length", in: context) == 2)
        #expect(try invokeString("__queryByClass(__els.previewCard, 'preview__round-role', false)[0].textContent", in: context) == "You")
        #expect(try invokeString("__queryFirstText(__els.previewCard, 'preview__section-label')", in: context) == "Files")
        #expect(try invokeBool("__hasClass(__els.previewCard, 'preview--visible')", in: context))
    }

    @Test("result rows use full-width title with split model-meta and path footer")
    func resultRowsUseFullWidthTitleWithSplitModelMetaAndPathFooter() throws {
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

        #expect(try invokeString("__queryFirstText(__els.results.children[0], 'row__title')", in: context) == "Ship telemetry")
        #expect(try invokeInt("__queryByClass(__els.results.children[0], 'row__meta-row', false).length", in: context) == 1)
        #expect(try invokeString("__queryFirstText(__els.results.children[0], 'row__path')", in: context) == "/Users/fuyuming/Desktop/project/vibelight/.worktrees/v1-implementation")
        #expect(try invokeString("__queryFirstText(__els.results.children[0], 'row__model-meta')", in: context) == "claude-sonnet-4 · 84.8k · 2m ago")
        #expect(try invokeInt("__queryByClass(__els.results.children[0], 'row__context', false).length", in: context) == 0)
        #expect(try invokeInt("__queryByClass(__els.results.children[0], 'row__context-rail', false).length", in: context) == 0)
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

    @Test("mouseenter on already selected finished row still schedules preview dwell")
    func mouseEnterOnAlreadySelectedFinishedRowStillSchedulesPreviewDwell() throws {
        let context = try makePanelScriptContext()
        let payload = #"""
        [{
          "sessionId": "sess-finished",
          "tool": "codex",
          "title": "Finished Session",
          "project": "/tmp/finished",
          "projectName": "finished",
          "gitBranch": "",
          "status": "closed",
          "startedAt": "2026-03-28T09:30:00Z",
          "tokenCount": 2300,
          "lastActivityAt": "2026-03-28T09:41:00Z",
          "activityStatus": "closed",
          "relativeTime": "3m ago",
          "healthStatus": "ok",
          "healthDetail": ""
        }]
        """#

        _ = context.evaluateScript("window.updateResults(\(payload));")
        _ = context.evaluateScript("__dispatch(__els.results.children[0], 'mouseenter');")
        _ = context.evaluateScript("__runAllTimeouts();")

        #expect(try invokeBool(
            "window.__bridgeMessages.some(function(msg) { return msg.type === 'preview' && msg.sessionId === 'sess-finished'; })",
            in: context
        ))
    }

    @Test("click on row triggers dwell preview request")
    func clickOnRowTriggersDwellPreviewRequest() throws {
        let context = try makePanelScriptContext()
        let payload = #"""
        [{
          "sessionId": "sess-click",
          "tool": "codex",
          "title": "Clickable Session",
          "project": "/tmp/clickable",
          "projectName": "clickable",
          "gitBranch": "",
          "status": "closed",
          "startedAt": "2026-03-28T09:30:00Z",
          "tokenCount": 1200,
          "lastActivityAt": "2026-03-28T09:42:00Z",
          "activityStatus": "closed",
          "relativeTime": "2m ago",
          "healthStatus": "ok",
          "healthDetail": ""
        }]
        """#

        _ = context.evaluateScript("window.updateResults(\(payload));")
        _ = context.evaluateScript("__dispatch(__els.results.children[0], 'click');")
        _ = context.evaluateScript("__runAllTimeouts();")

        #expect(try invokeBool(
            "window.__bridgeMessages.some(function(msg) { return msg.type === 'preview' && msg.sessionId === 'sess-click'; })",
            in: context
        ))
    }

    @Test("activate selected includes the live search input in the select bridge message")
    func activateSelectedIncludesCurrentSearchInputInSelectMessage() throws {
        let context = try makePanelScriptContext()
        let payload = #"""
        [{
          "sessionId": "new-codex",
          "tool": "codex",
          "title": "New Codex session",
          "project": "/tmp/project",
          "projectName": "project",
          "gitBranch": "",
          "status": "action",
          "startedAt": "2026-03-28T09:30:00Z",
          "tokenCount": 0,
          "lastActivityAt": "2026-03-28T09:42:00Z",
          "activityStatus": "closed",
          "relativeTime": "2m ago",
          "healthStatus": "ok",
          "healthDetail": ""
        }]
        """#

        _ = context.evaluateScript("window.updateResults(\(payload));")
        _ = context.evaluateScript("__els.searchInput.value = 'new codex session';")
        _ = context.evaluateScript("window.activateSelected();")

        #expect(try invokeBool(
            "window.__bridgeMessages.some(function(msg) { return msg.type === 'select' && msg.query === 'new codex session'; })",
            in: context
        ))
    }

    @Test("schedule dwell is a no-op when selected row preview is already current and visible")
    func scheduleDwellNoOpWhenPreviewAlreadyCurrentAndVisible() throws {
        let context = try makePanelScriptContext()
        let payload = #"""
        [{
          "sessionId": "sess-stable",
          "tool": "claude",
          "title": "Stable Session",
          "project": "/tmp/stable",
          "projectName": "stable",
          "gitBranch": "",
          "status": "closed",
          "startedAt": "2026-03-28T09:30:00Z",
          "tokenCount": 1200,
          "lastActivityAt": "2026-03-28T09:42:00Z",
          "activityStatus": "closed",
          "relativeTime": "2m ago",
          "healthStatus": "ok",
          "healthDetail": ""
        }]
        """#
        let previewPayload = #"""
        {
          "state": "Task",
          "detail": "Stable preview detail",
          "exchanges": [{ "role": "assistant", "text": "Preview text" }],
          "files": []
        }
        """#

        _ = context.evaluateScript("window.updateResults(\(payload));")
        _ = context.evaluateScript("__dispatch(__els.results.children[0], 'mouseenter');")
        _ = context.evaluateScript("__runAllTimeouts();")
        _ = context.evaluateScript("window.updatePreview(\(previewPayload));")

        let previewRequestCountBefore = try invokeInt(
            "window.__bridgeMessages.filter(function(msg) { return msg.type === 'preview' && msg.sessionId === 'sess-stable'; }).length",
            in: context
        )
        let previewHideCountBefore = try invokeInt(
            "window.__bridgeMessages.filter(function(msg) { return msg.type === 'previewVisible' && msg.visible === false; }).length",
            in: context
        )

        _ = context.evaluateScript("__dispatch(__els.results.children[0], 'click');")
        _ = context.evaluateScript("__runAllTimeouts();")

        let previewRequestCountAfter = try invokeInt(
            "window.__bridgeMessages.filter(function(msg) { return msg.type === 'preview' && msg.sessionId === 'sess-stable'; }).length",
            in: context
        )
        let previewHideCountAfter = try invokeInt(
            "window.__bridgeMessages.filter(function(msg) { return msg.type === 'previewVisible' && msg.visible === false; }).length",
            in: context
        )

        #expect(previewRequestCountAfter == previewRequestCountBefore)
        #expect(previewHideCountAfter == previewHideCountBefore)
    }

    @Test("action row selection hides preview immediately and does not request dwell preview")
    func actionRowSelectionHidesPreviewAndSkipsDwellRequest() throws {
        let context = try makePanelScriptContext()
        let payload = #"""
        [{
          "sessionId": "sess-normal",
          "tool": "claude",
          "title": "Normal Session",
          "project": "/tmp/normal",
          "projectName": "normal",
          "gitBranch": "",
          "status": "closed",
          "startedAt": "2026-03-28T09:30:00Z",
          "tokenCount": 1200,
          "lastActivityAt": "2026-03-28T09:42:00Z",
          "activityStatus": "closed",
          "relativeTime": "2m ago",
          "healthStatus": "ok",
          "healthDetail": ""
        }, {
          "sessionId": "new-codex",
          "tool": "codex",
          "title": "New Codex session",
          "project": "/tmp/normal",
          "projectName": "normal",
          "gitBranch": "",
          "status": "action",
          "startedAt": "2026-03-28T09:30:00Z",
          "tokenCount": 0,
          "lastActivityAt": "2026-03-28T09:42:00Z",
          "activityStatus": "closed",
          "relativeTime": "2m ago",
          "healthStatus": "ok",
          "healthDetail": ""
        }]
        """#
        let visiblePreviewPayload = #"""
        {
          "sessionId": "sess-normal",
          "lastActivityAt": "2026-03-28T09:42:00Z",
          "state": "Task",
          "detail": "Preview detail",
          "exchanges": [{ "role": "assistant", "text": "Preview text" }],
          "files": []
        }
        """#

        _ = context.evaluateScript("window.updateResults(\(payload));")
        _ = context.evaluateScript("__dispatch(__els.results.children[0], 'mouseenter');")
        _ = context.evaluateScript("__runAllTimeouts();")
        _ = context.evaluateScript("window.updatePreview(\(visiblePreviewPayload));")

        #expect(try invokeBool("__hasClass(__els.previewCard, 'preview--visible')", in: context))

        _ = context.evaluateScript("__dispatch(__els.results.children[1], 'click');")
        _ = context.evaluateScript("__runAllTimeouts();")

        #expect(!(try invokeBool("__hasClass(__els.previewCard, 'preview--visible')", in: context)))
        #expect(try invokeBool(
            "window.__bridgeMessages.some(function(msg) { return msg.type === 'preview' && msg.sessionId === 'new-codex'; })",
            in: context
        ) == false)
    }

    @Test("stale preview payload is ignored when session identity does not match latest request")
    func stalePreviewPayloadIsIgnoredWhenSessionIdentityDoesNotMatchLatestRequest() throws {
        let context = try makePanelScriptContext()
        let payload = #"""
        [{
          "sessionId": "sess-current",
          "tool": "claude",
          "title": "Current Session",
          "project": "/tmp/current",
          "projectName": "current",
          "gitBranch": "",
          "status": "closed",
          "startedAt": "2026-03-28T09:30:00Z",
          "tokenCount": 1200,
          "lastActivityAt": "2026-03-28T09:42:00Z",
          "activityStatus": "closed",
          "relativeTime": "2m ago",
          "healthStatus": "ok",
          "healthDetail": ""
        }]
        """#
        let stalePayload = #"""
        {
          "sessionId": "sess-stale",
          "lastActivityAt": "2026-03-28T09:41:00Z",
          "state": "Task",
          "detail": "Stale preview",
          "exchanges": [{ "role": "assistant", "text": "Stale" }],
          "files": []
        }
        """#
        let freshPayload = #"""
        {
          "sessionId": "sess-current",
          "lastActivityAt": "2026-03-28T09:42:00Z",
          "state": "Task",
          "detail": "Fresh preview",
          "exchanges": [{ "role": "assistant", "text": "Fresh" }],
          "files": []
        }
        """#

        _ = context.evaluateScript("window.updateResults(\(payload));")
        _ = context.evaluateScript("__dispatch(__els.results.children[0], 'mouseenter');")
        _ = context.evaluateScript("__runAllTimeouts();")

        _ = context.evaluateScript("window.updatePreview(\(stalePayload));")
        #expect(!(try invokeBool("__hasClass(__els.previewCard, 'preview--visible')", in: context)))

        _ = context.evaluateScript("window.updatePreview(\(freshPayload));")
        #expect(try invokeBool("__hasClass(__els.previewCard, 'preview--visible')", in: context))
        #expect(try invokeString("__queryFirstText(__els.previewCard, 'preview__round-text')", in: context) == "Fresh")
    }

    @Test("preview requests panel growth for long content instead of scrolling inside the card")
    func previewRequestsPanelGrowthForLongContent() throws {
        let context = try makePanelScriptContext()
        let payload = #"""
        {
          "state": "Working",
          "detail": "Long preview detail that should remain fully accessible inside the card.",
          "exchanges": [
            { "role": "assistant", "text": "Long preview line 0", "isError": false },
            { "role": "assistant", "text": "Long preview line 1", "isError": false },
            { "role": "assistant", "text": "Long preview line 2", "isError": false },
            { "role": "assistant", "text": "Long preview line 3", "isError": false },
            { "role": "assistant", "text": "Long preview line 4", "isError": false },
            { "role": "assistant", "text": "Long preview line 5", "isError": false },
            { "role": "assistant", "text": "Long preview line 6", "isError": false },
            { "role": "assistant", "text": "Long preview line 7", "isError": false }
          ],
          "files": [
            "/tmp/project/file0.swift",
            "/tmp/project/file1.swift",
            "/tmp/project/file2.swift",
            "/tmp/project/file3.swift",
            "/tmp/project/file4.swift",
            "/tmp/project/file5.swift"
          ]
        }
        """#

        _ = context.evaluateScript("__els.panel.offsetHeight = 180;")
        _ = context.evaluateScript("__els.panel.getBoundingClientRect = function(){ return { top: 0, bottom: 180, height: 180 }; };")
        _ = context.evaluateScript("__els.results.getBoundingClientRect = function(){ return { top: 0, bottom: 124, height: 124 }; };")
        let resizeCountBefore = try invokeInt(
            "window.__bridgeMessages.filter(function(msg) { return msg.type === 'resize'; }).length",
            in: context
        )
        _ = context.evaluateScript("window.updatePreview(\(payload));")

        let resizeCountAfter = try invokeInt(
            "window.__bridgeMessages.filter(function(msg) { return msg.type === 'resize'; }).length",
            in: context
        )

        #expect(try invokeString("__els.previewCard.style.maxHeight", in: context) == "")
        #expect(resizeCountAfter == resizeCountBefore + 1)
    }

    @Test("preview card clamps upward instead of hanging below the panel")
    func previewCardClampsUpwardInsteadOfHangingBelowThePanel() throws {
        let context = try makePanelScriptContext()
        let payload = #"""
        {
          "exchanges": [
            { "role": "assistant", "text": "Preview line 0", "isError": false },
            { "role": "assistant", "text": "Preview line 1", "isError": false },
            { "role": "assistant", "text": "Preview line 2", "isError": false }
          ],
          "files": [
            "/tmp/project/file0.swift",
            "/tmp/project/file1.swift"
          ]
        }
        """#

        _ = context.evaluateScript("__els.panel.offsetHeight = 180;")
        _ = context.evaluateScript("__els.panel.getBoundingClientRect = function(){ return { top: 0, bottom: 180, height: 180 }; };")
        _ = context.evaluateScript("__els.results.children = [__registerBaseClass(__makeEl('div'))];")
        _ = context.evaluateScript("__els.results.children[0].className = 'row';")
        _ = context.evaluateScript("__els.results.children[0].getBoundingClientRect = function(){ return { top: 150, bottom: 170, height: 20 }; };")
        _ = context.evaluateScript("window.updatePreview(\(payload));")

        #expect(try invokeBool("parseInt(__els.previewCard.style.top, 10) < 150", in: context))
    }

    @Test("low-confidence rows omit token count from model metadata")
    func lowConfidenceRowsOmitTokenCountFromModelMetadata() throws {
        let context = try makePanelScriptContext()
        let payload = #"""
        [{
          "sessionId": "sess-low-confidence",
          "tool": "claude",
          "title": "Low confidence context",
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
          "contextWindowTokens": 200000,
          "contextUsedEstimate": 61000,
          "contextPercentEstimate": 31,
          "contextConfidence": "low"
        }]
        """#

        _ = context.evaluateScript("window.updateResults(\(payload));")
        #expect(try invokeString("__queryFirstText(__els.results.children[0], 'row__model-meta')", in: context) == "claude-sonnet-4 · 2m ago")
    }

    @Test("high-confidence rows fall back to token count when used estimate is missing")
    func highConfidenceRowsFallbackToTokenCountWhenUsedEstimateMissing() throws {
        let context = try makePanelScriptContext()
        let payload = #"""
        [{
          "sessionId": "sess-token-fallback",
          "tool": "claude",
          "title": "Token fallback context",
          "project": "/tmp/project",
          "projectName": "project",
          "gitBranch": "",
          "status": "live",
          "startedAt": "2026-03-28T09:30:00Z",
          "tokenCount": 1200,
          "lastActivityAt": "2026-03-28T09:42:00Z",
          "activityStatus": "waiting",
          "relativeTime": "2m ago",
          "healthStatus": "ok",
          "healthDetail": "",
          "effectiveModel": "claude-sonnet-4",
          "contextWindowTokens": 200000,
          "contextPercentEstimate": 31,
          "contextConfidence": "high"
        }]
        """#

        _ = context.evaluateScript("window.updateResults(\(payload));")
        #expect(try invokeString("__queryFirstText(__els.results.children[0], 'row__model-meta')", in: context) == "claude-sonnet-4 · 1.2k · 2m ago")
    }

    @Test("high-confidence rows omit zero token placeholders")
    func highConfidenceRowsOmitZeroTokenPlaceholders() throws {
        let context = try makePanelScriptContext()
        let payload = #"""
        [{
          "sessionId": "sess-zero-token",
          "tool": "claude",
          "title": "Zero token context",
          "project": "/tmp/project",
          "projectName": "project",
          "gitBranch": "",
          "status": "live",
          "startedAt": "2026-03-28T09:30:00Z",
          "tokenCount": 0,
          "lastActivityAt": "2026-03-28T09:42:00Z",
          "activityStatus": "waiting",
          "relativeTime": "2m ago",
          "healthStatus": "ok",
          "healthDetail": "",
          "effectiveModel": "claude-sonnet-4",
          "contextWindowTokens": 200000,
          "contextUsedEstimate": 0,
          "contextPercentEstimate": 31,
          "contextConfidence": "high"
        }]
        """#

        _ = context.evaluateScript("window.updateResults(\(payload));")
        #expect(try invokeString("__queryFirstText(__els.results.children[0], 'row__model-meta')", in: context) == "claude-sonnet-4 · 2m ago")
    }

    @Test("rows never render typing dots or status dots ornaments")
    func rowsNeverRenderTypingDotsOrStatusDotsOrnaments() throws {
        let context = try makePanelScriptContext()
        let payload = #"""
        [{
          "sessionId": "sess-low-confidence",
          "tool": "claude",
          "title": "Low confidence context",
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
          "contextWindowTokens": 200000,
          "contextUsedEstimate": 61000,
          "contextPercentEstimate": 31,
          "contextConfidence": "high"
        }, {
          "sessionId": "sess-waiting-dot",
          "tool": "claude",
          "title": "Waiting row",
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
          "contextWindowTokens": 200000,
          "contextUsedEstimate": 61000,
          "contextPercentEstimate": 31,
          "contextConfidence": "high"
        }]
        """#

        _ = context.evaluateScript("window.updateResults(\(payload));")
        #expect(try invokeInt("__queryByClass(__els.results, 'typing-dots', false).length", in: context) == 0)
        #expect(try invokeInt("__queryByClass(__els.results, 'status-dot', false).length", in: context) == 0)
    }

    @Test("rows without effective model show unknown model state")
    func rowsWithoutEffectiveModelShowUnknownModelState() throws {
        let context = try makePanelScriptContext()
        let payload = #"""
        [{
          "sessionId": "sess-no-model",
          "tool": "codex",
          "title": "No model metadata",
          "project": "/tmp/project",
          "projectName": "project",
          "gitBranch": "",
          "status": "live",
          "startedAt": "2026-03-28T09:30:00Z",
          "tokenCount": 1200,
          "lastActivityAt": "2026-03-28T09:42:00Z",
          "activityStatus": "waiting",
          "relativeTime": "2m ago",
          "healthStatus": "ok",
          "healthDetail": ""
        }]
        """#

        _ = context.evaluateScript("window.updateResults(\(payload));")
        #expect(try invokeString("__queryFirstText(__els.results.children[0], 'row__model-meta')", in: context) == "codex · model unknown · 2m ago")
    }

    @Test("panel script includes adaptive preview section hooks")
    func panelScriptIncludesAdaptivePreviewSectionHooks() throws {
        let script = try loadPanelScript()

        #expect(script.contains("preview__rounds"))
        #expect(script.contains("preview__files"))
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
    var window = this;
    window.__bridgeMessages = [];
    window.webkit = { messageHandlers: { bridge: { postMessage: function(message) { window.__bridgeMessages.push(message); } } } };
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
      __listeners: {},
      getElementById: function(id) {
        if (!__els[id]) __els[id] = __registerBaseClass(__makeEl('div'));
        return __els[id];
      },
      addEventListener: function(type, handler){
        if (!this.__listeners[type]) this.__listeners[type] = [];
        this.__listeners[type].push(handler);
      },
      createElement: function(tagName){ return __registerBaseClass(__makeEl(tagName)); },
      body: { appendChild: function(){} }
    };
    __els.results = document.getElementById('results');
    __els.panel = document.getElementById('panel');
    __els.panel.offsetHeight = 500;
    __els.searchInput = document.getElementById('searchInput');
    __els.actionHint = document.getElementById('actionHint');
    function getComputedStyle() { return { fontFamily: 'monospace' }; }
    window.__timeoutCallbacks = {};
    window.__nextTimeoutId = 1;
    function setTimeout(cb) {
      var id = window.__nextTimeoutId++;
      window.__timeoutCallbacks[id] = cb;
      return id;
    }
    function clearTimeout(id) {
      delete window.__timeoutCallbacks[id];
    }
    function requestAnimationFrame(cb) { cb(); }
    window.__lastKeydownPrevented = false;
    function __dispatch(el, type) {
      var handlers = (el && el.__listeners && el.__listeners[type]) || [];
      for (var i = 0; i < handlers.length; i++) {
        handlers[i].call(el, { type: type, currentTarget: el, preventDefault: function(){} });
      }
    }
    function __dispatchDocumentKeydown(key) {
      window.__lastKeydownPrevented = false;
      var handlers = (document.__listeners && document.__listeners['keydown']) || [];
      for (var i = 0; i < handlers.length; i++) {
        handlers[i].call(document, {
          key: key,
          type: 'keydown',
          currentTarget: document,
          preventDefault: function() {
            window.__lastKeydownPrevented = true;
          }
        });
      }
    }
    function __runAllTimeouts() {
      var ids = Object.keys(window.__timeoutCallbacks)
        .map(function(key) { return parseInt(key, 10); })
        .sort(function(a, b) { return a - b; });
      for (var i = 0; i < ids.length; i++) {
        var id = ids[i];
        if (!window.__timeoutCallbacks[id]) continue;
        var callback = window.__timeoutCallbacks[id];
        delete window.__timeoutCallbacks[id];
        callback();
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

private func invokeInt(_ script: String, in context: JSContext) throws -> Int {
    let value = try #require(context.evaluateScript(script))
    return Int(value.toInt32())
}
