// VibeLight Panel — JS Controller
// Handles: search input, keyboard navigation, result rendering, ghost suggestions
// All navigation is DOM-only — no Swift round-trip for arrow keys

(function() {
  'use strict';

  const bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge;
  const searchInput = document.getElementById('searchInput');
  const ghostSuggestion = document.getElementById('ghostSuggestion');
  const actionHint = document.getElementById('actionHint');
  const searchBarIcon = document.getElementById('searchBarIcon');
  const resultsContainer = document.getElementById('results');
  const panel = document.getElementById('panel');
  const blockCursor = document.getElementById('blockCursor');
  const sessionCountEl = document.getElementById('sessionCount');

  let currentResults = [];
  let selectedIndex = 0;
  let debounceTimer = null;
  let iconBaseURL = '';
  let currentHintTool = null;

  var previewCard = document.getElementById('previewCard');
  var dwellTimer = null;
  var previewedSessionId = null;
  var previewedLastActivity = null;
  var isPreviewShowing = false;
  var currentMode = 'all'; // 'all' = live + history, 'live' = live only

  var codexIntentAliases = ['codex', 'code', 'cod', 'co'];
  var claudeIntentAliases = ['claude', 'clau', 'cla', 'cl'];

  function tokenizeQuery(query) {
    return (query || '').trim().toLowerCase().split(/\s+/).filter(Boolean);
  }

  function intentTokenFromQuery(query) {
    var tokens = tokenizeQuery(query);
    if (!tokens.length) return '';
    if (tokens[0] === 'new' && tokens.length >= 2) return tokens[1];
    return tokens[0];
  }

  function matchesLaunchIntentToken(token, aliases) {
    if (!token) return false;
    if (token.length < 2) return false;
    if (aliases.indexOf(token) !== -1) return true;
    for (var i = 0; i < aliases.length; i++) {
      if (aliases[i].indexOf(token) === 0) return true;
    }
    return false;
  }

  function matchesCodexLaunchIntent(query) {
    var token = intentTokenFromQuery(query);
    return matchesLaunchIntentToken(token, codexIntentAliases);
  }

  function matchesClaudeLaunchIntent(query) {
    var token = intentTokenFromQuery(query);
    return matchesLaunchIntentToken(token, claudeIntentAliases);
  }

  function looksLikeNewSessionIntent(query) {
    var normalized = (query || '').trim().toLowerCase();
    if (!normalized) return false;
    if (matchesCodexLaunchIntent(normalized) || matchesClaudeLaunchIntent(normalized)) return true;
    if (normalized === 'new' || normalized.indexOf('new ') === 0) return true;

    var tokens = tokenizeQuery(normalized);
    if (!tokens.length) return false;
    if (tokens[0] === 'new' && tokens.length === 1) return true;
    if (tokens[0] === 'new' && tokens.length >= 2) {
      return matchesLaunchIntentToken(tokens[1], codexIntentAliases) ||
        matchesLaunchIntentToken(tokens[1], claudeIntentAliases);
    }
    return false;
  }

  window.looksLikeNewSessionIntent = looksLikeNewSessionIntent;
  window.matchesCodexLaunchIntent = matchesCodexLaunchIntent;
  window.matchesClaudeLaunchIntent = matchesClaudeLaunchIntent;

  // --- Swift → JS API ---

  window.updateResults = function(resultsJSON) {
    var newResults = [];

    try {
      if (Array.isArray(resultsJSON)) {
        newResults = resultsJSON;
      } else if (typeof resultsJSON === 'string') {
        var parsed = JSON.parse(resultsJSON);
        newResults = Array.isArray(parsed) ? parsed : [];
      }
    } catch (error) {
      newResults = [];
    }

    currentResults = newResults;
    clearTimeout(dwellTimer);
    dwellTimer = null;
    renderResults();
    if (currentResults.length > 0) {
      selectedIndex = Math.min(selectedIndex, currentResults.length - 1);
    } else {
      selectedIndex = 0;
    }
    updateSelection();
    updateActionHint();
    updateSessionCount();
    computeAndShowGhost();
    notifyResize();

    // Live-refresh preview if the previewed session's activity changed.
    // If filtering/refresh removes that session, hide the stale preview.
    if (previewedSessionId) {
      var current = currentResults.find(function(r) { return r.sessionId === previewedSessionId; });
      if (!current) {
        hidePreview();
      } else if (current.lastActivityAt !== previewedLastActivity) {
        requestPreview(current.sessionId, current.lastActivityAt);
      }
    }
  };

  window.setTheme = function(theme) {
    document.documentElement.setAttribute('data-theme', theme);
  };

  window.setGhostSuggestion = function(text) {
    // Ghost is now computed locally in JS — this is a no-op for backwards compat
  };

  window.resetAndFocus = function() {
    hidePreview();
    searchInput.value = '';
    ghostSuggestion.innerHTML = '';
    selectedIndex = 0;
    currentResults = [];
    previousResultKeys = [];
    resultsContainer.innerHTML = '';
    searchInput.focus();
    updateSessionCount();
    notifyResize();
  };

  window.setIconBaseURL = function(url) {
    iconBaseURL = url;
  };

  // --- Search Input ---

  searchInput.addEventListener('input', function() {
    clearTimeout(debounceTimer);
    // Clear ghost immediately on new input — feels snappy
    ghostSuggestion.innerHTML = '';
    updateBlockCursor();
    debounceTimer = setTimeout(function() {
      if (bridge) {
        bridge.postMessage({ type: 'search', query: searchInput.value });
      }
    }, 150);
  });

  // --- Keyboard Navigation ---

  document.addEventListener('keydown', function(e) {
    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault();
        moveSelection(1);
        break;
      case 'ArrowUp':
        e.preventDefault();
        moveSelection(-1);
        break;
      case 'Enter':
        e.preventDefault();
        activateSelected();
        break;
      case 'Escape':
        e.preventDefault();
        hidePreview();
        if (bridge) bridge.postMessage({ type: 'escape' });
        break;
      case 'Tab':
        e.preventDefault();
        handleTab();
        break;
      case 'ArrowRight':
        if (searchInput.selectionStart === searchInput.value.length) {
          acceptGhostSuggestion();
        }
        break;
    }
  });

  function moveSelection(delta) {
    if (currentResults.length === 0) return;
    const prev = selectedIndex;
    selectedIndex = Math.max(0, Math.min(currentResults.length - 1, selectedIndex + delta));
    if (prev !== selectedIndex) {
      updateSelection();
      updateActionHint();
    }
    scheduleDwell();
  }

  function updateSelection() {
    const rows = resultsContainer.querySelectorAll('.row');
    rows.forEach(function(row, i) {
      row.classList.toggle('row--selected', i === selectedIndex);
    });
    if (rows[selectedIndex]) {
      rows[selectedIndex].scrollIntoView({ block: 'nearest' });
    }
  }

  function activateSelected() {
    hidePreview();
    if (currentResults.length === 0) return;
    const result = currentResults[selectedIndex];
    if (result && bridge) {
      bridge.postMessage({
        type: 'select',
        sessionId: result.sessionId,
        status: result.status,
        tool: result.tool,
        query: searchInput.value
      });
    }
  }

  // --- Ghost Suggestions (computed locally from results) ---

  function computeAndShowGhost() {
    var query = searchInput.value;
    if (!query) {
      ghostSuggestion.innerHTML = '';
      return;
    }
    var lowerQuery = query.toLowerCase();

    // Find first title or project name that starts with the query
    var suggestion = null;
    for (var i = 0; i < currentResults.length; i++) {
      var r = currentResults[i];
      var cleanTitle = stripANSI(r.title || '');
      if (cleanTitle && cleanTitle.toLowerCase().startsWith(lowerQuery)) {
        suggestion = cleanTitle;
        break;
      }
      var pName = r.projectName || lastPathComponent(r.project);
      if (pName && pName.toLowerCase().startsWith(lowerQuery)) {
        suggestion = pName;
        break;
      }
    }

    if (!suggestion || suggestion.toLowerCase() === lowerQuery) {
      ghostSuggestion.innerHTML = '';
      return;
    }

    var spacer = document.createElement('span');
    spacer.className = 'ghost-suggestion__spacer';
    spacer.textContent = query;
    var completion = document.createElement('span');
    completion.className = 'ghost-suggestion__completion';
    completion.textContent = suggestion.slice(query.length);
    ghostSuggestion.innerHTML = '';
    ghostSuggestion.appendChild(spacer);
    ghostSuggestion.appendChild(completion);
  }

  function acceptGhostSuggestion() {
    var completionEl = ghostSuggestion.querySelector('.ghost-suggestion__completion');
    if (!completionEl || !completionEl.textContent) return false;
    var fullText = searchInput.value + completionEl.textContent;
    if (fullText === searchInput.value) return false;
    searchInput.value = fullText;
    ghostSuggestion.innerHTML = '';
    updateBlockCursor();
    // Fire search immediately on accept — no debounce needed
    if (bridge) {
      bridge.postMessage({ type: 'search', query: searchInput.value });
    }
    return true;
  }

  function drillIntoSelectedHistory() {
    if (currentResults.length === 0) return;
    var result = currentResults[selectedIndex];
    if (!result || result.status === 'live' || result.status === 'action' || !result.title) return;
    searchInput.value = result.title;
    ghostSuggestion.innerHTML = '';
    if (bridge) {
      bridge.postMessage({ type: 'search', query: searchInput.value });
    }
  }

  // --- Action Hint ---

  function updateActionHint() {
    if (currentResults.length === 0) {
      actionHint.textContent = '';
      if (currentHintTool !== null) {
        searchBarIcon.removeAttribute('src');
        currentHintTool = null;
      }
      return;
    }
    var result = currentResults[selectedIndex] || currentResults[0];

    // Only update icon if the tool changed — avoids image reload on every arrow key
    var tool = result.tool || null;
    if (tool !== currentHintTool) {
      currentHintTool = tool;
      var iconSrc = toolIconURL(tool);
      if (iconSrc) {
        searchBarIcon.src = iconSrc;
      } else {
        searchBarIcon.removeAttribute('src');
      }
    }

    var newHint;
    if (result.status === 'action') {
      newHint = '\u21A9 Launch';
    } else if (result.status === 'live') {
      newHint = '\u21A9 Switch';
    } else {
      newHint = '\u21A9 Resume \u21E5 History';
    }
    if (actionHint.textContent !== newHint) {
      actionHint.textContent = newHint;
    }
  }

  function scheduleDwell() {
    clearTimeout(dwellTimer);
    dwellTimer = null;
    if (currentResults.length === 0) return;
    var result = currentResults[selectedIndex];
    if (!result) return;
    if (result.status === 'action') {
      hidePreview();
      return;
    }

    var isPreviewCurrent = isPreviewShowing &&
      previewedSessionId === result.sessionId &&
      previewedLastActivity === result.lastActivityAt;
    if (isPreviewCurrent) {
      return;
    }

    hidePreview();
    dwellTimer = setTimeout(function() {
      requestPreview(result.sessionId, result.lastActivityAt);
    }, 300);
  }

  function requestPreview(sessionId, lastActivity) {
    previewedSessionId = sessionId;
    previewedLastActivity = lastActivity;
    if (bridge) {
      bridge.postMessage({ type: 'preview', sessionId: sessionId });
    }
  }

  function hidePreview() {
    clearTimeout(dwellTimer);
    dwellTimer = null;
    previewCard.classList.remove('preview--visible');
    previewedSessionId = null;
    previewedLastActivity = null;
    if (isPreviewShowing) {
      isPreviewShowing = false;
      if (bridge) bridge.postMessage({ type: 'previewVisible', visible: false });
    }
    notifyResize();
  }

  // --- Result Rendering (diff-based) ---

  var previousResultKeys = []; // Track session IDs for diffing

  function renderResults() {
    var newKeys = currentResults.map(function(r) { return r.sessionId; });

    // Fast path: if the keys are identical, just update content in-place
    if (arraysEqual(newKeys, previousResultKeys)) {
      var rows = resultsContainer.children;
      for (var i = 0; i < currentResults.length; i++) {
        updateRowContent(rows[i], currentResults[i], i);
      }
      previousResultKeys = newKeys;
      return;
    }

    // Keys changed: rebuild (add/remove/reorder)
    resultsContainer.innerHTML = '';
    currentResults.forEach(function(result, index) {
      resultsContainer.appendChild(createRow(result, index));
    });
    previousResultKeys = newKeys;
  }

  function arraysEqual(a, b) {
    if (a.length !== b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) return false;
    }
    return true;
  }

  function getStateClasses(result) {
    var classes = [];
    if (result.status === 'action') {
      classes.push('row--action');
    } else if (result.activityStatus === 'working') {
      classes.push('row--working');
    } else if (result.activityStatus === 'waiting') {
      classes.push('row--waiting');
    } else if (result.activityStatus === 'closed' || result.status !== 'live') {
      classes.push('row--closed');
    }
    if (result.healthStatus === 'error') {
      classes.push('row--error');
    } else if (result.healthStatus === 'stale') {
      classes.push('row--stale');
    }
    return classes;
  }

  function updateRowContent(row, result, index) {
    // Build target className and only apply if different to prevent blink
    var stateClasses = getStateClasses(result);
    var parts = ['row'].concat(stateClasses);
    if (index === selectedIndex) parts.push('row--selected');
    var targetClassName = parts.join(' ');
    if (row.className !== targetClassName) {
      row.className = targetClassName;
    }
    row.dataset.index = index;

    var titleEl = row.querySelector('.row__title');
    var newTitle = displayTitle(result);
    if (titleEl && titleEl.textContent !== newTitle) {
      titleEl.textContent = newTitle;
    }

    var pathEl = row.querySelector('.row__path');
    var newPath = formatSessionPath(result);
    if (pathEl && pathEl.textContent !== newPath) {
      pathEl.textContent = newPath;
    }

    var modelMetaEl = row.querySelector('.row__model-meta');
    var newModelMeta = formatModelMeta(result);
    if (modelMetaEl && modelMetaEl.textContent !== newModelMeta) {
      modelMetaEl.textContent = newModelMeta;
    }
  }

  function createRow(result, index) {
    var row = document.createElement('div');
    row.className = 'row';
    row.dataset.index = index;

    // State classes
    var stateClasses = getStateClasses(result);
    for (var i = 0; i < stateClasses.length; i++) {
      row.classList.add(stateClasses[i]);
    }

    if (index === selectedIndex) {
      row.classList.add('row--selected');
    }

    // Icon
    var iconSrc = toolIconURL(result.tool);
    if (iconSrc) {
      var icon = document.createElement('img');
      icon.className = 'row__icon';
      icon.src = iconSrc;
      icon.draggable = false;
      row.appendChild(icon);
    } else {
      var fallback = document.createElement('div');
      fallback.className = 'row__icon-fallback';
      fallback.textContent = (result.tool || '?')[0].toUpperCase();
      row.appendChild(fallback);
    }

    // Body
    var body = document.createElement('div');
    body.className = 'row__body';

    var title = document.createElement('span');
    title.className = 'row__title';
    title.textContent = displayTitle(result);
    body.appendChild(title);

    var metaRow = document.createElement('div');
    metaRow.className = 'row__meta-row';

    var modelMeta = document.createElement('span');
    modelMeta.className = 'row__model-meta';
    modelMeta.textContent = formatModelMeta(result);
    metaRow.appendChild(modelMeta);

    var path = document.createElement('span');
    path.className = 'row__path';
    path.textContent = formatSessionPath(result);
    metaRow.appendChild(path);
    body.appendChild(metaRow);

    row.appendChild(body);

    // Click handler
    row.addEventListener('click', function() {
      selectedIndex = index;
      updateSelection();
      updateActionHint();
      scheduleDwell();
    });

    row.addEventListener('dblclick', function() {
      selectedIndex = index;
      activateSelected();
    });

    row.addEventListener('mouseenter', function() {
      if (selectedIndex !== index) {
        selectedIndex = index;
        updateSelection();
        updateActionHint();
      }
      scheduleDwell();
    });

    return row;
  }

  function formatSessionPath(result) {
    return (result.project || '').trim();
  }

  function formatModelMeta(result) {
    var parts = [];
    parts.push(formatModelName(result));

    var compactTokens = formatTrustedTokenCount(result);
    if (compactTokens) {
      parts.push(compactTokens);
    }

    var relativeTime = ((result.relativeTime || '') + '').trim();
    if (relativeTime) {
      parts.push(relativeTime);
    }

    return parts.join(' \u00B7 ');
  }

  function formatModelName(result) {
    var model = ((result.effectiveModel || '') + '').trim();
    if (model) return model;
    var toolFamily = ((result.tool || '') + '').trim().toLowerCase();
    return toolFamily ? (toolFamily + ' \u00B7 model unknown') : 'unknown model';
  }

  function formatTrustedTokenCount(result) {
    if (!isTokenConfidenceTrustworthy(result)) return '';

    var usedEstimate = asPositiveNumber(result.contextUsedEstimate);
    if (usedEstimate !== null) return formatCompactCount(usedEstimate);

    var tokenCount = asPositiveNumber(result.tokenCount);
    if (tokenCount !== null) return formatCompactCount(tokenCount);
    return '';
  }

  function isTokenConfidenceTrustworthy(result) {
    var confidence = normalizeConfidence(result.contextConfidence);
    return confidence === 'high' || confidence === 'medium';
  }

  function normalizeConfidence(value) {
    return ((value || 'unknown') + '').toLowerCase();
  }

  function formatCompactCount(count) {
    if (count >= 1000000) {
      return trimTrailingZero((count / 1000000).toFixed(1)) + 'm';
    }
    if (count >= 1000) {
      return trimTrailingZero((count / 1000).toFixed(1)) + 'k';
    }
    return String(count);
  }

  function trimTrailingZero(value) {
    return value.replace(/\.0$/, '');
  }

  function asNumber(value) {
    return typeof value === 'number' && isFinite(value) ? value : null;
  }

  function asPositiveNumber(value) {
    var numeric = asNumber(value);
    return numeric !== null && numeric > 0 ? numeric : null;
  }

  function formatRunningTime(startedAtISO) {
    var start = new Date(startedAtISO);
    var now = new Date();
    var minutes = Math.floor((now - start) / 60000);
    if (minutes < 1) return 'running <1m';
    if (minutes < 60) return 'running ' + minutes + 'm';
    var hours = Math.floor(minutes / 60);
    var mins = minutes % 60;
    if (hours >= 3) return 'running ' + hours + 'h+';
    return 'running ' + hours + 'h ' + mins + 'm';
  }

  function formatTokens(count) {
    if (count >= 1000) {
      return (count / 1000).toFixed(1) + 'k tokens';
    }
    return count + ' tokens';
  }

  function lastPathComponent(path) {
    if (!path) return '';
    var parts = path.split('/');
    return parts[parts.length - 1] || '';
  }

  function toolIconURL(tool) {
    if (!tool) return null;
    var name = tool.toLowerCase();
    var assetMap = { claude: 'claude-icon', codex: 'codex-icon', gemini: 'gemini-icon' };
    var asset = assetMap[name];
    if (!asset) return null;
    if (iconBaseURL) return iconBaseURL + '/' + asset + '.png';
    return asset + '.png';
  }

  // --- Markdown Stripping ---

  function stripANSI(text) {
    if (!text) return '';
    // eslint-disable-next-line no-control-regex
    return text.replace(/\x1b\[[0-9;]*[A-Za-z]/g, '');
  }

  function stripSnippetMarkers(text) {
    return (text || '').replace(/>>>/g, '').replace(/<<</g, '');
  }

  function isGenericTitle(title, result) {
    if (!title || title === 'Untitled') return true;
    var pName = stripANSI(result.projectName || '');
    if (pName && title === pName) return true;
    return false;
  }

  function displayTitle(result) {
    // For FTS snippet matches: show the matched text
    if (result.snippet) {
      return stripSnippetMarkers(stripANSI(result.snippet));
    }
    var title = stripANSI(result.title || '');
    // Fallback to last user prompt ONLY when no smart title/summary exists
    if (result.lastUserPrompt && isGenericTitle(title, result)) {
      return stripANSI(result.lastUserPrompt);
    }
    return title;
  }

  function stripMarkdown(text) {
    if (!text) return '';
    return stripANSI(text)
      .replace(/#{1,6}\s*/g, '')         // headings
      .replace(/\*\*([^*]*)\*\*/g, '$1') // bold
      .replace(/\*([^*]*)\*/g, '$1')     // italic
      .replace(/__([^_]*)__/g, '$1')     // bold alt
      .replace(/_([^_]*)_/g, '$1')       // italic alt
      .replace(/`([^`]*)`/g, '$1')       // inline code
      .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1') // links
      .replace(/^[-*+]\s+/gm, '')        // list markers
      .replace(/^\d+\.\s+/gm, '')        // numbered lists
      .replace(/\s+/g, ' ')              // collapse whitespace
      .trim();
  }

  // --- Resize Notification ---

  function notifyResize() {
    requestAnimationFrame(function() {
      var height = panel.offsetHeight;
      if (isPreviewShowing && previewCard.classList.contains('preview--visible')) {
        var previewTop = parseFloat(previewCard.style.top || '0');
        if (!isFinite(previewTop)) previewTop = 0;
        var previewHeight = previewCard.scrollHeight || previewCard.offsetHeight || 0;
        height = Math.max(height, Math.ceil(previewTop + previewHeight + 16));
      }
      if (bridge) {
        bridge.postMessage({ type: 'resize', height: height });
      }
    });
  }

  // --- Block Cursor ---

  var cursorMeasure = document.createElement('span');
  var searchInputStyle = getComputedStyle(searchInput);
  cursorMeasure.style.cssText =
    'position:absolute;visibility:hidden;white-space:pre;' +
    'font-family:' + searchInputStyle.fontFamily + ';' +
    'font-size:' + searchInputStyle.fontSize + ';' +
    'font-weight:' + searchInputStyle.fontWeight + ';' +
    'line-height:' + searchInputStyle.lineHeight + ';' +
    'letter-spacing:' + searchInputStyle.letterSpacing + ';';
  document.body.appendChild(cursorMeasure);

  function updateBlockCursor() {
    var text = searchInput.value;
    var pos = searchInput.selectionStart || 0;
    cursorMeasure.textContent = text.slice(0, pos);
    blockCursor.style.left = cursorMeasure.offsetWidth + 'px';
  }

  searchInput.addEventListener('click', updateBlockCursor);
  searchInput.addEventListener('keyup', updateBlockCursor);
  searchInput.addEventListener('focus', function() {
    blockCursor.style.display = '';
    updateBlockCursor();
  });
  searchInput.addEventListener('blur', function() {
    blockCursor.style.display = 'none';
  });

  // --- Session Count ---

  function updateSessionCount() {
    if (!sessionCountEl) return;
    var query = searchInput.value.trim();
    if (!query) {
      var total = currentResults.filter(function(r) { return r.status !== 'action'; }).length;
      sessionCountEl.textContent = total > 0 ? total + ' sessions' : '';
    } else {
      var text = currentResults.length + ' matches';
      if (currentMode === 'live') text += ' · live only';
      sessionCountEl.textContent = text;
    }
  }

  // --- Expose to Swift for direct native key interception ---
  window.moveSelection = moveSelection;
  window.activateSelected = activateSelected;

  window.setMode = function(mode) {
    currentMode = mode;
    updateSessionCount();
  };
  window.handleTab = function() {
    // Tab toggles live/all mode only when a search query is active
    if (searchInput.value.trim() && bridge) {
      bridge.postMessage({ type: 'toggleMode' });
    }
  };

  // --- Init ---
  searchInput.focus();
  updateBlockCursor();

  window.updatePreview = function(previewJSON) {
    var data;
    try {
      data = typeof previewJSON === 'string' ? JSON.parse(previewJSON) : previewJSON;
    } catch (e) {
      return;
    }

    if (data && data.sessionId && data.lastActivityAt) {
      if (data.sessionId !== previewedSessionId || data.lastActivityAt !== previewedLastActivity) {
        return;
      }
    }

    previewCard.innerHTML = '';

    var exchanges = (data.exchanges || []).slice(-3);
    if (exchanges.length > 0) {
      var rounds = document.createElement('div');
      rounds.className = 'preview__rounds';

      for (var i = 0; i < exchanges.length; i++) {
        var ex = exchanges[i];
        var round = document.createElement('div');
        round.className = 'preview__round';
        if (ex.isError) {
          round.classList.add('preview__round--error');
        } else if (ex.role === 'user') {
          round.classList.add('preview__round--user');
        } else {
          round.classList.add('preview__round--assistant');
        }

        var role = document.createElement('div');
        role.className = 'preview__round-role';
        role.textContent = ex.isError ? 'Error' : (ex.role === 'user' ? 'You' : 'Assistant');
        round.appendChild(role);

        var body = document.createElement('div');
        body.className = 'preview__round-text';
        body.textContent = stripMarkdown(stripANSI(ex.text));
        round.appendChild(body);

        rounds.appendChild(round);
      }
      previewCard.appendChild(rounds);
    }

    var files = data.files || [];
    if (files.length > 0) {
      var filesSection = document.createElement('div');
      filesSection.className = 'preview__files';

      var filesLabel = document.createElement('div');
      filesLabel.className = 'preview__section-label';
      filesLabel.textContent = 'Files';
      filesSection.appendChild(filesLabel);

      var fileList = document.createElement('div');
      fileList.className = 'preview__file-list';
      for (var j = 0; j < files.length; j++) {
        var filePath = files[j];
        var parts = filePath.split('/');
        var basename = parts[parts.length - 1] || filePath;
        var dir = parts.slice(Math.max(0, parts.length - 3), parts.length - 1).join('/');

        var fileDiv = document.createElement('div');
        fileDiv.className = 'preview__file';
        fileDiv.textContent = basename;
        if (dir) {
          var dirSpan = document.createElement('span');
          dirSpan.className = 'preview__file-dir';
          dirSpan.textContent = dir;
          fileDiv.appendChild(dirSpan);
        }
        fileList.appendChild(fileDiv);
      }
      filesSection.appendChild(fileList);
      previewCard.appendChild(filesSection);
    }

    previewCard.style.maxHeight = '';

    // Position relative to selected row.
    // The native panel is resized from preview content, so the card can remain
    // fully visible without its own internal scrollbar.
    var rows = resultsContainer.querySelectorAll('.row');
    if (rows[selectedIndex]) {
      var rowRect = rows[selectedIndex].getBoundingClientRect();
      var panelRect = panel.getBoundingClientRect();
      var rowTop = rowRect.top - panelRect.top;
      previewCard.style.top = '';
      previewCard.style.bottom = '';
      previewCard.style.top = rowTop + 'px';
    }

    previewCard.classList.add('preview--visible');
    if (!isPreviewShowing) {
      isPreviewShowing = true;
      if (bridge) bridge.postMessage({ type: 'previewVisible', visible: true });
    }
    notifyResize();
  };
})();
