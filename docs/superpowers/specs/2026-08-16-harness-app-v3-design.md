# Harness.app v3.0 — Design

**Date:** 2026-08-16 · **Status:** approved by Arnold (scope + revisions) · **Author:** Claude with Arnold

## 1. Purpose

Harness.app is a native macOS launcher for DeepSeek Harness (`dsh`). Double-click:
it starts the user's own `dsh web` server, shows the official web UI in a native
window, and stops the server when the window closes. It exists because the
alternatives are 500 MB Electron/Tauri bundles that pin their own copy of dsh,
hide to a tray, and ask users to trust a third-party binary with their API key
and shell.

Design stance (this is also the public pitch):

1. **BYO upstream, zero bundle.** Runs the `dsh` you installed with npm, against
   your `~/.dsh`. New upstream RC = one command; the app never needs updating.
2. **Native, tiny, auditable.** AppKit + WKWebView, ~600–700 lines of ObjC, one
   `clang` command, universal binary. No Chromium, no Rust toolchain, no bundled Node.
3. **Behaves like a document, not a service.** Close = stop (opt-in keep-alive,
   no tray, no daemon), no phone-home except two disclosed, off-able version checks.
4. **Never constrains dsh.** The harness's plugin self-modification ("update
   yourself to support markdown upload") must work exactly as from the CLI.

Non-goals for v3.0: tray icon, bundled Node, Windows/Linux, notarized binaries
(no Apple Developer membership — deliberate), Sparkle, generic "any local server"
mode (v4 roadmap; config is already command/port/name-driven).

## 2. User-visible behavior

### 2.1 Launch
- Resolve `dsh`: `DshPath` preference if set, else PATH lookup **through the
  user's login shell** (`/bin/zsh -lic 'command -v dsh'`, with `$SHELL`
  fallback) so Homebrew, nvm, volta, fnm installs all resolve.
- Capture the login-shell environment once (`$SHELL -lic env`) and use it as the
  server's environment (with `PATH` as captured). This is what lets dsh's own
  plugin installs find `pnpm`/`node`. `DSH_HOME` is passed through untouched.
- If a server already answers HTTP 200 on `http://127.0.0.1:<Port>/` → **attach
  mode**: use it, never stop it (matches a `dsh web` the user started in a terminal).
- Else spawn `dsh web --port <Port>` (plus `--profile <Profile>` when Profile ≠
  `web`) with cwd = Workspace, in its **own process group**, stdout/stderr → log.
- Show the placeholder ("Starting DeepSeek Harness…") and poll `/` every 400 ms
  until HTTP 200 (45 s budget), then load the UI.

### 2.2 First run / self-healing (unique to this app)
- `dsh` not found → dialog: plain-language explanation, the exact install
  command (Node ≥ 22.19 or ≥ 24 required; npm ≥ 11 needs
  `--allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs`),
  buttons **Open Terminal** (runs the command visibly) / **Copy Command** / **Quit**.
- Node missing or in the excluded gap (23.x, < 22.19) → the same dialog explains
  which Node to install (`brew install node`), then the dsh command.
- **Broken node-pty detection**: after resolving dsh, check that
  `<npm root -g>/@deepseek-ai/dsh/node_modules/node-pty/build/Release/pty.node`
  exists (path derived from the resolved dsh symlink target, not a hard-coded
  prefix). Missing → non-blocking notice: "dsh's shell tools are broken (npm
  skipped native builds). Repair…" → Terminal with the repair command, which is
  the same full install command as §2.6 (known-good; verified 2026-08-14).

### 2.3 Running
- Cross-origin navigation guard: any main-frame navigation or new window whose
  origin ≠ our origin opens in the default browser; in-app navigation denied.
- JS alert/confirm handled natively (existing).
- Child exit while running → restart once automatically (fresh log marker); a
  second death within 60 s → error sheet with last 30 log lines, **Open Log** /
  **Reload** / **Quit**. Never a blank window.
- Cmd-R reloads; window frame autosaved (existing).
- Dock: dropping a folder on the icon (or `open -a Harness.app <dir>`) sets
  Workspace for this launch and restarts the server there if one was spawned by
  us (attach mode: warn that the running server's workspace is unchanged).

### 2.4 Close / quit
- Window close, Cmd-Q, SIGTERM/SIGINT → graceful path.
- If **we** spawned the server and KeepServerRunning = NO → SIGTERM to the
  child's process group → wait up to 5 s → SIGKILL the group. Verified: no
  orphan `dsh`, `node-pty`, or `sandbox-exec` processes remain.
- If KeepServerRunning = YES → leave the server; next launch attaches instantly.
- Attach mode → never signals the server.

### 2.5 Menus
- **Harness** — About Harness.app (app version, dsh version, port, workspace,
  log path, mode attach/spawned) · Preferences… (Cmd-,) · Quit.
- **Edit** — standard (existing).
- **View** — Reload · Open in Browser.
- **Server** — Restart Server · Keep Server Running After Close (checkbox, bound
  to preference) · Profile ▸ (`web` + entries of `~/.dsh/profiles/`, radio,
  restarts server) · Open Log · Open Workspace in Terminal.
- **dsh** — Update dsh… · Check for dsh Updates Now · Repair Shell Tools…
- **Window** — Minimize · Zoom.

### 2.6 Updates (both disclosed in README, both off-able)
- **dsh**: at launch (background, ≤ 3 s timeout) compare `dsh --version` with
  `npm view @deepseek-ai/dsh version`. Newer → subtle notice (window subtitle
  "dsh 0.1.0-rc.7 available") + enabled menu item. **Update dsh…** opens
  Terminal.app running the exact command:
  `npm install -g --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs @deepseek-ai/dsh@latest`
  — visible, nothing hidden. The app cannot know when Terminal finishes, so it
  shows a non-modal notice: "When the update finishes, choose Server ▸ Restart
  Server." Profiles under `~/.dsh` are never touched (README notes
  `dsh plugin update`).
