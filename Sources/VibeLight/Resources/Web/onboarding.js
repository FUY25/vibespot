let state = null;

function post(message) {
  window.webkit?.messageHandlers?.onboardingBridge?.postMessage(message);
}

function renderDemoPane() {
  const mediaSources = {
    quickActivation: "onboarding-quick-activation.mp4",
    fastSwitch: "onboarding-fast-switch.mp4",
    searchSessions: "onboarding-search-sessions.mp4",
    startNewSession: "onboarding-start-new-session.mp4",
  };

  const mediaSource = mediaSources[state.cardID];
  const viewportContent = mediaSource
    ? `
        <video class="demo-placeholder__video" autoplay muted loop playsinline preload="auto">
          <source src="${escapeHtml(mediaSource)}" type="video/mp4">
        </video>
      `
    : `
        <div class="demo-placeholder__glass"></div>
        <div class="demo-placeholder__copy">${escapeHtml(state.rightPane.placeholderPrompt || "")}</div>
      `;

  return `
    <div class="pane pane--demo">
      <div class="demo-placeholder">
        <div class="demo-placeholder__viewport">
          ${viewportContent}
        </div>
      </div>
    </div>
  `;
}

function renderShortcutPane() {
  return `
    <div class="pane pane--compact">
      <div class="setting-block setting-block--shortcut">
        <div class="setting-block__value">${escapeHtml(state.hotkey)}</div>
        <div class="setting-actions">
          <button class="button button--secondary" onclick="post({ type: 'changeShortcut' })">${escapeHtml(state.rightPane.shortcutActions?.[0] || "")}</button>
          <button class="button button--secondary" onclick="post({ type: 'resetShortcut' })">${escapeHtml(state.rightPane.shortcutActions?.[1] || "")}</button>
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
    <div class="pane pane--compact">
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
    <div class="pane pane--compact">
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
    <div class="pane pane--compact">
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
  const shell = document.querySelector('.card-shell');
  const height = shell
    ? Math.ceil(shell.getBoundingClientRect().height)
    : document.documentElement.scrollHeight;
  post({ type: "resize", height });
}

function startDemoVideos() {
  const videos = document.querySelectorAll('.demo-placeholder__video');
  videos.forEach((video) => {
    if (typeof video.play === 'function') {
      const playPromise = video.play();
      if (playPromise && typeof playPromise.catch === 'function') {
        playPromise.catch(() => {});
      }
    }
    video.addEventListener('loadeddata', () => {
      if (typeof video.play === 'function') {
        const playPromise = video.play();
        if (playPromise && typeof playPromise.catch === 'function') {
          playPromise.catch(() => {});
        }
      }
    }, { once: true });
  });
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
  requestAnimationFrame(() => {
    startDemoVideos();
    notifyResize();
  });
};

window.addEventListener("load", notifyResize);
