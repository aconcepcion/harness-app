# Harness.app

**A native macOS launcher for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`dsh`). Runs the dsh *you* installed, in a real Mac window, and stops it when you close the window. ~1,200 lines of Objective-C. No Electron, no bundled copy of dsh, no tray daemon.**

Double-click → it starts *your* `dsh web` → shows the official UI in a native window → stops the server when you close it.

> Unofficial community project. Not affiliated with DeepSeek. `dsh` is theirs; this is just a window and a process manager.

[中文](README.zh.md) · [For AI agents ↓](#for-ai-agents) · [Install ↓](#install)

## Why I built this

I installed dsh the day it came out. It's excellent, and it's a terminal command that opens a browser tab. That's fine for an hour and annoying for a week: the tab gets lost among fifty others, the server keeps running in a terminal you forgot about, and you can't just click a Dock icon like every other app you use all day.

So I wrote a small native launcher for myself. Then I looked at what everyone else had done, because within three days there were *nine* "DeepSeek Harness Desktop" repos. Almost all of them make the same choices: wrap the web UI in Electron or Tauri, **ship their own copy of dsh inside the app**, hide to the menu-bar tray when you close the window, and hand you a 300–500 MB binary to install. The most polished one is genuinely good work — but it's a *product*, with its own release schedule, its own update servers, and its own copy of dsh that lags upstream.

That's backwards for a tool that is changing weekly. dsh is a developer preview. New release candidates land constantly, and one of dsh's best features is that **it can modify itself** — ask it to support a file type it doesn't handle and it installs the plugin into its own profile. A wrapper that pins its own dsh, or layers its own profile on top, gets in the way of exactly that.

Harness.app takes the opposite stance on every point, on purpose:

| | Harness.app | Typical wrapper |
|---|---|---|
| Which dsh runs | **The one you installed with npm.** New upstream RC = one command; the app never needs updating | A pinned copy inside the bundle; you wait for their release |
| Size / stack | <400 KB universal binary, AppKit + the system WebKit, one `clang` command | 300–500 MB Electron/Tauri, bundled Chromium or Rust toolchain |
| Trust | Read all of it in half an hour; `brew` compiles it on *your* machine | A notarized (or not) binary from a stranger |
| Close the window | **Stops the server** (opt-in keep-alive; no tray, no daemon) | Hides to a tray; server keeps running |
| Network | localhost + two disclosed, off-able version checks | Update servers, sometimes counted-download endpoints |
| dsh's plugin self-modification | Untouched — same `~/.dsh`, same profiles, your login-shell PATH | Often a custom profile layered on top |

If you want a tray app with a plugin marketplace, use one of the others — they're good at that. If you want your own dsh in a native window that behaves like a document, this is it.

## Why those things are good (if you're not a Mac developer)

- **"Runs your own npm dsh"** — dsh is installed by npm, Node's package manager. Harness doesn't carry a copy; it launches the one on your machine. So when DeepSeek ships a new version, you type one command and you're on it — Harness never has to release anything. You are never waiting on a middleman.
- **"~1,200 lines of Objective-C, no Electron"** — Electron apps bundle an entire Chrome browser to draw their window (that's why they're 300–500 MB and use a lot of memory). Harness uses the browser engine already built into macOS, through Apple's own AppKit. Result: a sub-400 KB app that opens in about a second, feels native, and is small enough that a curious person can read *all* of it — there is nowhere for anything sneaky to hide. Homebrew even compiles it from source on your own Mac.
- **"No tray, no daemon"** — many desktop wrappers keep running in the menu bar after you close the window, with the server still going. Harness behaves like a document: close the window, it's gone, nothing left running. (If you *want* the server to stay up between sessions, there's a checkbox for that — off by default.)
- **"Two disclosed, off-able version checks"** — the only network traffic besides talking to dsh on your own machine is a version lookup on npm (for dsh) and on GitHub (for Harness). Both are visible in Settings and can be switched off. No telemetry, no phone-home.
- **"Never constrains dsh"** — the app doesn't put itself between you and dsh's plugin system. Your `~/.dsh`, your profiles, your PATH. Whatever dsh can do from the terminal, it can do inside Harness.

## Install

