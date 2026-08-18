# Harness.app v3.1 — Design

**Date:** 2026-08-18 · **Status:** scope approved by Arnold; built as v3.1.0 before the public launch

## 1. Why v3.1

Within five days of dsh's release the community's energy moved *inside* the
harness: two-phase "anchored" agent presets (dsh-anchored-standard, 3.5k★),
runtime routers (dsh-routing-suite, 5.7k★), and cognition-suite skills
(J-Space, 1.5k★). All of them install the same way — copy a directory into
`~/.dsh/.agent-presets/` or `~/.dsh/skills/`, or `dsh plugin add` a package —
then restart dsh and pick the preset in a new session.

Harness.app deliberately refuses to *own* that layer (no bundled presets, no
curated marketplace — upstream rc.7 is already growing plugin management into
the UI). v3.1 makes it the best **native host** for that ecosystem instead:
install what the user pastes, show what is installed, open the right folders
and files, keep the Mac awake for long runs, and fix two gaps found while
verifying rc.7. Six changes, one release, no change of stance.

## 2. Scope (all six ship together as 3.1.0)

| # | Change | Kind |
|---|--------|------|
| 1 | **dsh ▸ Install from Git URL…** — clone a repo the user names, detect presets / skills / plugins, install the ones they tick, visibly in Terminal | new flow |
| 2 | **dsh ▸ Presets ▸ / Skills ▸** — read-only listing of what is installed, Reveal in Finder, Restart Server | new menus |
| 3 | **dsh ▸ Reveal dsh Home / Reveal Sessions / Edit Profile Config…** | new menu items |
| 4 | **Update dsh… / Repair Shell Tools… use the npm that owns the found dsh** | fix |
| 5 | **Server ▸ Prevent Sleep While Running** | new option |
| 6 | **WKWebView file-chooser delegate** (`runOpenPanelWithParameters:`) | fix / safety net |

Non-goals (decided 2026-08-18): multiple windows / one server per workspace
(dsh's web UI already offers per-session workspaces and its own directory
picker); native notifications (no stable dsh event surface yet — revisit when
upstream exposes one); any curated list of presets; any write into `~/.dsh`
performed by the app process itself.

## 3. Invariants that still hold

- Never bundle dsh, never inject a profile, always pass the login-shell
  environment. **The app process never writes into `$DSH_HOME`.** Every install
  step that touches `$DSH_HOME` runs as a visible command in Terminal that the
  user has just read on screen (same model as *Update dsh…*).
- Network: localhost, `npm view`, `api.github.com`, **plus — new — the git host
  of a URL the user pastes**, contacted only by `git clone` at the moment they
  ask. Disclosed in README *Privacy & network*. Nothing runs at launch.
- Everything readable in one sitting: v3.1 adds ~350 lines (target: stay under
  1,600 total), two new small units, no dependencies.

## 4. Feature designs

### 4.1 Install from Git URL… (dsh menu)

**Flow**

1. Sheet with a text field: "Git URL of a dsh preset, skill or plugin
   repository" (accepts `https://…`, `http://…`, `git@host:owner/repo.git`,
   `ssh://…`). Buttons **Fetch** / **Cancel**.
2. Off the main thread: `git clone --depth 1 --recurse-submodules
   --shallow-submodules <url> <target>` using `git` from the login-shell PATH,
   with the login-shell environment, ≤ 120 s. `<target>` =
   `~/Library/Application Support/Harness.app/sources/<host>/<owner>/<repo>`
   (derived from the URL; anything that would escape that root is rejected
   before cloning). An existing target is removed and re-cloned (it is a cache,
   not user data). Window subtitle shows "cloning …" meanwhile.
   Failure → sheet with git's last stderr lines, **Copy Command** / **OK**.
