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
  };

  window.setTheme = function(theme) {
    document.documentElement.setAttribute('data-theme', theme);
  };

  window.setGhostSuggestion = function(text) {
    // Ghost is now computed locally in JS — this is a no-op for backwards compat
  };

  window.resetAndFocus = function() {
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
        if (bridge) bridge.postMessage({ type: 'escape' });
        break;
      case 'Tab':
        e.preventDefault();
        if (!acceptGhostSuggestion()) {
          drillIntoSelectedHistory();
        }
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
    if (currentResults.length === 0) return;
    const result = currentResults[selectedIndex];
    if (result && bridge) {
      bridge.postMessage({ type: 'select', sessionId: result.sessionId, status: result.status, tool: result.tool });
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
      if (r.title && r.title.toLowerCase().startsWith(lowerQuery)) {
        suggestion = r.title;
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

  function updateRowContent(row, result, index) {
    // Update state classes
    row.className = 'row';
    if (result.status === 'action') {
      row.classList.add('row--action');
    } else if (result.activityStatus === 'working') {
      row.classList.add('row--working');
    } else if (result.activityStatus === 'waiting') {
      row.classList.add('row--waiting');
    } else if (result.activityStatus === 'closed' || result.status !== 'live') {
      row.classList.add('row--closed');
    }
    if (index === selectedIndex) {
      row.classList.add('row--selected');
    }
    row.dataset.index = index;

    // Update title
    var titleEl = row.querySelector('.row__title');
    if (titleEl && titleEl.textContent !== result.title) {
      titleEl.textContent = result.title;
    }

    // Update metadata
    var metaEl = row.querySelector('.row__meta');
    if (metaEl) {
      var newMeta = formatMetadata(result);
      if (metaEl.textContent !== newMeta) {
        metaEl.textContent = newMeta;
      }
    }
  }

  function createRow(result, index) {
    var row = document.createElement('div');
    row.className = 'row';
    row.dataset.index = index;

    // State classes
    if (result.status === 'action') {
      row.classList.add('row--action');
    } else if (result.activityStatus === 'working') {
      row.classList.add('row--working');
    } else if (result.activityStatus === 'waiting') {
      row.classList.add('row--waiting');
    } else if (result.activityStatus === 'closed' || result.status !== 'live') {
      row.classList.add('row--closed');
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

    // Header (title + status)
    var header = document.createElement('div');
    header.className = 'row__header';

    var title = document.createElement('span');
    title.className = 'row__title';
    title.textContent = result.title;
    header.appendChild(title);

    var status = createStatusElement(result);
    if (status) header.appendChild(status);

    body.appendChild(header);

    // Metadata
    var meta = document.createElement('span');
    meta.className = 'row__meta';
    meta.textContent = formatMetadata(result);
    body.appendChild(meta);

    // Activity
    if (result.activityPreview && result.activityStatus !== 'closed') {
      var activity = document.createElement('span');
      activity.className = 'row__activity';
      var kind = result.activityPreviewKind || 'tool';
      if (kind === 'assistant') {
        activity.classList.add('row__activity--assistant');
      } else {
        activity.classList.add('row__activity--tool');
      }
      activity.textContent = stripMarkdown(result.activityPreview);
      body.appendChild(activity);
    }

    row.appendChild(body);

    // Click handler
    row.addEventListener('click', function() {
      selectedIndex = index;
      updateSelection();
      updateActionHint();
    });

    row.addEventListener('dblclick', function() {
      selectedIndex = index;
      activateSelected();
    });

    return row;
  }

  function createStatusElement(result) {
    if (result.activityStatus === 'working') {
      var dots = document.createElement('div');
      dots.className = 'typing-dots';
      for (var i = 0; i < 3; i++) {
        var d = document.createElement('span');
        d.className = 'typing-dot';
        dots.appendChild(d);
      }
      return dots;
    }

    return null;
  }

  function formatMetadata(result) {
    var parts = [];
    if (result.relativeTime) parts.push(result.relativeTime);
    var projectName = result.projectName || lastPathComponent(result.project);
    if (projectName) {
      var branch = (result.gitBranch || '').trim();
      parts.push(branch ? projectName + ' / ' + branch : projectName);
    }
    if (result.tokenCount > 0) {
      parts.push(formatTokens(result.tokenCount));
    }
    return parts.join(' \u00B7 ');
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

  function stripMarkdown(text) {
    if (!text) return '';
    return text
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
      if (bridge) {
        bridge.postMessage({ type: 'resize', height: height });
      }
    });
  }

  // --- Block Cursor ---

  var cursorMeasure = document.createElement('span');
  cursorMeasure.style.cssText = 'position:absolute;visibility:hidden;white-space:pre;font-family:' + getComputedStyle(searchInput).fontFamily + ';font-size:24px;font-weight:500;letter-spacing:-0.02em;';
  document.body.appendChild(cursorMeasure);

  function updateBlockCursor() {
    var text = searchInput.value;
    var pos = searchInput.selectionStart || 0;
    cursorMeasure.textContent = text.slice(0, pos);
    blockCursor.style.left = cursorMeasure.offsetWidth + 'px';
  }

  searchInput.addEventListener('input', updateBlockCursor);
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
      sessionCountEl.textContent = currentResults.length + ' matches';
    }
  }

  // --- Expose to Swift for direct native key interception ---
  window.moveSelection = moveSelection;
  window.activateSelected = activateSelected;
  window.handleTab = function() {
    if (!acceptGhostSuggestion()) {
      drillIntoSelectedHistory();
    }
  };

  // --- Init ---
  searchInput.focus();
  updateBlockCursor();
})();
