let state = null;

function post(message) {
  window.webkit?.messageHandlers?.onboardingBridge?.postMessage(message);
}

function renderDemoPane() {
  const chipSets = {
    quickActivation: [state.hotkey, "Panel", "Live state"],
    fastSwitch: ["Enter", "Jump back", "Current session"],
    searchSessions: ["Search", "Tab", "Enter"],
    startNewSession: ["new claude", "new codex", "Launch"],
  };

  const chips = (chipSets[state.cardID] || []).map((chip) => `<span class="demo-chip">${escapeHtml(chip)}</span>`).join("");

  return `
    <div class="pane pane--demo">
      <div class="pane__chrome">${escapeHtml(state.rightPane.chromeLabel)}</div>
      <div class="demo-placeholder">
        <div class="demo-placeholder__viewport">
          <div class="demo-placeholder__glass"></div>
          <div class="demo-placeholder__copy">${escapeHtml(state.rightPane.placeholderPrompt || "")}</div>
        </div>
        <div class="demo-placeholder__footer">
          <span class="demo-placeholder__label">${escapeHtml(state.rightPane.placeholderLabel || "")}</span>
          <div class="demo-placeholder__chips">${chips}</div>
        </div>
      </div>
    </div>
  `;
}

function renderShortcutPane() {
  return `
    <div class="pane">
      <div class="pane__chrome">${escapeHtml(state.rightPane.chromeLabel)}</div>
      <div class="setting-block">
        <div class="setting-block__value">${escapeHtml(state.hotkey)}</div>
        <div class="setting-actions">
          <button class="button button--secondary" onclick="post({ type: 'changeShortcut' })">${escapeHtml(state.rightPane.shortcutActions?.[0] || "")}</button>
          <button class="button button--ghost" onclick="post({ type: 'resetShortcut' })">${escapeHtml(state.rightPane.shortcutActions?.[1] || "")}</button>
        </div>
      </div>
    </div>
  `;
}

function renderAccessPane() {
  const statuses = (state.rightPane.accessStatuses || []).map((item) => `
    <div class="status-row">
      <span class="status-row__label">${escapeHtml(item.label)}</span>
      <span class="status-pill status-pill--${escapeHtml(item.tone)}">${escapeHtml(item.value)}</span>
    </div>
  `).join("");

  return `
    <div class="pane">
      <div class="pane__chrome">${escapeHtml(state.rightPane.chromeLabel)}</div>
      <div class="setting-block setting-block--stacked">
        <div class="status-list">${statuses}</div>
        <button class="button button--secondary" onclick="post({ type: 'runChecks' })">${escapeHtml(state.rightPane.accessActionTitle || "")}</button>
      </div>
    </div>
  `;
}

function renderTerminalPane() {
  const terminalStatus = state.rightPane.terminalStatus;
  return `
    <div class="pane">
      <div class="pane__chrome">${escapeHtml(state.rightPane.chromeLabel)}</div>
      <div class="setting-block setting-block--stacked">
        <div class="status-row status-row--single">
          <span class="status-row__label">${escapeHtml(terminalStatus?.label || "")}</span>
          <span class="status-pill status-pill--${escapeHtml(terminalStatus?.tone || "neutral")}">${escapeHtml(terminalStatus?.value || "")}</span>
        </div>
        <button class="button button--secondary" onclick="post({ type: 'runTerminalCheck' })">${escapeHtml(state.rightPane.terminalActionTitle || "")}</button>
      </div>
    </div>
  `;
}

function renderQuickSetupPane() {
  const disabledClass = state.rightPane.launchAtLoginSupportedLabel ? "toggle--disabled" : "";
  const supportText = state.rightPane.launchAtLoginSupportedLabel
    ? `<div class="setting-note">${escapeHtml(state.rightPane.launchAtLoginSupportedLabel)}</div>`
    : "";

  return `
    <div class="pane">
      <div class="pane__chrome">${escapeHtml(state.rightPane.chromeLabel)}</div>
      <div class="setting-block setting-block--stacked">
        <div class="status-row status-row--single">
          <span class="status-row__label">${escapeHtml(state.rightPane.launchAtLoginLabel || "")}</span>
          <button class="toggle ${state.launchAtLogin ? 'toggle--on' : ''} ${disabledClass}" onclick="toggleLaunchAtLogin()">
            <span class="toggle__knob"></span>
          </button>
        </div>
        ${supportText}
      </div>
    </div>
  `;
}

function renderRightPane() {
  switch (state.rightPane.kind) {
    case "shortcut":
      return renderShortcutPane();
    case "access":
      return renderAccessPane();
    case "terminal":
      return renderTerminalPane();
    case "quickSetup":
      return renderQuickSetupPane();
    case "demo":
    default:
      return renderDemoPane();
  }
}

function renderCard() {
  const primaryType = state.cardID === "quickSetup" ? "finish" : "next";
  return `
    <div class="frame">
      <div class="card-shell">
        <div class="card-shell__header">
          <button class="text-button" onclick="post({ type: 'quit' })">${escapeHtml(state.quitLabel)}</button>
          <div class="progress">${escapeHtml(state.progressLabel)}</div>
        </div>
        <div class="card-shell__body">
          <section class="copy-pane">
            <p class="copy-pane__sentence">${escapeHtml(state.sentence)}</p>
          </section>
          <section class="visual-pane">
            ${renderRightPane()}
          </section>
        </div>
        <div class="card-shell__footer">
          <button class="button button--ghost ${state.canGoBack ? '' : 'button--hidden'}" onclick="post({ type: 'back' })">${escapeHtml(state.backLabel)}</button>
          <button
            class="button button--primary"
            ${primaryType === "finish" && !state.canFinish ? "disabled" : ""}
            onclick="post({ type: '${primaryType}' })"
          >${escapeHtml(state.primaryActionTitle)}</button>
        </div>
      </div>
    </div>
  `;
}

function toggleLaunchAtLogin() {
  if (state.rightPane.launchAtLoginSupportedLabel) {
    return;
  }
  post({ type: "setLaunchAtLogin", enabled: !state.launchAtLogin });
}

function notifyResize() {
  const height = document.documentElement.scrollHeight;
  post({ type: "resize", height });
}

function escapeHtml(text) {
  return String(text ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

window.updateOnboardingState = function updateOnboardingState(stateJSON) {
  state = JSON.parse(stateJSON);
  document.documentElement.lang = state.languageCode || "en";
  document.getElementById("app").innerHTML = renderCard();
  requestAnimationFrame(notifyResize);
};

window.addEventListener("load", notifyResize);
