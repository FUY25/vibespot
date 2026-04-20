let state = {
  step: 'welcome',
  launchAtLogin: true,
  launchAtLoginSupported: true,
  hotkey: 'Cmd+Shift+Space',
  checksRunning: false,
  codexFound: false,
  claudeFound: false,
  missingPaths: [],
  checkedPaths: [],
};

function post(message) {
  window.webkit?.messageHandlers?.onboardingBridge?.postMessage(message);
}

function renderWelcome() {
  return `
    <div class="frame">
      <div class="frame__glow frame__glow--left"></div>
      <div class="frame__glow frame__glow--right"></div>
      <section class="hero">
        <div>
          <div class="hero__meta">
            <span class="badge badge--soft">VibeSpot</span>
            <span class="badge">Native search app</span>
          </div>
          <h1>${escapeHtml(state.headline || '')}</h1>
          <p>${escapeHtml(state.body || '')}</p>
          <p class="caption">${escapeHtml(state.detail || '')}</p>
          <div class="hero__metrics">
            <div class="metric">
              <span class="metric__value">Live</span>
              <span class="metric__label">Switch back into active runs before the thread disappears.</span>
            </div>
            <div class="metric">
              <span class="metric__value">Local</span>
              <span class="metric__label">Indexes session files already on your machine.</span>
            </div>
          </div>
        </div>
        <div class="hero__cards">
          <div class="card card--demo">
            <div class="card__label">Demo</div>
            <div class="demo-shell">
              <div class="demo-shell__top">
                <span class="demo-shell__dot"></span>
                <span class="demo-shell__pill">task</span>
                <span class="demo-shell__status">14 matches</span>
              </div>
              <div class="demo-shell__list">
                <div class="demo-row demo-row--active">
                  <div class="demo-row__icon"></div>
                  <div class="demo-row__body">
                    <strong>resume the streaming parser fix</strong>
                    <span>live Codex session · updated now</span>
                  </div>
                </div>
                <div class="demo-row">
                  <div class="demo-row__icon"></div>
                  <div class="demo-row__body">
                    <strong>ship the preferences redesign</strong>
                    <span>Claude Code · 12 minutes ago</span>
                  </div>
                </div>
                <div class="demo-row">
                  <div class="demo-row__icon"></div>
                  <div class="demo-row__body">
                    <strong>draft the release README</strong>
                    <span>historical session · yesterday</span>
                  </div>
                </div>
              </div>
              <div class="demo-shell__footer">Demo GIF placeholder</div>
            </div>
            <div class="feature-list">
              <div class="feature"><span class="feature-dot"></span><span><strong>Switch live sessions fast</strong> with native Spotlight-like search.</span></div>
              <div class="feature"><span class="feature-dot"></span><span><strong>Search older threads</strong> when you need context, not just what is running now.</span></div>
              <div class="feature"><span class="feature-dot"></span><span><strong>Stay local</strong> by reading the session files already on your machine.</span></div>
            </div>
          </div>
        </div>
      </section>
      <div class="button-row">
        <div class="button-group">
          <button class="button-secondary" onclick="post({ type: 'quit' })">Quit</button>
        </div>
        <div class="button-group">
          <button class="button-primary" onclick="post({ type: 'continue' })">Continue</button>
        </div>
      </div>
    </div>
  `;
}

