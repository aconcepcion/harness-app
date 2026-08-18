# AGENTS.md — working on Harness.app

This file is for AI agents (and humans) contributing to this repository. For *installing or using* Harness.app, read the "For AI agents" section of [README.md](README.md#for-ai-agents) instead.

## What this is
A native macOS launcher for DeepSeek Harness (`dsh`): Objective-C, AppKit + WKWebView, ~1,600 lines, one `clang` invocation. It launches the user's own npm-installed `dsh web`, shows the UI, and stops the server on close; since 3.1 it also installs presets/skills/plugins the user names (visibly, in Terminal) and lists what is installed. Design specs: `docs/superpowers/specs/2026-08-16-harness-app-v3-design.md`, `docs/superpowers/specs/2026-08-18-harness-app-v3.1-design.md`. Plans: `docs/superpowers/plans/2026-08-16-harness-app-v3.md`, `docs/superpowers/plans/2026-08-18-harness-app-v3.1.md`.

## Layout
- `src/main.m` — AppDelegate: window, WKWebView (incl. file-chooser delegate), menus, sheets, Settings, Dock drop, Install-from-Git flow, `--check-env`
- `src/HAEnvironment.[mh]` — login-shell env capture, dsh/Node discovery, node-pty diagnosis (pure C helpers, testable)
- `src/HAServer.[mh]` — attach-or-spawn, HTTP readiness, process-group stop with escalation, one auto-restart
- `src/HAUpdater.[mh]` — semver compare, npm/GitHub version checks, visible Terminal runner
- `src/HAInstaller.[mh]` — clone target for a Git URL, preset/skill/plugin detection in a clone, install-script generation, installed listings (pure, testable)
- `src/HASleepGuard.[mh]` — IOPM idle-sleep assertion (Prevent Sleep While Running)
- `src/HAPreferencesWindow.[mh]` — Settings window, `HAAvailableProfiles()`
- `src/HAConfig.h` — preference keys, version, defaults
- `tests/` — hand-rolled runner (`HATest.h`), `fakedsh.c` (fake HTTP server standing in for `dsh web`), `test_*.m` (environment, server, updater, installer, sleepguard)
- `scripts/smoke.sh` — end-to-end scenarios against the built app; `scripts/make-icon.sh` — icns pipeline

## Build / test (Command Line Tools only; no Xcode project)
```sh
make            # universal build/Harness.app
make test       # unit tests; must print "0 failures" for every test binary
make smoke      # end-to-end; must print "smoke: 0 failure(s)"; restores the user's preferences afterwards
make install    # /Applications/Harness.app (ad-hoc signed)
```
CI (`.github/workflows/ci.yml`) runs all three on macos-latest; keep them green.

## Conventions
- Keep it small and readable end to end; prefer a few lines in the right unit over a new dependency. No third-party frameworks, no Swift (CLT `swiftc` breaks single-file AppKit builds on some machines).
- Never bundle dsh, never inject a profile, always pass the user's login-shell environment to dsh, and the app process never writes into `~/.dsh` — anything that must (Install from Git URL) runs as a script the user has read, visibly in Terminal (`bash -ex`), and moves existing items aside rather than deleting them. These are product invariants, not preferences.
- Every failure surfaces as a sheet with an action (Retry / Open Log / Quit). Never a blank window.
- The only network calls are localhost, `npm view` (dsh check), `api.github.com` (app check) — both off-able — and, only on the user's explicit Fetch, `git clone` of the URL they pasted. Adding another requires a README "Privacy & network" update.
- The dsh install flags live in one place (`HA_DSH_INSTALL_ARGS` in `HAEnvironment.m`); `HADshInstallCommand` and `HADshInstallCommandForPackageDir()` are composed from it. Do not duplicate them.
- TDD for anything below the UI: write the failing `tests/test_*.m` case first. UI behaviour is verified via `scripts/smoke.sh` and the manual checklist in the plan (Task 10).
- Preference keys are declared only in `HAConfig.h`; the README "Settings" table must match.
- Version lives in `HAConfig.h` (`HAAppVersion`) and `Makefile` (`VERSION`); bump both, add a CHANGELOG entry, tag `vX.Y.Z`, then update `Formula/harness-app.rb` (url + sha256) and mirror it to `aconcepcion/homebrew-tap`.
- Commit messages: conventional prefixes (`feat:`, `fix:`, `docs:`, `test:`, `ci:`, `build:`).