3. Scan the clone (depth ≤ 4, skipping `.git`, `node_modules`, dotdirs):
   - **preset** = directory containing `preset.yml` → id = directory name
     lower-cased, non `[a-z0-9-]` runs → `-`, leading `-` trimmed (dsh requires
     `^[a-z0-9][a-z0-9-]*$`); target `$DSH_HOME/.agent-presets/<id>`
   - **skill** = directory containing `SKILL.md` → target `$DSH_HOME/skills/<dirname>`
   - **plugin** = directory containing `package.json` **and** (`cordis.patch.yml`,
     or a `"dsh"`/`"cordis"` key, or `keywords` containing `dsh-plugin` /
     `cordis-plugin`) → `dsh plugin --profile <current profile> add <abs dir>`
     (pnpm adds the local path — the same command the injector's README gives).
     A root `package.json` that is only repo tooling (no markers) is ignored,
     which is what keeps dsh-anchored-standard from being mis-read as a plugin.
   Nothing detected → sheet "No presets, skills or plugins recognised" with
   **Reveal Clone** and **Open README** (the user follows the repo's own
   instructions; we do not guess).
4. Sheet "Found in <repo>": one checkbox per item (all on), each labelled
   `preset router-standard → ~/.dsh/.agent-presets/router-standard` (or
   "(replaces existing)" when the target exists), buttons **Install in Terminal**
   / **Reveal Clone** / **Cancel**.
5. **Install in Terminal** runs one script, echoed line by line:
   ```sh
   set -e
   DSH_HOME="<resolved>"     # $DSH_HOME from the login shell, else ~/.dsh
   mkdir -p "$DSH_HOME/.agent-presets" "$DSH_HOME/skills"
   [ -e "$DSH_HOME/.agent-presets/<id>" ] && mv "$DSH_HOME/.agent-presets/<id>" "$DSH_HOME/.agent-presets/<id>.replaced-<yyyymmdd-HHMMSS>"
   cp -R "<clone>/<dir>" "$DSH_HOME/.agent-presets/<id>"
   …                                                     # skills likewise
   "<dsh>" plugin --profile <profile> add "<clone>/<plugindir>"
   echo "Harness: done — choose Server ▸ Restart Server, then pick the preset in a new session."
   ```
   Replaced directories are renamed, never deleted. Then a sheet: "Running in
   Terminal… when it finishes choose Server ▸ Restart Server."

**Unit** `HAInstaller.[mh]` (pure, testable): `HAInstallCloneTargetForURL`,
`HAScanInstallables(dir)` → items `{kind, sourceDir, id, targetPath}`,
`HAInstallScript(items, dshHome, dshPath, profile, timestamp)`,
`HAPresetIDFromName`. `main.m` owns only the sheets and the Terminal hand-off.

### 4.2 Presets ▸ / Skills ▸ (dsh menu)

Populated on open (`menuNeedsUpdate:`, like Profile): first item **Reveal
Presets Folder** / **Reveal Skills Folder** (creates nothing; if the folder
does not exist the item is disabled and reads "(none installed)"), separator,
then one item per installed entry (directories under `$DSH_HOME/.agent-presets`
holding `preset.yml`; under `$DSH_HOME/skills` holding `SKILL.md`; also
`~/.agents/skills`, which dsh reads too, labelled "(~/.agents)"). Choosing an
entry reveals it in Finder. Last item **Restart Server**. Nothing here writes.

### 4.3 Reveal / Edit (dsh menu)

- **Reveal dsh Home** → Finder at `$DSH_HOME` (default `~/.dsh`).
- **Reveal Sessions** → Finder at `$DSH_HOME/sessions` (disabled if absent).
- **Edit Profile Config…** → opens `$DSH_HOME/profiles/<current profile>/cordis.patch.yml`
  with the default app for the file, falling back to TextEdit; if the profile
  directory does not exist yet (profile never booted) → sheet explaining dsh
  creates it on first boot, **Restart Server** / **OK**.

### 4.4 Update / Repair command targets the owning npm (fix)

`HAEnvironment` already knows `dshPackageDir` (e.g.
`/opt/homebrew/lib/node_modules/@deepseek-ai/dsh`). New
`HADshInstallCommandForPackageDir(pkgDir)`:

- pkgDir under `<prefix>/lib/node_modules/…` and `<prefix>/bin/npm` executable →
  `'<prefix>/bin/npm' install -g --allow-scripts=… @deepseek-ai/dsh@latest`
- pkgDir under `<prefix>/lib/node_modules/…`, no sibling npm →
  `npm --prefix '<prefix>' install -g --allow-scripts=… @deepseek-ai/dsh@latest`
- otherwise (dsh not found, or an unusual layout) → the plain command, unchanged.

The flag list stays defined once (`HADshInstallArguments`); `HADshInstallCommand`
is now `"npm install -g " + arguments`. Used by *Update dsh…*, *Repair Shell
Tools…*, the update sheet, and (unchanged) first-run guidance. Arnold's machine
is the motivating case: login-shell `npm` = `~/.local/bin/npm` (prefix
`~/.local`), dsh installed under `/opt/homebrew` — the old command would have
produced a second, shadowing dsh.

### 4.5 Prevent Sleep While Running (Server menu + Settings)

Preference `PreventSleepWhileRunning` (BOOL, default NO). When ON and the
server is ready (spawned *or* attached — the user asked for "while running"),
hold an `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep,
…, "Harness.app: dsh server running")`; release it when the server stops, the
option is turned off, or the app quits. Unit `HASleepGuard.[mh]` (create /
release, idempotent, ~25 lines; links IOKit). Honest limit stated in README:
prevents *idle* sleep; closing a MacBook's lid still sleeps unless macOS
clamshell rules apply. Visible in `pmset -g assertions` (smoke test checks it).

### 4.6 WKWebView open panel (fix)

Implement `webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:`
with an `NSOpenPanel` sheet honouring `allowsMultipleSelection` and
`allowsDirectories`, `canChooseFiles = YES`; cancel → `completionHandler(nil)`.
Without it any `<input type=file>` inside the UI silently does nothing.
(dsh's own workspace directory picker is unaffected — it runs server-side via
`osascript` — but attachments, plugins and future RCs may use a browser chooser.)

## 5. Menus after v3.1

- **Server** — Restart Server · Keep Server Running After Close · **Prevent
  Sleep While Running** · Profile ▸ · — · Open Log · Open Workspace in Terminal
- **dsh** — Update dsh… · Check for dsh Updates Now · — · **Install from Git
  URL…** · **Presets ▸** · **Skills ▸** · — · **Reveal dsh Home** · **Reveal
  Sessions** · **Edit Profile Config…** · — · Repair Shell Tools…

Settings window gains the *Prevent sleep while the server is running* checkbox.

## 6. Error handling

Every failure is a sheet with an action: git missing (→ "install Xcode Command
Line Tools: xcode-select --install", **Copy**), clone failed (stderr tail,
**Copy Command**), nothing recognised (**Reveal Clone / Open README**),
Terminal refused (existing Automation-permission message), profile dir absent
(**Restart Server**). Cloning never blocks the UI; a second *Install…* while one
is running is refused with a notice.

## 7. Testing

- `tests/test_installer.m` (new): URL → clone target (https, ssh, git@, `.git`
  suffix, escape attempts rejected); scan of a synthetic tree (three presets, a
  skill, a plugin with `cordis.patch.yml`, a decoy root `package.json`, files
  under `node_modules`/`.git` ignored); preset-id sanitising; generated script
  (quoting, `mv … .replaced-`, `dsh plugin … add`, one `mkdir -p`).
- `tests/test_environment.m`: `HADshInstallCommandForPackageDir` three cases;
  `HADshHome` (env override vs default).
- `tests/test_sleepguard.m` (new): enable/disable idempotent, assertion id set.
- `scripts/smoke.sh`: scenario 5 — with `PreventSleepWhileRunning` YES,
  `pmset -g assertions` lists "Harness.app: dsh server running" while up and not
  after quit.
- Manual (Arnold): Install a real preset (xiaobright/dsh-anchored-standard) and
  J-Space, restart, pick them in a session; open a file chooser inside the UI;
  toggle Prevent Sleep and watch `pmset`.

## 8. Release

Version 3.1.0 in `HAConfig.h` + `Makefile`; CHANGELOG; README EN/中文/ES
(features, menus, Settings table, Privacy & network, "Installing presets,
skills and plugins" section); tag `v3.1.0`; GitHub release; tap formula sha256;
CI green (build + unit + smoke on macos-latest). No AI attribution anywhere.