function renderSetup() {
  const codexStatus = state.codexFound ? 'Found' : 'Missing';
  const claudeStatus = state.claudeFound ? 'Found' : 'Missing';
  const pathStatus = (state.missingPaths || []).length === 0 ? 'Ready' : 'Needs attention';
  const launchStatus = state.launchAtLoginSupported ? 'Enabled in this build' : 'Packaged app only';

  return `
    <div class="frame">
      <div class="frame__glow frame__glow--left"></div>
      <div class="frame__glow frame__glow--right"></div>
      <section class="hero">
        <div>
          <div class="hero__meta">
            <span class="badge badge--soft">Setup</span>
            <span class="badge">Default shortcut: ${escapeHtml(state.hotkey)}</span>
          </div>
          <h1>${escapeHtml(state.headline || '')}</h1>
          <p>${escapeHtml(state.body || '')}</p>
          <p class="caption">${escapeHtml(state.detail || '')}</p>
        </div>
        <div class="hero__cards">
          <div class="card">
            <div class="card__label">Readiness</div>
            <div class="checks">
              <div class="check-pill">
                <span class="check-pill__label">Launch at login</span>
                <span class="check-pill__status ${state.launchAtLoginSupported ? 'ok' : 'neutral'}">${launchStatus}</span>
              </div>
              <div class="check-pill">
                <span class="check-pill__label">Codex helper</span>
                <span class="check-pill__status ${state.codexFound ? 'ok' : 'warn'}">${codexStatus}</span>
              </div>
              <div class="check-pill">
                <span class="check-pill__label">Claude helper</span>
                <span class="check-pill__status ${state.claudeFound ? 'ok' : 'warn'}">${claudeStatus}</span>
              </div>
              <div class="check-pill">
                <span class="check-pill__label">Session paths</span>
                <span class="check-pill__status ${(state.missingPaths || []).length === 0 ? 'ok' : 'warn'}">${pathStatus}</span>
              </div>
            </div>
            <p class="caption">${state.checksRunning ? 'Running checks...' : describePaths()}</p>
          </div>
        </div>
      </section>

      <section class="panel">
        <div class="settings-grid">
          <div class="settings-card">
            <h2>System</h2>
            <p>Keep the initial setup small: one shortcut, one launch preference, one quick readiness check.</p>
            <div class="settings-row">
              <div class="settings-row__text">
                <h3>Launch at login</h3>
                <p>${state.launchAtLoginSupported ? 'Open VibeSpot automatically when you sign in.' : 'This only works from a packaged app build, not while running from source.'}</p>
              </div>
              <div
                class="toggle ${state.launchAtLogin ? 'is-on' : ''} ${state.launchAtLoginSupported ? '' : 'is-disabled'}"
                onclick="toggleLaunchAtLogin()"
              ></div>
            </div>
            <div class="settings-row">
              <div class="settings-row__text">
                <h3>Shortcut</h3>
                <p>Use the default or pick a different global shortcut.</p>
              </div>
              <div class="shortcut-box">
                <span class="shortcut-chip">${escapeHtml(state.hotkey)}</span>
                <button class="button-secondary" onclick="post({ type: 'changeShortcut' })">Change shortcut</button>
                <button class="button-link" onclick="post({ type: 'resetShortcut' })">Reset</button>
              </div>
            </div>
            <div class="settings-row">
              <div class="settings-row__text">
                <h3>Environment checks</h3>
                <p>Verify your local files and helper binaries before the first search.</p>
              </div>
              <button class="button-secondary" onclick="post({ type: 'runChecks' })">${state.checksRunning ? 'Checking...' : 'Run checks again'}</button>
            </div>
          </div>
        </div>
      </section>

      <div class="button-row">
        <div class="button-group">
          <button class="button-secondary" onclick="post({ type: 'back' })">Back</button>
        </div>
        <div class="button-group">
          <button class="button-primary" onclick="post({ type: 'finish' })">Finish</button>
        </div>
      </div>
    </div>
  `;
}

function describePaths() {
  const missing = state.missingPaths || [];
  if (missing.length === 0) {
    return 'All expected local session paths are reachable.';
  }
  return `Missing: ${missing.join(', ')}`;
}

function escapeHtml(text) {
  return String(text)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function toggleLaunchAtLogin() {
  if (!state.launchAtLoginSupported) {
    return;
  }
  const nextValue = !state.launchAtLogin;
  post({ type: 'setLaunchAtLogin', enabled: nextValue });
}

function notifyResize() {
  const height = document.documentElement.scrollHeight;
  post({ type: 'resize', height });
}

window.updateOnboardingState = function updateOnboardingState(stateJSON) {
  state = JSON.parse(stateJSON);
  document.getElementById('app').innerHTML = state.step === 'setup' ? renderSetup() : renderWelcome();
  requestAnimationFrame(notifyResize);
};

window.addEventListener('load', notifyResize);
