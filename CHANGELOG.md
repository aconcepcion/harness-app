# Changelog

## 3.1.0 — 2026-08-18
- dsh ▸ Install from Git URL…: clone a preset / skill / plugin repository, tick what to install, and run it visibly in Terminal (presets → `$DSH_HOME/.agent-presets`, skills → `$DSH_HOME/skills`, plugins → `dsh plugin add`); anything already there is moved aside, never deleted; the exact script is shown before it runs
- dsh ▸ Presets / Skills submenus list what is installed (Reveal in Finder, Restart Server)
- dsh ▸ Reveal dsh Home, Reveal Sessions, Edit Profile Config… (`cordis.patch.yml`)
- Update dsh… / Repair Shell Tools… now target the npm prefix that owns the found dsh, so a login shell whose first `npm` is a different Node install no longer produces a second, shadowing dsh
- Server ▸ Prevent Sleep While Running (idle-sleep assertion; off by default; also in Settings)
- File choosers inside the web UI open a native panel (WKUIDelegate `runOpenPanel`)
- Privacy: Install from Git URL contacts only the host of the URL you paste, only when you click Fetch

## 3.0.0 — 2026-08-16
First public release. Previously a private launcher (v2) built 2026-08-14.
- Attach-or-spawn `dsh web`; HTTP readiness; process-group stop with SIGTERM→SIGKILL escalation; one auto-restart then a real error sheet
- First-run guidance when dsh / Node are missing or unsupported; detects and repairs the npm-11 broken node-pty state
- Close = stop by default; opt-in Keep Server Running; no tray, no daemon
- Cross-origin navigation opens in the default browser
- Settings window; Profile submenu; Dock folder drop; About panel with dsh version, port, workspace, log
- Disclosed, off-able version checks for dsh (npm) and Harness (GitHub); "Update dsh…" runs visibly in Terminal
- Universal binary; `make test` + `make smoke`; Homebrew tap formula; bilingual README
