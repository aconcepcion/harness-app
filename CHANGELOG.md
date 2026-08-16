# Changelog

## 3.0.0 — 2026-08-16
First public release. Previously a private launcher (v2) built 2026-08-14.
- Attach-or-spawn `dsh web`; HTTP readiness; process-group stop with SIGTERM→SIGKILL escalation; one auto-restart then a real error sheet
- First-run guidance when dsh / Node are missing or unsupported; detects and repairs the npm-11 broken node-pty state
- Close = stop by default; opt-in Keep Server Running; no tray, no daemon
- Cross-origin navigation opens in the default browser
- Settings window; Profile submenu; Dock folder drop; About panel with dsh version, port, workspace, log
- Disclosed, off-able version checks for dsh (npm) and Harness (GitHub); "Update dsh…" runs visibly in Terminal
- Universal binary; `make test` + `make smoke`; Homebrew tap formula; bilingual README
