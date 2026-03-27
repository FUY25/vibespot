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

  let currentResults = [];
  let selectedIndex = 0;
  let debounceTimer = null;
  let iconBaseURL = '';

  // --- Swift → JS API ---

  window.updateResults = function(resultsJSON) {
    const newResults = typeof resultsJSON === 'string' ? JSON.parse(resultsJSON) : resultsJSON;
    currentResults = newResults;
    renderResults();
    if (currentResults.length > 0) {
      selectedIndex = Math.min(selectedIndex, currentResults.length - 1);
    } else {
      selectedIndex = 0;
    }
    updateSelection();
    updateActionHint();
    notifyResize();
  };

  window.setTheme = function(theme) {
    document.documentElement.setAttribute('data-theme', theme);
  };

  window.setGhostSuggestion = function(text) {
    updateGhostDisplay(text);
  };

  window.resetAndFocus = function() {
    searchInput.value = '';
    ghostSuggestion.textContent = '';
    selectedIndex = 0;
    currentResults = [];
    resultsContainer.innerHTML = '';
    searchInput.focus();
    notifyResize();
  };

  window.setIconBaseURL = function(url) {
    iconBaseURL = url;
  };

  // --- Search Input ---

  searchInput.addEventListener('input', function() {
    clearTimeout(debounceTimer);
    updateGhostFromInput();
    debounceTimer = setTimeout(function() {
      if (bridge) {
        bridge.postMessage({ type: 'search', query: searchInput.value });
      }
    }, 80);
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

  // --- Ghost Suggestions ---

  function updateGhostFromInput() {
    if (!searchInput.value) {
      ghostSuggestion.textContent = '';
      return;
    }
    // Ghost is updated from Swift via setGhostSuggestion
  }

  function updateGhostDisplay(suggestion) {
    if (!suggestion || !searchInput.value || !suggestion.toLowerCase().startsWith(searchInput.value.toLowerCase())) {
      ghostSuggestion.textContent = '';
      return;
    }
    // Show full suggestion but make typed portion invisible
    const typed = searchInput.value;
    const spacer = typed.replace(/./g, '\u00A0'); // invisible spacer matching typed width
    ghostSuggestion.textContent = spacer + suggestion.slice(typed.length);
  }

  function acceptGhostSuggestion() {
    var fullText = '';
    // Reconstruct full suggestion from ghost display
    if (ghostSuggestion.textContent && ghostSuggestion.textContent.trim()) {
      var suffix = ghostSuggestion.textContent.replace(/^\u00A0+/, '');
      fullText = searchInput.value + suffix;
    }
    if (!fullText || fullText === searchInput.value) return false;
    searchInput.value = fullText;
    ghostSuggestion.textContent = '';
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
    ghostSuggestion.textContent = '';
    if (bridge) {
      bridge.postMessage({ type: 'search', query: searchInput.value });
    }
  }

  // --- Action Hint ---

  function updateActionHint() {
    if (currentResults.length === 0) {
      actionHint.textContent = '';
      searchBarIcon.src = '';
      return;
    }
    var result = currentResults[selectedIndex] || currentResults[0];
    var iconSrc = toolIconURL(result.tool);
    searchBarIcon.src = iconSrc || '';

    if (result.status === 'action') {
      actionHint.textContent = '\u21A9 Launch';
    } else if (result.status === 'live') {
      actionHint.textContent = '\u21A9 Switch';
    } else {
      actionHint.textContent = '\u21A9 Resume \u21E5 History';
    }
  }

  // --- Result Rendering ---

  function renderResults() {
    resultsContainer.innerHTML = '';
    currentResults.forEach(function(result, index) {
      resultsContainer.appendChild(createRow(result, index));
    });
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
      activity.textContent = result.activityPreview;
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
      var status = document.createElement('div');
      status.className = 'row__status';

      var dot = document.createElement('span');
      dot.className = 'status-dot status-dot--green';
      status.appendChild(dot);

      var dots = document.createElement('div');
      dots.className = 'typing-dots';
      for (var i = 0; i < 3; i++) {
        var d = document.createElement('span');
        d.className = 'typing-dot';
        dots.appendChild(d);
      }
      status.appendChild(dots);
      return status;
    }

    if (result.activityStatus === 'waiting') {
      var status = document.createElement('div');
      status.className = 'row__status';

      var dot = document.createElement('span');
      dot.className = 'status-dot status-dot--amber';
      status.appendChild(dot);

      var text = document.createElement('span');
      text.className = 'row__status-text';
      text.textContent = 'AWAITING';
      status.appendChild(text);
      return status;
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

  // --- Resize Notification ---

  function notifyResize() {
    requestAnimationFrame(function() {
      var height = panel.offsetHeight;
      if (bridge) {
        bridge.postMessage({ type: 'resize', height: height });
      }
    });
  }

  // --- Init ---
  searchInput.focus();
})();