- **App**: at launch compare bundle version with the latest GitHub Release tag
  (`api.github.com/repos/aconcepcion/harness-app/releases/latest`, ≤ 3 s).
  Newer → notice pointing to `brew upgrade harness-app` / the release page. No
  auto-download.

### 2.7 Preferences window (Cmd-,)
Small single-pane window: Port (3080), Workspace (path + Choose…), Profile
(popup), Keep server running after close (checkbox), Check for dsh updates
(checkbox), Check for app updates (checkbox), dsh path (auto / Choose…), Open
Log button. Stored in `NSUserDefaults` (`com.arnoldoconcepcion.harness-app`),
so `defaults write` also works and is documented.

## 3. Architecture

Four ObjC units + a header of keys; one `clang` invocation builds them.

| Unit | Responsibility | Depends on |
|---|---|---|
| `main.m` — `AppDelegate` | window, WKWebView, menus, placeholder/error UI, Dock drop, Preferences window, wiring | HAServer, HAUpdater, HAEnvironment |
| `HAEnvironment.m/h` | resolve login-shell env, find `dsh`, Node/npm checks, node-pty check, derive npm root; pure functions returning structs/dicts | Foundation |
| `HAServer.m/h` | attach-or-spawn, readiness poll (HTTP), process-group stop with escalation, crash restart policy, delegate callbacks (ready / died / gaveUp) | HAEnvironment |
| `HAUpdater.m/h` | background dsh + app version checks, Terminal command runner (`osascript` → Terminal.app `do script`), repair command | HAEnvironment |
| `HAConfig.h` | preference keys + defaults registration | — |

Data flow: AppDelegate → HAEnvironment (once) → HAServer.start → callbacks →
webView load / error sheet. HAUpdater runs after first successful load.

Error handling principle: every failure surfaces as a native sheet with an
action (Open Terminal / Open Log / Reload / Quit); nothing fails silently; the
log always has the reason.

## 4. Repository layout

```
harness-app/
  Makefile            build (universal), install, icon, clean, smoke
  src/main.m src/HAServer.[mh] src/HAUpdater.[mh] src/HAEnvironment.[mh] src/HAConfig.h
  src/icon.m          renders AppIcon (whale emoji on DeepSeek-blue rounded rect)
  Resources/Info.plist.in
  scripts/smoke.sh    automated smoke tests (see §5)
  Formula/harness-app.rb   Homebrew formula (also mirrored to aconcepcion/homebrew-tap)
  .github/workflows/ci.yml   build + smoke on macOS runner on every push/PR
  README.md  README.zh.md  LICENSE (MIT)  CHANGELOG.md
  docs/superpowers/specs/…  docs/superpowers/plans/…
```

Bundle id `com.arnoldoconcepcion.harness-app`; app name **Harness.app**; version
3.0.0. Ad-hoc signed by `make install`; brew builds locally (no quarantine).
Icon: whale emoji (not DeepSeek's logo); README states "unofficial".

## 5. Testing

`scripts/smoke.sh` (runs locally and in CI, using a fake `dsh` shim in CI):
1. Cold start: no server → app spawns → HTTP 200 reached → window loads.
2. Attach: pre-started server → app attaches → app quit leaves it running.
3. Stop escalation: child that ignores SIGTERM is SIGKILLed; `pgrep` shows no
   orphans in the group.
4. Crash-restart: kill child once → auto-restart; kill twice within 60 s →
   error sheet path taken (asserted via log markers).
5. Keep-alive: preference on → quit leaves server; relaunch attaches.
6. Navigation guard: external URL → `NSWorkspace` open, not in-window (log marker).
7. dsh-missing path: PATH without dsh → first-run dialog path taken (headless
   assertion via a `--check-env` CLI flag that prints the resolution report).
8. Update check: fake npm returning a higher version → notice state set.

Manual checklist: menus, Preferences round-trip, Dock folder drop, About panel,
`lipo -info` shows arm64 + x86_64, `brew install --build-from-source` from the
tap on a clean shell.

## 6. Requirements checklist (acceptance)

- [ ] Runs user's npm dsh; no bundled copy; no custom profile injected; `DSH_HOME` respected
- [ ] dsh plugin self-modification works from inside the app (verify by asking the harness to add a plugin, then restart server)
- [ ] Close = stop by default; opt-in keep-alive; no orphans
- [ ] First-run guidance for missing dsh / bad Node / broken node-pty
- [ ] Never a blank window on failure
- [ ] Only network calls: localhost, npm registry (dsh check), api.github.com (app check) — both off-able and documented
- [ ] Universal binary; builds with one `clang` command; `brew install` from tap works
- [ ] Bilingual README with pitch, install, gotchas, comparison, roadmap

## 7. Open items deferred to launch-strategy phase
- Twitter/X thread + short write-up (bundling vs BYO, trust surface, close-means-stop)
- Homebrew-core / homebrew-cask submission once notability allows
- v4 idea: generic launcher for any local web tool