**Homebrew (compiles locally, ~2 s, no Gatekeeper prompt):**
```sh
brew install aconcepcion/tap/harness-app
cp -R "$(brew --prefix)/opt/harness-app/Harness.app" /Applications/
```
**Or from source:**
```sh
git clone https://github.com/aconcepcion/harness-app && cd harness-app && make install
```
Requirements: macOS 13+, Xcode Command Line Tools (`xcode-select --install`), and `dsh` installed via npm — **or not**: if dsh isn't found, Harness shows you the exact install command and opens Terminal for you.

## First run

1. Open Harness. It finds `dsh` through your login shell (Homebrew, nvm, volta, fnm all work).
2. If dsh is missing, or Node is the wrong version, or dsh's shell tools are broken (see Gotchas), it tells you exactly what to run — visibly, in Terminal. Nothing runs hidden.
3. The official dsh web UI loads. Enter your API key in Settings → Models as usual.
4. Close the window: the server it started stops. (Turn on **Server ▸ Keep Server Running After Close** if you'd rather it stayed; the next launch reattaches instantly.)

## For AI agents

If you are an AI agent (Claude Code, Codex, Cursor, Copilot, Hermes, dsh itself…) asked to install or operate Harness.app on a Mac, follow this section literally. Every step has a verifiable outcome.

**Preconditions (check, don't assume)**
```sh
sw_vers -productVersion            # need 13.0 or newer
xcode-select -p                    # must print a path; else: xcode-select --install
which brew                         # optional; enables the one-line install
which dsh && dsh --version         # optional; Harness will guide the user if missing
node --version                     # dsh needs ^22.19.0 || >=24.0.0 (23.x is NOT supported)
```

**Install (choose one)**
```sh
# A. Homebrew tap — builds locally, no Gatekeeper prompt
brew install aconcepcion/tap/harness-app && cp -R "$(brew --prefix)/opt/harness-app/Harness.app" /Applications/
# B. From source
git clone https://github.com/aconcepcion/harness-app ~/harness-app && make -C ~/harness-app install
```

**Verify**
```sh
/Applications/Harness.app/Contents/MacOS/Harness --version      # prints 3.0.0
/Applications/Harness.app/Contents/MacOS/Harness --check-env     # exit 0 = dsh found; exit 1 = dsh missing (report shows why)
open -a Harness                                                  # launches; UI on http://127.0.0.1:3080 within ~5 s
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3080/  # 200 when ready
```

**If `--check-env` reports `dsh: not found`, install dsh (this exact command; the `--allow-scripts` part is mandatory with npm ≥ 11):**
```sh
npm install -g --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs @deepseek-ai/dsh@latest
```
If it reports `node-pty: BROKEN`, run the same command (it repairs the missing macOS prebuild).

**Configure (all optional; take effect on Server ▸ Restart Server or next launch)**
```sh
defaults write com.arnoldoconcepcion.harness-app Port -int 3080
defaults write com.arnoldoconcepcion.harness-app Workspace "$HOME/projects"
defaults write com.arnoldoconcepcion.harness-app KeepServerRunning -bool NO
defaults write com.arnoldoconcepcion.harness-app CheckForDshUpdates -bool YES
defaults write com.arnoldoconcepcion.harness-app CheckForAppUpdates -bool YES
open -a Harness "$HOME/projects"        # or: launch with a workspace folder
```

**Operate / diagnose**
- Log: `~/Library/Logs/Harness.app/harness-app.log` (Harness lines are prefixed `[harness-app …]`; dsh's own output follows).
- Quit = `osascript -e 'quit app "Harness"'` or SIGTERM to the `Harness` process; the dsh server it spawned stops with it unless `KeepServerRunning` is YES.
- Harness never modifies `~/.dsh`, never installs its own profile, and passes the user's login-shell environment (`$SHELL -ilc env`) to dsh. Anything dsh can do from a terminal, it can do here.
- Uninstall: `rm -rf /Applications/Harness.app; defaults delete com.arnoldoconcepcion.harness-app` (and `brew uninstall harness-app` if installed via tap). dsh itself is untouched.

Contributing agents: see [`AGENTS.md`](AGENTS.md) for build, test and code conventions.

## What it actually does

- **Attach or spawn.** If something already answers on the port (e.g. a `dsh web` you started in a terminal), Harness attaches and never kills it. Otherwise it spawns `dsh web --port <Port>` in your workspace, in its own process group, logging to `~/Library/Logs/Harness.app/`.
- **Readiness = HTTP 200**, not "port open". You see a placeholder until the UI is really there.
- **Stop = SIGTERM to the process group → 5 s → SIGKILL.** No orphaned `node-pty` shells or `sandbox-exec` children.
- **Crash policy.** If dsh dies, Harness restarts it once; if it dies again within a minute you get an error sheet with the log tail — never a blank window.
- **Navigation guard.** Anything not on `127.0.0.1` opens in your default browser.
- **Dock drop.** Drag a folder onto the icon (or `open -a Harness ~/project`) to use it as the workspace.
- **Profiles.** Server ▸ Profile lists `~/.dsh/profiles/`; switching restarts the server. Harness never injects a profile of its own.
- **Update dsh… / Repair Shell Tools…** open Terminal running the exact command below. Harness can't tell when Terminal is done, so it just reminds you: Server ▸ Restart Server.

## Updating dsh

```sh
npm install -g --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs @deepseek-ai/dsh@latest
```
That's the whole story: dsh is npm's, not ours. Harness checks npm at launch and shows "dsh x.y.z available" in the window subtitle when there is one. Your `~/.dsh` profiles and plugins are never touched (run `dsh plugin update` if a new RC needs it).

## Settings

Cmd-, or `defaults write com.arnoldoconcepcion.harness-app <Key> <value>`:

| Key | Default | Meaning |
|---|---|---|
| `Port` | `3080` | Port to attach to / start on |
| `Workspace` | `$HOME` | cwd for the spawned `dsh web` |
| `Profile` | `web` | `dsh web` for `web`, else `dsh --profile <name>` |
| `DshPath` | (auto) | Override the login-shell PATH lookup |
| `KeepServerRunning` | `NO` | Leave the server running after close |
| `CheckForDshUpdates` | `YES` | `npm view @deepseek-ai/dsh version` at launch |
| `CheckForAppUpdates` | `YES` | GitHub latest-release check at launch |

Port/workspace/profile/dsh path apply on **Server ▸ Restart Server**.

## Privacy & network

Harness talks to exactly three places: `127.0.0.1` (dsh), `registry.npmjs.org` via `npm view` (dsh update check), and `api.github.com` (its own update check). Both checks are visible in Settings and can be turned off. It captures your login-shell environment once at launch (`$SHELL -ilc env`, with `HA_ENV_CAPTURE=1` set so your rc files can skip slow work) and hands that environment to dsh — nothing is sent anywhere.

## Gotchas this app knows about

- **npm ≥ 11 skips install scripts by default**, so a plain `npm install -g @deepseek-ai/dsh` leaves node-pty without its macOS prebuild → dsh's shell/PTY tools are silently dead. Hence `--allow-scripts=…` in every command above. Harness detects the broken state (`node_modules/node-pty/prebuilds/darwin-<arch>/` missing) and offers the repair.
- **Node 23.x is in the excluded gap** of dsh's `engines` (`^22.19.0 || >=24.0.0`). Harness tells you if your Node is unsupported.
- **dsh is a developer preview** (rc.x); RCs can break things. That's precisely why Harness doesn't pin one — you decide when to update.

## Building & testing

```sh
make            # universal Harness.app in build/
make test       # unit tests (env discovery, semver, server lifecycle with a fake dsh)
make smoke      # end-to-end: cold start, attach, keep-alive, SIGKILL escalation
make install    # copy to /Applications (ad-hoc signed)
```
Only Command Line Tools are needed. There is no notarized download on purpose: a locally built app has no quarantine flag, and nothing about a 400 KB launcher justifies asking you to trust a binary.

## Roadmap / non-goals

- Possible v4: a generic mode for any local web tool (Open WebUI, ComfyUI, …) — the config is already command/port/name-driven.
- Not planned: tray icon, bundled Node, Windows/Linux, auto-download updates.

## License

MIT © Arnoldo Concepcion. DeepSeek's name and logo belong to DeepSeek.
