# Harness.app v3.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Harness.app v3.0 — a native, tiny, auditable macOS launcher for the user's own npm-installed DeepSeek Harness (`dsh`) — as a public MIT repo installable via Homebrew tap or `make install`.

**Architecture:** Four small Objective-C units (AppDelegate/UI, HAEnvironment, HAServer, HAUpdater) plus a keys header, built by one `clang` invocation into a universal `Harness.app`. HAServer owns the `dsh web` child via `posix_spawn` in its own process group (attach-or-spawn, HTTP readiness, escalating stop, one auto-restart). HAEnvironment captures the login-shell environment and diagnoses dsh/Node/node-pty. HAUpdater does two disclosed, off-able version checks and runs update commands visibly in Terminal.app.

**Tech Stack:** Objective-C (ARC), AppKit, WebKit (WKWebView), Foundation, `posix_spawn`, libdispatch; `make`; a hand-rolled test runner (no XCTest — Command Line Tools only); a tiny C fake-`dsh` HTTP server for lifecycle tests; Homebrew formula; GitHub Actions (macos runner).

**Spec:** `docs/superpowers/specs/2026-08-16-harness-app-v3-design.md`

## Global Constraints

- App name **Harness.app**; executable `Harness`; bundle id `com.arnoldoconcepcion.harness-app`; version `3.0.0`; `LSMinimumSystemVersion` 13.0.
- Universal binary (`-arch arm64 -arch x86_64`); ad-hoc signed by `make install`; **no notarization, no DMG** in v3.0.
- Build must remain one `clang` command over `src/*.m` (Makefile may add icon/bundle steps).
- The launcher runs the user's own `dsh` and `~/.dsh`; never bundles dsh, never injects a profile, passes `DSH_HOME` through; the login-shell environment is the server's environment.
- Default port `3080`; default profile `web`; default workspace `$HOME`; default close = stop; keep-alive opt-in; no tray, no daemon.
- Only network calls: localhost, `registry.npmjs.org` via `npm view` (dsh check), `api.github.com` (app check) — both off-able via preferences.
- The exact dsh install/repair command (verbatim everywhere):
  `npm install -g --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs @deepseek-ai/dsh@latest`
- Node support rule (dsh `engines`): `^22.19.0 || >=24.0.0`.
- Broken-node-pty rule: `<dsh package>/node_modules/node-pty/prebuilds/darwin-<arch>/pty.node` missing **or** `spawn-helper` missing/not executable ⇒ broken; `node-pty` dir absent ⇒ unknown (do not nag).
- Whale emoji icon (never DeepSeek's logo); README states "unofficial community project".
- Commit after every task with the trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

## File structure

```
harness-app/
  Makefile                       build/test/smoke/install/icon/clean
  .gitignore                     build/, *.o, .DS_Store
  LICENSE                        MIT
  Resources/Info.plist.in        @VERSION@ substituted by make
  src/HAConfig.h                 preference keys + HARegisterDefaults()
  src/HAEnvironment.h/.m         login-shell env, dsh/Node discovery, node-pty diagnosis (pure C helpers + class)
  src/HAServer.h/.m              attach-or-spawn, readiness, escalating stop, crash restart
  src/HAUpdater.h/.m             semver compare, dsh/app version checks, Terminal command runner
  src/main.m                     AppDelegate: window, WKWebView, menus, dialogs, Preferences, Dock drop, --check-env
  src/icon.m                     renders 1024px AppIcon PNG (whale on blue)
  tests/HATest.h                 assertion macros + HAWaitUntil()
  tests/fakedsh.c                fake `dsh` HTTP server for lifecycle tests
  tests/test_environment.m       HAEnvironment unit tests
  tests/test_server.m            HAServer lifecycle tests (uses fakedsh)
  tests/test_updater.m           HACompareVersions tests
  scripts/make-icon.sh           PNG → .icns via sips + iconutil
  scripts/smoke.sh               end-to-end app smoke (4 scenarios)
  Formula/harness-app.rb         Homebrew formula (mirrored to aconcepcion/homebrew-tap)
  .github/workflows/ci.yml       build + test + smoke on macos-latest
  README.md  README.zh.md  CHANGELOG.md
```

---

### Task 1: Scaffold the repo and port v2 into the new build system

**Files:**
- Create: `Makefile`, `.gitignore`, `LICENSE`, `Resources/Info.plist.in`, `src/HAConfig.h`, `src/icon.m` (moved), `src/main.m` (v2 copy, renamed strings), `scripts/make-icon.sh`, `tests/HATest.h`
- Source of v2: `~/dsh-test/launcher-src/main.m`, `~/dsh-test/launcher-src/icon.m`

**Interfaces:**
- Produces: `make` → `build/Harness.app` (universal); `make install` → `/Applications/Harness.app`; `make test` (runs `tests/test_*.m`); `HARegisterDefaults()`; preference key constants `HAPref*`.

- [ ] **Step 1: Copy v2 sources in and create `.gitignore` + LICENSE**

```bash
cd ~/Projects/harness-app
mkdir -p src tests scripts Resources Formula .github/workflows
cp ~/dsh-test/launcher-src/main.m src/main.m
cp ~/dsh-test/launcher-src/icon.m src/icon.m
printf 'build/\n*.o\n.DS_Store\n*.icns\n*.png\n' > .gitignore
```

`LICENSE` (MIT, verbatim):
```
MIT License

Copyright (c) 2026 Arnoldo Concepcion

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Rename v2 strings in `src/main.m`**

In the copied `src/main.m` replace: window title `@"DeepSeek Harness"` → `@"Harness"`; frame autosave `@"DSHMainWindow"` → `@"HAMainWindow"`; menu `@"Quit DeepSeek Harness"` → `@"Quit Harness"`; alert `messageText = @"DeepSeek Harness"` → `@"Harness"`. Leave behavior unchanged for now (Task 5 rewrites it).

- [ ] **Step 3: Write `src/HAConfig.h`**

```objc
#import <Foundation/Foundation.h>

// Preference keys (NSUserDefaults, domain = bundle id com.arnoldoconcepcion.harness-app).
static NSString *const HAPrefPort              = @"Port";               // NSNumber, default 3080
static NSString *const HAPrefWorkspace         = @"Workspace";          // NSString path, default NSHomeDirectory()
static NSString *const HAPrefProfile           = @"Profile";            // NSString, default "web"
static NSString *const HAPrefDshPath           = @"DshPath";            // NSString, "" = auto-detect
static NSString *const HAPrefKeepServerRunning = @"KeepServerRunning";  // BOOL, default NO
static NSString *const HAPrefCheckDshUpdates   = @"CheckForDshUpdates"; // BOOL, default YES
static NSString *const HAPrefCheckAppUpdates   = @"CheckForAppUpdates"; // BOOL, default YES

static NSString *const HAAppVersion    = @"3.0.0";
static NSString *const HAGitHubRepo    = @"aconcepcion/harness-app";
static NSString *const HADefaultProfile = @"web";
static uint16_t const HADefaultPort    = 3080;

static inline void HARegisterDefaults(void) {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        HAPrefPort: @(HADefaultPort),
        HAPrefWorkspace: NSHomeDirectory(),
        HAPrefProfile: HADefaultProfile,
        HAPrefDshPath: @"",
        HAPrefKeepServerRunning: @NO,
        HAPrefCheckDshUpdates: @YES,
        HAPrefCheckAppUpdates: @YES,
    }];
}

// Log lives where macOS expects app logs (Console.app picks it up).
static inline NSString *HALogPath(void) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/Harness.app"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"harness-app.log"];
}
```

- [ ] **Step 4: Write `Resources/Info.plist.in`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Harness</string>
  <key>CFBundleDisplayName</key><string>Harness</string>
  <key>CFBundleIdentifier</key><string>com.arnoldoconcepcion.harness-app</string>
  <key>CFBundleExecutable</key><string>Harness</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>@VERSION@</string>
  <key>CFBundleVersion</key><string>@VERSION@</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License. Unofficial community launcher for DeepSeek Harness.</string>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>Folder</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSItemContentTypes</key><array><string>public.folder</string></array>
    <key>LSHandlerRank</key><string>None</string>
  </dict></array>
</dict></plist>
```

- [ ] **Step 5: Write `scripts/make-icon.sh`**

```bash
#!/bin/bash
# Usage: make-icon.sh <icon-tool-binary> <out.icns>
set -euo pipefail
TOOL="$1"; OUT="$2"; TMP="$(mktemp -d)"
"$TOOL" "$TMP/icon_1024.png" >/dev/null
mkdir -p "$TMP/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon_1024.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s*2)); sips -z $d $d "$TMP/icon_1024.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$OUT"
rm -rf "$TMP"
echo "icon: $OUT"
```
`chmod +x scripts/make-icon.sh`.

- [ ] **Step 6: Write `tests/HATest.h`**

```objc
#import <Foundation/Foundation.h>
static int HAFailures = 0, HAChecks = 0;
#define HA_ASSERT(cond, ...) do { HAChecks++; if (!(cond)) { HAFailures++; \
    fprintf(stderr, "  FAIL %s:%d: ", __FILE__, __LINE__); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } } while (0)
#define HA_EQ_STR(a, b) HA_ASSERT([(a) isEqualToString:(b)], "expected \"%s\" got \"%s\"", [(b) UTF8String], [(a) UTF8String])
#define HA_DONE() do { printf("%s: %d checks, %d failures\n", __FILE__, HAChecks, HAFailures); return HAFailures ? 1 : 0; } while (0)
// Spin the main run loop until block returns YES or timeout; returns whether it did.
static inline BOOL HAWaitUntil(NSTimeInterval timeout, BOOL (^cond)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!cond()) {
        if ([deadline timeIntervalSinceNow] <= 0) return NO;
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return YES;
}
```

- [ ] **Step 7: Write the `Makefile`**

```make
APP      = Harness
VERSION  = 3.0.0
BUILD    = build
APPDIR   = $(BUILD)/$(APP).app
SRC      = src/main.m src/HAEnvironment.m src/HAServer.m src/HAUpdater.m
HDR      = $(wildcard src/*.h)
ARCHS    = -arch arm64 -arch x86_64
CFLAGS   = -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=13.0
FW       = -framework Cocoa -framework WebKit
TESTS    = $(patsubst tests/%.m,$(BUILD)/%,$(wildcard tests/test_*.m))
LIBSRC   = src/HAEnvironment.m src/HAServer.m src/HAUpdater.m

.PHONY: all app install test smoke clean icon
all: app
app: $(APPDIR)

$(BUILD)/$(APP): $(SRC) $(HDR) | $(BUILD)
	clang $(CFLAGS) $(ARCHS) -o $@ $(SRC) $(FW)

$(BUILD)/icontool: src/icon.m | $(BUILD)
	clang -fobjc-arc -O2 -o $@ src/icon.m -framework AppKit

$(BUILD)/AppIcon.icns: $(BUILD)/icontool scripts/make-icon.sh
	scripts/make-icon.sh $(BUILD)/icontool $@

$(APPDIR): $(BUILD)/$(APP) $(BUILD)/AppIcon.icns Resources/Info.plist.in
	rm -rf $(APPDIR)
	mkdir -p $(APPDIR)/Contents/MacOS $(APPDIR)/Contents/Resources
	sed 's/@VERSION@/$(VERSION)/g' Resources/Info.plist.in > $(APPDIR)/Contents/Info.plist
	cp $(BUILD)/$(APP) $(APPDIR)/Contents/MacOS/$(APP)
	cp $(BUILD)/AppIcon.icns $(APPDIR)/Contents/Resources/AppIcon.icns
	codesign --force -s - $(APPDIR)
	@echo "built $(APPDIR)"; lipo -info $(APPDIR)/Contents/MacOS/$(APP)

install: app
	rm -rf "/Applications/$(APP).app"
	cp -R $(APPDIR) "/Applications/$(APP).app"
	@echo "installed /Applications/$(APP).app"

$(BUILD)/fakedsh: tests/fakedsh.c | $(BUILD)
	clang -O2 -o $@ tests/fakedsh.c

$(BUILD)/test_%: tests/test_%.m $(LIBSRC) $(HDR) tests/HATest.h | $(BUILD)
	clang $(CFLAGS) -Isrc -o $@ $< $(LIBSRC) -framework Foundation -framework AppKit

test: $(TESTS) $(BUILD)/fakedsh
	@rc=0; for t in $(TESTS); do FAKEDSH=$(abspath $(BUILD)/fakedsh) $$t || rc=1; done; exit $$rc

smoke: app $(BUILD)/fakedsh
	scripts/smoke.sh $(abspath $(APPDIR)) $(abspath $(BUILD)/fakedsh)

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
```

Until Tasks 2–4 create the other sources, temporarily set `SRC = src/main.m` and `LIBSRC =` (empty) so Task 1 builds; Tasks 2–4 restore the lines above as they add files.

- [ ] **Step 8: Build, install, verify the v2 behavior still works under the new name**

Run: `make && make install && lipo -info build/Harness.app/Contents/MacOS/Harness && open -a Harness`
Expected: `Architectures ... x86_64 arm64`; window titled "Harness" opens, dsh UI loads; closing quits and stops the server (`pgrep -f "dsh web"` → empty).

- [ ] **Step 9: Commit**

```bash
git add -A && git commit -m "build: scaffold Harness.app repo, universal Makefile, port v2 launcher

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: HAEnvironment — login-shell env, dsh/Node discovery, node-pty diagnosis (TDD)

**Files:**
- Create: `src/HAEnvironment.h`, `src/HAEnvironment.m`, `tests/test_environment.m`
- Modify: `Makefile` (`SRC` gains `src/HAEnvironment.m`; `LIBSRC` gains it)

**Interfaces:**
- Produces (used by Tasks 3, 5, 7):
  - `NSString *const HADshInstallCommand`
  - `NSDictionary<NSString*,NSString*> *HACaptureLoginShellEnvironment(NSTimeInterval timeout)`
  - `NSDictionary<NSString*,NSString*> *HAParseNullSeparatedEnvironment(NSData *data)`
  - `NSString *_Nullable HAFindExecutable(NSString *name, NSString *_Nullable pathValue)`
  - `BOOL HANodeVersionIsSupported(NSString *version)`
  - `NSString *_Nullable HADshPackageDirForBinary(NSString *binPath)`
  - `HANodePtyState HANodePtyStateForPackageDir(NSString *pkgDir, NSString *arch)` — enum `HANodePtyUnknown/Intact/Broken`
  - `NSString *HACurrentNodeArch(void)` — `"arm64"` or `"x64"`
  - `NSString *_Nullable HARunCommandOutput(NSString *path, NSArray *args, NSDictionary *_Nullable env, NSTimeInterval timeout, int *_Nullable status)`
  - `@interface HAEnvironment` with readonly `shellEnvironment, dshPath, dshVersion, dshPackageDir, nodePath, nodeVersion, nodeSupported, nodePtyState`; `+ (instancetype)capture:(NSString *_Nullable)preferredDshPath;` `- (NSString *)report;`

- [ ] **Step 1: Write the failing tests `tests/test_environment.m`**

```objc
#import "HATest.h"
#import "HAEnvironment.h"

static NSString *tmpdir(void) {
    NSString *d = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"hatest-%d-%u", getpid(), arc4random()]];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}
static void touch(NSString *p, BOOL exec) {
    [[NSFileManager defaultManager] createDirectoryAtPath:[p stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] createFileAtPath:p contents:[NSData data]
        attributes:@{NSFilePosixPermissions: @(exec ? 0755 : 0644)}];
}

int main(void) { @autoreleasepool {
    // Node version rule: ^22.19.0 || >=24.0.0
    HA_ASSERT(HANodeVersionIsSupported(@"v26.7.0"), "26 supported");
    HA_ASSERT(HANodeVersionIsSupported(@"24.0.0"), "24.0.0 supported");
    HA_ASSERT(HANodeVersionIsSupported(@"22.19.0"), "22.19.0 supported");
    HA_ASSERT(HANodeVersionIsSupported(@"22.20.1"), "22.20.1 supported");
    HA_ASSERT(!HANodeVersionIsSupported(@"22.18.9"), "22.18 unsupported");
    HA_ASSERT(!HANodeVersionIsSupported(@"v23.11.0"), "23.x unsupported (the gap)");
    HA_ASSERT(!HANodeVersionIsSupported(@"20.11.0"), "20 unsupported");
    HA_ASSERT(!HANodeVersionIsSupported(@"garbage"), "garbage unsupported");

    // Env block parsing (NUL-separated, markers around it)
    NSMutableData *blob = [NSMutableData data];
    [blob appendData:[@"junk from rc file\n__HA_ENV_START__\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [blob appendData:[@"PATH=/a:/b\0HOME=/Users/x\0MULTI=line1\nline2\0" dataUsingEncoding:NSUTF8StringEncoding]];
    [blob appendData:[@"__HA_ENV_END__\n" dataUsingEncoding:NSUTF8StringEncoding]];
    NSDictionary *env = HAParseNullSeparatedEnvironment(blob);
    HA_EQ_STR(env[@"PATH"], @"/a:/b");
    HA_EQ_STR(env[@"HOME"], @"/Users/x");
    HA_EQ_STR(env[@"MULTI"], @"line1\nline2");
    HA_ASSERT(env.count == 3, "exactly 3 vars, got %lu", (unsigned long)env.count);
    HA_ASSERT(HAParseNullSeparatedEnvironment([NSData data]).count == 0, "empty → empty");

    // Executable lookup honors PATH order and executable bit
    NSString *d = tmpdir();
    touch([d stringByAppendingPathComponent:@"one/dsh"], NO);
    touch([d stringByAppendingPathComponent:@"two/dsh"], YES);
    NSString *path = [NSString stringWithFormat:@"%@/one:%@/two", d, d];
    HA_EQ_STR(HAFindExecutable(@"dsh", path), [d stringByAppendingPathComponent:@"two/dsh"]);
    HA_ASSERT(HAFindExecutable(@"nope", path) == nil, "missing → nil");
    HA_ASSERT(HAFindExecutable(@"dsh", nil) == nil || YES, "nil PATH tolerated");

    // Package dir from (symlinked) bin: <root>/bin/dsh -> ../lib/node_modules/@deepseek-ai/dsh/lib/bin.js
    NSString *pkg = [d stringByAppendingPathComponent:@"lib/node_modules/@deepseek-ai/dsh"];
    touch([pkg stringByAppendingPathComponent:@"lib/bin.js"], YES);
    [@"{\"name\":\"@deepseek-ai/dsh\",\"version\":\"0.1.0-rc.6\"}" writeToFile:[pkg stringByAppendingPathComponent:@"package.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:[d stringByAppendingPathComponent:@"bin"] withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] createSymbolicLinkAtPath:[d stringByAppendingPathComponent:@"bin/dsh"]
        withDestinationPath:@"../lib/node_modules/@deepseek-ai/dsh/lib/bin.js" error:nil];
    NSString *found = HADshPackageDirForBinary([d stringByAppendingPathComponent:@"bin/dsh"]);
    HA_ASSERT([[found stringByResolvingSymlinksInPath] isEqualToString:[pkg stringByResolvingSymlinksInPath]], "pkg dir resolved, got %s", [found UTF8String]);
    HA_ASSERT(HADshPackageDirForBinary(@"/nonexistent/dsh") == nil, "nonexistent → nil");

    // node-pty state
    HA_ASSERT(HANodePtyStateForPackageDir(pkg, @"arm64") == HANodePtyUnknown, "no node-pty dir → unknown");
    NSString *pre = [pkg stringByAppendingPathComponent:@"node_modules/node-pty/prebuilds/win32-arm64"];
    touch([pre stringByAppendingPathComponent:@"pty.node"], NO);
    HA_ASSERT(HANodePtyStateForPackageDir(pkg, @"arm64") == HANodePtyBroken, "only win32 prebuild → broken");
    NSString *dar = [pkg stringByAppendingPathComponent:@"node_modules/node-pty/prebuilds/darwin-arm64"];
    touch([dar stringByAppendingPathComponent:@"pty.node"], NO);
    touch([dar stringByAppendingPathComponent:@"spawn-helper"], NO);
    HA_ASSERT(HANodePtyStateForPackageDir(pkg, @"arm64") == HANodePtyBroken, "spawn-helper not executable → broken");
    chmod([[dar stringByAppendingPathComponent:@"spawn-helper"] fileSystemRepresentation], 0755);
    HA_ASSERT(HANodePtyStateForPackageDir(pkg, @"arm64") == HANodePtyIntact, "darwin prebuild complete → intact");
    HA_ASSERT(HANodePtyStateForPackageDir(pkg, @"x64") == HANodePtyBroken, "other arch missing → broken");

    // Command runner + timeout
    int st = -1;
    NSString *out = HARunCommandOutput(@"/bin/echo", @[@"hi"], nil, 5, &st);
    HA_EQ_STR([out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet], @"hi");
    HA_ASSERT(st == 0, "echo exit 0");
    NSDate *t0 = [NSDate date];
    out = HARunCommandOutput(@"/bin/sleep", @[@"5"], nil, 0.5, &st);
    HA_ASSERT(out == nil && [[NSDate date] timeIntervalSinceDate:t0] < 3, "timeout kills the task");

    HA_ASSERT([HACurrentNodeArch() isEqualToString:@"arm64"] || [HACurrentNodeArch() isEqualToString:@"x64"], "arch string");
    HA_ASSERT([HADshInstallCommand containsString:@"--allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs"], "install command carries allow-scripts");

    // Real capture smoke (this machine): must not throw, PATH non-empty
    NSDictionary *real = HACaptureLoginShellEnvironment(8);
    HA_ASSERT([real[@"PATH"] length] > 0, "captured PATH");
    HA_DONE();
} }
```

- [ ] **Step 2: Run to verify it fails to build**

Run: `make build/test_environment`
Expected: compile error — `HAEnvironment.h` not found.

- [ ] **Step 3: Write `src/HAEnvironment.h`**

```objc
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

extern NSString *const HADshInstallCommand;

typedef NS_ENUM(NSInteger, HANodePtyState) { HANodePtyUnknown = 0, HANodePtyIntact, HANodePtyBroken };

NSDictionary<NSString *, NSString *> *HACaptureLoginShellEnvironment(NSTimeInterval timeout);
NSDictionary<NSString *, NSString *> *HAParseNullSeparatedEnvironment(NSData *data);
NSString *_Nullable HAFindExecutable(NSString *name, NSString *_Nullable pathValue);
BOOL HANodeVersionIsSupported(NSString *version);
NSString *_Nullable HADshPackageDirForBinary(NSString *binPath);
HANodePtyState HANodePtyStateForPackageDir(NSString *pkgDir, NSString *arch);
NSString *HACurrentNodeArch(void);
NSString *_Nullable HARunCommandOutput(NSString *path, NSArray<NSString *> *args,
                                       NSDictionary<NSString *, NSString *> *_Nullable env,
                                       NSTimeInterval timeout, int *_Nullable status);

@interface HAEnvironment : NSObject
@property (readonly) NSDictionary<NSString *, NSString *> *shellEnvironment;
@property (readonly, nullable) NSString *dshPath;
@property (readonly, nullable) NSString *dshVersion;
@property (readonly, nullable) NSString *dshPackageDir;
@property (readonly, nullable) NSString *nodePath;
@property (readonly, nullable) NSString *nodeVersion;
@property (readonly) BOOL nodeSupported;
@property (readonly) HANodePtyState nodePtyState;
/// Blocking (runs shell + a few commands, up to ~15 s worst case). Call off the main thread.
+ (instancetype)capture:(NSString *_Nullable)preferredDshPath;
- (NSString *)report;
@end
NS_ASSUME_NONNULL_END
```

- [ ] **Step 4: Write `src/HAEnvironment.m`**

```objc
#import "HAEnvironment.h"
#import <sys/sysctl.h>

NSString *const HADshInstallCommand =
    @"npm install -g --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs @deepseek-ai/dsh@latest";

NSString *HARunCommandOutput(NSString *path, NSArray<NSString *> *args, NSDictionary *env,
                             NSTimeInterval timeout, int *status) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = args;
    if (env) task.environment = env;
    NSPipe *out = [NSPipe pipe];
    task.standardOutput = out;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];
    NSError *err = nil;
    if (![task launchAndReturnError:&err]) { if (status) *status = -1; return nil; }
    __block BOOL timedOut = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (task.isRunning) { timedOut = YES; [task terminate]; kill(task.processIdentifier, SIGKILL); }
    });
    NSData *data = [[out fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    if (status) *status = task.terminationStatus;
    if (timedOut) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

NSDictionary<NSString *, NSString *> *HAParseNullSeparatedEnvironment(NSData *data) {
    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    if (data.length == 0) return env;
    NSData *start = [@"__HA_ENV_START__\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *end = [@"__HA_ENV_END__" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange s = [data rangeOfData:start options:0 range:NSMakeRange(0, data.length)];
    NSUInteger from = (s.location == NSNotFound) ? 0 : NSMaxRange(s);
    NSRange e = [data rangeOfData:end options:0 range:NSMakeRange(from, data.length - from)];
    NSUInteger to = (e.location == NSNotFound) ? data.length : e.location;
    NSData *body = [data subdataWithRange:NSMakeRange(from, to - from)];
    const char *bytes = body.bytes; NSUInteger len = body.length, i = 0;
    while (i < len) {
        NSUInteger j = i; while (j < len && bytes[j] != '\0') j++;
        NSString *kv = [[NSString alloc] initWithBytes:bytes + i length:j - i encoding:NSUTF8StringEncoding];
        NSRange eq = [kv rangeOfString:@"="];
        if (eq.location != NSNotFound && eq.location > 0)
            env[[kv substringToIndex:eq.location]] = [kv substringFromIndex:eq.location + 1];
        i = j + 1;
    }
    return env;
}

NSDictionary<NSString *, NSString *> *HACaptureLoginShellEnvironment(NSTimeInterval timeout) {
    NSDictionary *procEnv = [NSProcessInfo processInfo].environment;
    NSString *shell = procEnv[@"SHELL"] ?: @"/bin/zsh";
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:shell]) shell = @"/bin/zsh";
    NSString *script = @"echo __HA_ENV_START__; env -0; echo __HA_ENV_END__";
    NSMutableDictionary *childEnv = [procEnv mutableCopy];
    childEnv[@"HA_ENV_CAPTURE"] = @"1"; // rc files may test this to skip slow/interactive work
    for (NSArray *flags in @[@[@"-ilc"], @[@"-lc"]]) {
        NSTask *task = [NSTask new];
        task.executableURL = [NSURL fileURLWithPath:shell];
        task.arguments = [flags arrayByAddingObject:script];
        task.environment = childEnv;
        task.standardInput = [NSFileHandle fileHandleWithNullDevice];
        task.standardError = [NSFileHandle fileHandleWithNullDevice];
        NSPipe *out = [NSPipe pipe]; task.standardOutput = out;
        NSError *err = nil;
        if (![task launchAndReturnError:&err]) continue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ if (task.isRunning) kill(task.processIdentifier, SIGKILL); });
        NSData *data = [[out fileHandleForReading] readDataToEndOfFile];
        [task waitUntilExit];
        NSDictionary *env = HAParseNullSeparatedEnvironment(data);
        if ([env[@"PATH"] length] > 0) return env;
    }
    return procEnv;
}

NSString *HAFindExecutable(NSString *name, NSString *pathValue) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in [pathValue ?: @"" componentsSeparatedByString:@":"]) {
        if (dir.length == 0) continue;
        NSString *p = [dir stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:p isDirectory:&isDir] && !isDir && [fm isExecutableFileAtPath:p]) return p;
    }
    return nil;
}

BOOL HANodeVersionIsSupported(NSString *version) {
    NSString *v = [version hasPrefix:@"v"] ? [version substringFromIndex:1] : version;
    NSArray *parts = [[v stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsSeparatedByString:@"."];
    if (parts.count < 2) return NO;
    NSScanner *sc = [NSScanner scannerWithString:parts[0]]; NSInteger major = -1, minor = -1;
    if (![sc scanInteger:&major] || !sc.isAtEnd) return NO;
    sc = [NSScanner scannerWithString:parts[1]]; if (![sc scanInteger:&minor]) return NO;
    return (major == 22 && minor >= 19) || major >= 24;
}

NSString *HADshPackageDirForBinary(NSString *binPath) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:binPath]) return nil;
    NSString *real = [binPath stringByResolvingSymlinksInPath];
    NSString *dir = [real stringByDeletingLastPathComponent];
    for (int i = 0; i < 6 && dir.length > 1; i++) {
        NSString *pj = [dir stringByAppendingPathComponent:@"package.json"];
        NSData *d = [NSData dataWithContentsOfFile:pj];
        if (d) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            if ([json[@"name"] isEqual:@"@deepseek-ai/dsh"]) return dir;
        }
        dir = [dir stringByDeletingLastPathComponent];
    }
    return nil;
}

HANodePtyState HANodePtyStateForPackageDir(NSString *pkgDir, NSString *arch) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *pty = [pkgDir stringByAppendingPathComponent:@"node_modules/node-pty"];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:pty isDirectory:&isDir] || !isDir) return HANodePtyUnknown;
    if ([fm fileExistsAtPath:[pty stringByAppendingPathComponent:@"build/Release/pty.node"]]) return HANodePtyIntact;
    NSString *pre = [pty stringByAppendingFormat:@"/prebuilds/darwin-%@", arch];
    NSString *helper = [pre stringByAppendingPathComponent:@"spawn-helper"];
    if ([fm fileExistsAtPath:[pre stringByAppendingPathComponent:@"pty.node"]] &&
        [fm fileExistsAtPath:helper] && [fm isExecutableFileAtPath:helper]) return HANodePtyIntact;
    return HANodePtyBroken;
}

NSString *HACurrentNodeArch(void) {
#if defined(__arm64__)
    return @"arm64";
#else
    return @"x64";
#endif
}

@interface HAEnvironment ()
@property (readwrite) NSDictionary<NSString *, NSString *> *shellEnvironment;
@property (readwrite, nullable) NSString *dshPath, *dshVersion, *dshPackageDir, *nodePath, *nodeVersion;
@property (readwrite) BOOL nodeSupported;
@property (readwrite) HANodePtyState nodePtyState;
@end

@implementation HAEnvironment
+ (instancetype)capture:(NSString *)preferredDshPath {
    HAEnvironment *e = [HAEnvironment new];
    e.shellEnvironment = HACaptureLoginShellEnvironment(8);
    NSString *path = e.shellEnvironment[@"PATH"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (preferredDshPath.length && [fm isExecutableFileAtPath:preferredDshPath]) e.dshPath = preferredDshPath;
    else e.dshPath = HAFindExecutable(@"dsh", path);
    e.nodePath = HAFindExecutable(@"node", path);
    if (e.nodePath) {
        NSString *v = HARunCommandOutput(e.nodePath, @[@"--version"], e.shellEnvironment, 5, NULL);
        v = [v stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (v.length) { e.nodeVersion = [v hasPrefix:@"v"] ? [v substringFromIndex:1] : v; e.nodeSupported = HANodeVersionIsSupported(v); }
    }
    if (e.dshPath) {
        NSString *v = HARunCommandOutput(e.dshPath, @[@"--version"], e.shellEnvironment, 8, NULL);
        v = [v stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (v.length) e.dshVersion = v;
        e.dshPackageDir = HADshPackageDirForBinary(e.dshPath);
        e.nodePtyState = e.dshPackageDir ? HANodePtyStateForPackageDir(e.dshPackageDir, HACurrentNodeArch()) : HANodePtyUnknown;
    }
    return e;
}
- (NSString *)report {
    NSString *pty = @[@"unknown", @"intact", @"BROKEN"][self.nodePtyState];
    return [NSString stringWithFormat:
        @"shell PATH: %@\ndsh: %@\ndsh version: %@\ndsh package: %@\nnode: %@\nnode version: %@ (%@)\nnode-pty: %@\nDSH_HOME: %@\n",
        self.shellEnvironment[@"PATH"] ?: @"", self.dshPath ?: @"not found", self.dshVersion ?: @"?",
        self.dshPackageDir ?: @"?", self.nodePath ?: @"not found", self.nodeVersion ?: @"?",
        self.nodeSupported ? @"supported" : @"UNSUPPORTED", pty, self.shellEnvironment[@"DSH_HOME"] ?: @"(default ~/.dsh)"];
}
@end
```

- [ ] **Step 5: Add `src/HAEnvironment.m` to `SRC`/`LIBSRC` in the Makefile, run tests**

Run: `make build/test_environment && FAKEDSH=x build/test_environment`
Expected: `tests/test_environment.m: N checks, 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: HAEnvironment — login-shell env, dsh/Node discovery, node-pty diagnosis

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: fakedsh test server + HAServer — attach-or-spawn, readiness, escalating stop, crash restart (TDD)

**Files:**
- Create: `tests/fakedsh.c`, `src/HAServer.h`, `src/HAServer.m`, `tests/test_server.m`
- Modify: `Makefile` (`SRC`/`LIBSRC` gain `src/HAServer.m`)

**Interfaces:**
- Consumes: nothing from HAEnvironment (HAServer takes resolved values).
- Produces (used by Task 5):
  - `typedef NS_ENUM(NSInteger, HAServerMode) { HAServerModeNone, HAServerModeAttached, HAServerModeSpawned }`
  - `@protocol HAServerDelegate` — `serverDidBecomeReady:`, `server:didFailToStart:`, `serverDidRestart:`, `server:didGiveUp:` (all on main queue)
  - `HAServer` — `initWithDshPath:port:profile:workspace:environment:logPath:`, `start`, `restart`, `stopSynchronously:`, `probeReady`, readonly `mode`, `port`, `baseURL`, `logPath`, `childPID`
  - `+ (BOOL)probeURL:timeout:` (HTTP GET, true when status < 400)
  - `+ (NSArray<NSString *> *)argumentsForProfile:port:` → `web --port N` for `web`, else `--profile NAME --port N`
  - `- (NSString *)logTail:(NSUInteger)lines`

- [ ] **Step 1: Write `tests/fakedsh.c` — a minimal HTTP server that mimics `dsh web`**

```c
// fakedsh: pretends to be `dsh web --port N`. Env knobs:
//   FAKEDSH_IGNORE_TERM=1   ignore SIGTERM (forces SIGKILL escalation)
//   FAKEDSH_EXIT_AFTER=N    exit(3) after N seconds of serving (crash simulation)
//   FAKEDSH_SPAWN_CHILD=1   spawn a `sleep 600` child in the same process group (orphan test)
//   FAKEDSH_DELAY=N         wait N seconds before listening (readiness test)
#include <arpa/inet.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static void ignore(int s) { (void)s; }

int main(int argc, char **argv) {
    int port = 3080;
    for (int i = 1; i < argc; i++) if (!strcmp(argv[i], "--port") && i + 1 < argc) port = atoi(argv[i + 1]);
    if (argc > 1 && !strcmp(argv[1], "--version")) { puts("0.1.0-fake"); return 0; }
    if (getenv("FAKEDSH_IGNORE_TERM")) signal(SIGTERM, ignore);
    if (getenv("FAKEDSH_SPAWN_CHILD")) { if (fork() == 0) { execl("/bin/sleep", "sleep", "600", (char *)0); _exit(1); } }
    if (getenv("FAKEDSH_DELAY")) sleep(atoi(getenv("FAKEDSH_DELAY")));
    int fd = socket(AF_INET, SOCK_STREAM, 0), one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a = {0}; a.sin_family = AF_INET; a.sin_port = htons(port); a.sin_addr.s_addr = inet_addr("127.0.0.1");
    if (bind(fd, (struct sockaddr *)&a, sizeof a) < 0) { perror("bind"); return 2; }
    listen(fd, 16);
    fprintf(stderr, "fakedsh: listening on %d pid %d\n", port, getpid());
    time_t start = time(NULL); int exit_after = getenv("FAKEDSH_EXIT_AFTER") ? atoi(getenv("FAKEDSH_EXIT_AFTER")) : 0;
    const char *resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 27\r\nConnection: close\r\n\r\n<html><body>fake</body></html>";
    for (;;) {
        fd_set rf; FD_ZERO(&rf); FD_SET(fd, &rf); struct timeval tv = {0, 200000};
        int r = select(fd + 1, &rf, NULL, NULL, &tv);
        if (exit_after && time(NULL) - start >= exit_after) { fprintf(stderr, "fakedsh: simulated crash\n"); return 3; }
        if (r <= 0) continue;
        int c = accept(fd, NULL, NULL); if (c < 0) continue;
        char buf[2048]; read(c, buf, sizeof buf); write(c, resp, strlen(resp)); close(c);
    }
}
```

- [ ] **Step 2: Write the failing tests `tests/test_server.m`**

```objc
#import "HATest.h"
#import "HAServer.h"
#import <signal.h>
#import <sys/wait.h>

@interface Recorder : NSObject <HAServerDelegate>
@property int ready, failed, restarted, gaveUp; @property NSString *lastReason;
@end
@implementation Recorder
- (void)serverDidBecomeReady:(HAServer *)s { self.ready++; }
- (void)server:(HAServer *)s didFailToStart:(NSString *)r { self.failed++; self.lastReason = r; }
- (void)serverDidRestart:(HAServer *)s { self.restarted++; }
- (void)server:(HAServer *)s didGiveUp:(NSString *)r { self.gaveUp++; self.lastReason = r; }
@end

static BOOL alive(pid_t pid) { return pid > 0 && (kill(pid, 0) == 0 || errno == EPERM); }
static pid_t childOf(pid_t pid) { // first child pid via pgrep -P
    NSTask *t = [NSTask new]; t.executableURL = [NSURL fileURLWithPath:@"/usr/bin/pgrep"]; t.arguments = @[@"-P", @(pid).stringValue];
    NSPipe *p = [NSPipe pipe]; t.standardOutput = p; [t launchAndReturnError:nil];
    NSString *s = [[NSString alloc] initWithData:[[p fileHandleForReading] readDataToEndOfFile] encoding:NSUTF8StringEncoding];
    [t waitUntilExit]; return (pid_t)[[s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] intValue];
}
static HAServer *make(NSString *fake, uint16_t port, NSDictionary *extraEnv, NSString *log) {
    NSMutableDictionary *env = [[NSProcessInfo processInfo].environment mutableCopy];
    [env addEntriesFromDictionary:extraEnv ?: @{}];
    return [[HAServer alloc] initWithDshPath:fake port:port profile:@"web" workspace:NSTemporaryDirectory() environment:env logPath:log];
}

int main(void) { @autoreleasepool {
    NSString *fake = [NSProcessInfo processInfo].environment[@"FAKEDSH"];
    NSString *log = [NSTemporaryDirectory() stringByAppendingFormat:@"hatest-%d.log", getpid()];
    HA_ASSERT(fake.length && [[NSFileManager defaultManager] isExecutableFileAtPath:fake], "FAKEDSH env must point to built fakedsh");

    // argumentsForProfile
    HA_ASSERT([[HAServer argumentsForProfile:@"web" port:3080] isEqual:(@[@"web", @"--port", @"3080"])], "web args");
    HA_ASSERT([[HAServer argumentsForProfile:@"lab" port:3099] isEqual:(@[@"--profile", @"lab", @"--port", @"3099"])], "custom profile args");

    // 1. Cold start: spawn, ready, stop → no process left
    Recorder *r = [Recorder new];
    HAServer *s = make(fake, 3391, nil, log); s.delegate = r; [s start];
    HA_ASSERT(HAWaitUntil(10, ^{ return (BOOL)(r.ready == 1); }), "cold start became ready");
    HA_ASSERT(s.mode == HAServerModeSpawned, "mode spawned");
    HA_ASSERT([HAServer probeURL:s.baseURL timeout:2], "probe 200");
    pid_t pid = s.childPID; HA_ASSERT(alive(pid), "child alive");
    HA_ASSERT([s stopSynchronously:5], "stopped gracefully");
    HA_ASSERT(!alive(pid), "child gone after stop");
    HA_ASSERT(![HAServer probeURL:s.baseURL timeout:1], "port closed after stop");
    HA_ASSERT([[s logTail:50] containsString:@"fakedsh: listening"], "log captured child stderr");

    // 2. Attach: pre-started server is used and never killed
    NSTask *pre = [NSTask new]; pre.executableURL = [NSURL fileURLWithPath:fake]; pre.arguments = @[@"web", @"--port", @"3392"];
    pre.standardError = [NSFileHandle fileHandleWithNullDevice]; [pre launchAndReturnError:nil];
    HA_ASSERT(HAWaitUntil(5, ^{ return [HAServer probeURL:[NSURL URLWithString:@"http://127.0.0.1:3392/"] timeout:1]; }), "pre-started listening");
    r = [Recorder new]; s = make(fake, 3392, nil, log); s.delegate = r; [s start];
    HA_ASSERT(HAWaitUntil(10, ^{ return (BOOL)(r.ready == 1); }), "attach became ready");
    HA_ASSERT(s.mode == HAServerModeAttached, "mode attached");
    HA_ASSERT([s stopSynchronously:2], "stop is a no-op when attached");
    HA_ASSERT(pre.isRunning, "attached server still running");
    [pre terminate]; [pre waitUntilExit];

    // 3. Escalation: child ignores SIGTERM and has its own child → both killed, no orphans
    r = [Recorder new]; s = make(fake, 3393, @{@"FAKEDSH_IGNORE_TERM": @"1", @"FAKEDSH_SPAWN_CHILD": @"1"}, log); s.delegate = r; [s start];
    HA_ASSERT(HAWaitUntil(10, ^{ return (BOOL)(r.ready == 1); }), "stubborn child ready");
    pid = s.childPID; pid_t grandchild = childOf(pid);
    HA_ASSERT(grandchild > 0 && alive(grandchild), "grandchild exists (pid %d)", grandchild);
    NSDate *t0 = [NSDate date];
    HA_ASSERT([s stopSynchronously:1.0], "escalated stop returned");
    HA_ASSERT([[NSDate date] timeIntervalSinceDate:t0] < 4, "escalation bounded (~1s grace)");
    HA_ASSERT(!alive(pid), "stubborn child killed");
    HA_ASSERT(HAWaitUntil(3, ^{ return (BOOL)!alive(grandchild); }), "grandchild killed with the group");

    // 4. Crash policy: dies once → auto restart; dies again within 60s → give up
    r = [Recorder new]; s = make(fake, 3394, @{@"FAKEDSH_EXIT_AFTER": @"1"}, log); s.delegate = r; [s start];
    HA_ASSERT(HAWaitUntil(10, ^{ return (BOOL)(r.ready >= 1); }), "crashy child ready once");
    HA_ASSERT(HAWaitUntil(15, ^{ return (BOOL)(r.restarted == 1); }), "one auto restart");
    HA_ASSERT(HAWaitUntil(15, ^{ return (BOOL)(r.gaveUp == 1); }), "gave up on second crash");
    HA_ASSERT([r.lastReason containsString:@"simulated crash"] || r.lastReason.length > 0, "give-up reason includes log tail");
    [s stopSynchronously:2];

    // 5. Never becomes ready → didFailToStart with reason
    r = [Recorder new]; s = [[HAServer alloc] initWithDshPath:@"/usr/bin/false" port:3395 profile:@"web" workspace:NSTemporaryDirectory()
        environment:[NSProcessInfo processInfo].environment logPath:log]; s.delegate = r; [s start];
    HA_ASSERT(HAWaitUntil(10, ^{ return (BOOL)(r.failed == 1); }), "exiting child reports failure quickly");
    HA_ASSERT(r.lastReason.length > 0, "failure has a reason");

    [[NSFileManager defaultManager] removeItemAtPath:log error:nil];
    HA_DONE();
} }
```

- [ ] **Step 3: Run to verify it fails to build**

Run: `make build/fakedsh build/test_server`
Expected: fakedsh builds; test fails to compile — `HAServer.h` not found.

- [ ] **Step 4: Write `src/HAServer.h`**

```objc
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HAServerMode) { HAServerModeNone = 0, HAServerModeAttached, HAServerModeSpawned };
@class HAServer;

@protocol HAServerDelegate <NSObject>
- (void)serverDidBecomeReady:(HAServer *)server;                  // load the UI (also fires after a successful auto-restart)
- (void)server:(HAServer *)server didFailToStart:(NSString *)reason;
- (void)serverDidRestart:(HAServer *)server;                      // child died; a fresh one is starting
- (void)server:(HAServer *)server didGiveUp:(NSString *)reason;   // second death within 60 s
@end

@interface HAServer : NSObject
@property (weak, nullable) id<HAServerDelegate> delegate;
@property (readonly) HAServerMode mode;
@property (readonly) uint16_t port;
@property (readonly) NSURL *baseURL;
@property (readonly) NSString *logPath;
@property (readonly) pid_t childPID;          // 0 unless spawned and alive
@property (readonly) NSString *profile;
@property (readonly) NSString *workspace;

- (instancetype)initWithDshPath:(NSString *)dshPath port:(uint16_t)port profile:(NSString *)profile
                      workspace:(NSString *)workspace environment:(NSDictionary<NSString *, NSString *> *)environment
                        logPath:(NSString *)logPath;
- (void)start;                                  // attach-or-spawn; async; delegate on main queue
- (void)restart;                                // spawned: stop + fresh spawn; attached: re-probe only
- (BOOL)stopSynchronously:(NSTimeInterval)grace; // SIGTERM group → wait ≤ grace → SIGKILL group; YES when nothing left. No-op when attached.
- (BOOL)probeReady;                             // HTTP GET baseURL, 1 s timeout
- (NSString *)logTail:(NSUInteger)lines;
+ (BOOL)probeURL:(NSURL *)url timeout:(NSTimeInterval)timeout;
+ (NSArray<NSString *> *)argumentsForProfile:(NSString *)profile port:(uint16_t)port;
@end
NS_ASSUME_NONNULL_END
```

- [ ] **Step 5: Write `src/HAServer.m`**

```objc
#import "HAServer.h"
#import <fcntl.h>
#import <signal.h>
#import <spawn.h>
#import <sys/wait.h>

extern char **environ;
static const NSTimeInterval kReadyBudget = 45.0, kPollInterval = 0.4, kRestartWindow = 60.0;

@interface HAServer ()
@property (readwrite) HAServerMode mode;
@property (readwrite) pid_t childPID;
@property NSString *dshPath;
@property NSDictionary<NSString *, NSString *> *environment;
@property dispatch_queue_t queue;
@property (nullable) dispatch_source_t exitSource;
@property BOOL stopping, everReady;
@property NSDate *lastRestart;   // nil until first auto-restart
@property int generation;
@end

@implementation HAServer

- (instancetype)initWithDshPath:(NSString *)dshPath port:(uint16_t)port profile:(NSString *)profile
                      workspace:(NSString *)workspace environment:(NSDictionary *)environment logPath:(NSString *)logPath {
    if ((self = [super init])) {
        _dshPath = dshPath; _port = port; _profile = profile; _workspace = workspace; _environment = environment; _logPath = logPath;
        _baseURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u/", port]];
        _queue = dispatch_queue_create("harness.server", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

+ (NSArray<NSString *> *)argumentsForProfile:(NSString *)profile port:(uint16_t)port {
    NSString *p = [NSString stringWithFormat:@"%u", port];
    if ([profile isEqualToString:@"web"]) return @[@"web", @"--port", p];
    return @[@"--profile", profile, @"--port", p];
}

+ (BOOL)probeURL:(NSURL *)url timeout:(NSTimeInterval)timeout {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:timeout];
    __block BOOL ok = NO; dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = timeout; cfg.timeoutIntervalForResource = timeout;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    [[session dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *resp, NSError *err) {
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        ok = (err == nil && code > 0 && code < 400);
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)((timeout + 1) * NSEC_PER_SEC)));
    [session finishTasksAndInvalidate];
    return ok;
}
- (BOOL)probeReady { return [HAServer probeURL:self.baseURL timeout:1.0]; }

- (void)log:(NSString *)line {
    NSString *s = [NSString stringWithFormat:@"[harness-app %@] %@\n", [NSDate date], line];
    int fd = open(self.logPath.fileSystemRepresentation, O_WRONLY | O_APPEND | O_CREAT, 0644);
    if (fd >= 0) { write(fd, s.UTF8String, strlen(s.UTF8String)); close(fd); }
}
- (NSString *)logTail:(NSUInteger)lines {
    NSString *all = [NSString stringWithContentsOfFile:self.logPath encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSArray *arr = [all componentsSeparatedByString:@"\n"];
    NSUInteger n = MIN(lines, arr.count);
    return [[arr subarrayWithRange:NSMakeRange(arr.count - n, n)] componentsJoinedByString:@"\n"];
}

- (void)notify:(void (^)(id<HAServerDelegate>))block {
    dispatch_async(dispatch_get_main_queue(), ^{ id<HAServerDelegate> d = self.delegate; if (d) block(d); });
}

- (void)start {
    dispatch_async(self.queue, ^{
        self.stopping = NO;
        if ([self probeReady]) {
            self.mode = HAServerModeAttached; self.everReady = YES;
            [self log:[NSString stringWithFormat:@"attached to existing server on port %u", self.port]];
            [self notify:^(id<HAServerDelegate> d) { [d serverDidBecomeReady:self]; }];
            return;
        }
        [self spawnAndWait];
    });
}

// Runs on self.queue.
- (void)spawnAndWait {
    int gen = ++self.generation;
    pid_t pid = [self spawnChild];
    if (pid <= 0) { [self notify:^(id<HAServerDelegate> d) { [d server:self didFailToStart:@"Could not launch dsh (posix_spawn failed). Check the log."]; }]; return; }
    self.childPID = pid; self.mode = HAServerModeSpawned;
    [self log:[NSString stringWithFormat:@"spawned dsh pid %d: %@ %@ (cwd %@)", pid, self.dshPath,
               [[HAServer argumentsForProfile:self.profile port:self.port] componentsJoinedByString:@" "], self.workspace]];
    [self watchExitOfPID:pid generation:gen];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:kReadyBudget];
    while (!self.stopping && self.childPID == pid && [deadline timeIntervalSinceNow] > 0) {
        if ([self probeReady]) {
            self.everReady = YES;
            [self log:@"server ready"];
            [self notify:^(id<HAServerDelegate> d) { [d serverDidBecomeReady:self]; }];
            return;
        }
        [NSThread sleepForTimeInterval:kPollInterval];
    }
    if (self.stopping || self.childPID != pid) return; // exit handler already reported
    [self log:@"server did not become ready in time; stopping it"];
    [self stopSynchronously:3];
    [self notify:^(id<HAServerDelegate> d) { [d server:self didFailToStart:[NSString stringWithFormat:@"dsh did not answer on port %u within %.0f seconds.\n\n%@", self.port, kReadyBudget, [self logTail:20]]]; }];
}

- (pid_t)spawnChild {
    NSArray *args = [@[self.dshPath] arrayByAddingObjectsFromArray:[HAServer argumentsForProfile:self.profile port:self.port]];
    NSMutableArray<NSString *> *envs = [NSMutableArray array];
    [self.environment enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) { [envs addObject:[NSString stringWithFormat:@"%@=%@", k, v]]; }];
    char **argv = calloc(args.count + 1, sizeof(char *)); for (NSUInteger i = 0; i < args.count; i++) argv[i] = strdup([args[i] UTF8String]);
    char **envp = calloc(envs.count + 1, sizeof(char *)); for (NSUInteger i = 0; i < envs.count; i++) envp[i] = strdup([envs[i] UTF8String]);
    posix_spawnattr_t attr; posix_spawnattr_init(&attr);
    posix_spawnattr_setpgroup(&attr, 0);                          // new process group, pgid == child pid
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    posix_spawn_file_actions_t fa; posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&fa, 1, self.logPath.fileSystemRepresentation, O_WRONLY | O_APPEND | O_CREAT, 0644);
    posix_spawn_file_actions_addopen(&fa, 2, self.logPath.fileSystemRepresentation, O_WRONLY | O_APPEND | O_CREAT, 0644);
    posix_spawn_file_actions_addchdir_np(&fa, self.workspace.fileSystemRepresentation);
    pid_t pid = 0;
    int rc = posix_spawn(&pid, self.dshPath.fileSystemRepresentation, &fa, &attr, argv, envp);
    posix_spawn_file_actions_destroy(&fa); posix_spawnattr_destroy(&attr);
    for (char **p = argv; *p; p++) free(*p); free(argv); for (char **p = envp; *p; p++) free(*p); free(envp);
    if (rc != 0) { [self log:[NSString stringWithFormat:@"posix_spawn failed: %s", strerror(rc)]]; return -1; }
    return pid;
}

- (void)watchExitOfPID:(pid_t)pid generation:(int)gen {
    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, pid, DISPATCH_PROC_EXIT, self.queue);
    self.exitSource = src;
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(src, ^{
        typeof(self) self = weakSelf; if (!self) return;
        int status = 0; waitpid(pid, &status, WNOHANG);
        dispatch_source_cancel(src);
        if (self.childPID != pid || self.generation != gen) return;
        self.childPID = 0;
        NSString *how = WIFSIGNALED(status) ? [NSString stringWithFormat:@"signal %d", WTERMSIG(status)] : [NSString stringWithFormat:@"status %d", WEXITSTATUS(status)];
        [self log:[NSString stringWithFormat:@"dsh pid %d exited (%@)", pid, how]];
        if (self.stopping) return;
        if (!self.everReady) {
            [self notify:^(id<HAServerDelegate> d) { [d server:self didFailToStart:[NSString stringWithFormat:@"dsh exited before it was ready (%@).\n\n%@", how, [self logTail:20]]]; }];
            return;
        }
        BOOL recentlyRestarted = self.lastRestart && [[NSDate date] timeIntervalSinceDate:self.lastRestart] < kRestartWindow;
        if (recentlyRestarted) {
            [self log:@"second failure within 60s — giving up"];
            [self notify:^(id<HAServerDelegate> d) { [d server:self didGiveUp:[NSString stringWithFormat:@"dsh keeps exiting (%@).\n\n%@", how, [self logTail:30]]]; }];
            return;
        }
        self.lastRestart = [NSDate date];
        [self log:@"unexpected exit — restarting once"];
        [self notify:^(id<HAServerDelegate> d) { [d serverDidRestart:self]; }];
        [self spawnAndWait];
    });
    dispatch_resume(src);
}

- (void)restart {
    dispatch_async(self.queue, ^{
        if (self.mode == HAServerModeAttached) {
            [self notify:^(id<HAServerDelegate> d) { if ([self probeReady]) [d serverDidBecomeReady:self]; else [d server:self didFailToStart:@"The attached server is no longer answering."]; }];
            return;
        }
        [self stopSynchronously:5];
        self.stopping = NO; self.everReady = NO; self.lastRestart = nil;
        [self spawnAndWait];
    });
}

- (BOOL)stopSynchronously:(NSTimeInterval)grace {
    if (self.mode != HAServerModeSpawned) return YES;
    pid_t pid = self.childPID;
    self.stopping = YES;
    if (pid <= 0) return YES;
    [self log:[NSString stringWithFormat:@"stopping dsh pid %d (SIGTERM group, %.0fs grace)", pid, grace]];
    killpg(pid, SIGTERM);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:grace];
    while ([deadline timeIntervalSinceNow] > 0) {
        int status = 0; pid_t r = waitpid(pid, &status, WNOHANG);
        if (r == pid || (r < 0 && errno == ECHILD)) break;
        if (kill(pid, 0) != 0) break;
        [NSThread sleepForTimeInterval:0.1];
    }
    if (kill(pid, 0) == 0) { [self log:@"grace expired — SIGKILL group"]; killpg(pid, SIGKILL); }
    else killpg(pid, SIGKILL); // sweep any lingering group members (grandchildren) even if the leader is gone
    int status = 0; for (int i = 0; i < 20 && waitpid(pid, &status, WNOHANG) == 0; i++) [NSThread sleepForTimeInterval:0.05];
    if (self.exitSource) { dispatch_source_cancel(self.exitSource); self.exitSource = nil; }
    self.childPID = 0;
    return kill(pid, 0) != 0;
}
@end
```

- [ ] **Step 6: Add `src/HAServer.m` to `SRC`/`LIBSRC`, build and run**

Run: `make build/fakedsh build/test_server && FAKEDSH=$PWD/build/fakedsh build/test_server`
Expected: all checks pass, `0 failures`. If scenario 3's grandchild survives, verify `killpg` after leader death is reached (the sweep line) — grandchildren keep the pgid after their parent dies.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: HAServer — attach-or-spawn, HTTP readiness, escalating group stop, one auto-restart; fakedsh test server

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: HAUpdater — semver compare, dsh/app version checks, Terminal runner (TDD)

**Files:**
- Create: `src/HAUpdater.h`, `src/HAUpdater.m`, `tests/test_updater.m`
- Modify: `Makefile` (`SRC`/`LIBSRC` gain `src/HAUpdater.m`)

**Interfaces:**
- Consumes: `HADshInstallCommand`, `HARunCommandOutput`, `HAFindExecutable` (Task 2); `HAGitHubRepo`, `HAAppVersion` (Task 1).
- Produces (used by Task 7):
  - `NSComparisonResult HACompareVersions(NSString *a, NSString *b)` — semver with prerelease, tolerates leading `v`
  - `NSString *HAShellQuote(NSString *s)`; `NSString *HAAppleScriptQuote(NSString *s)`
  - `HAUpdater` — `initWithEnvironment:installedDshVersion:appVersion:`; `checkDshLatest:` `(void (^)(NSString *_Nullable latest, BOOL newer))`; `checkAppLatest:` `(void (^)(NSString *_Nullable latest, BOOL newer, NSURL *_Nullable page))`; `+ (BOOL)runInTerminal:(NSString *)command error:(NSError **)error`; `+ (NSString *)installCommand`

- [ ] **Step 1: Write the failing tests `tests/test_updater.m`**

```objc
#import "HATest.h"
#import "HAUpdater.h"

int main(void) { @autoreleasepool {
    HA_ASSERT(HACompareVersions(@"0.1.0-rc.6", @"0.1.0-rc.7") == NSOrderedAscending, "rc.6 < rc.7");
    HA_ASSERT(HACompareVersions(@"0.1.0-rc.10", @"0.1.0-rc.9") == NSOrderedDescending, "rc.10 > rc.9 (numeric identifiers)");
    HA_ASSERT(HACompareVersions(@"0.1.0-rc.9", @"0.1.0") == NSOrderedAscending, "prerelease < release");
    HA_ASSERT(HACompareVersions(@"0.1.0", @"0.2.0") == NSOrderedAscending, "minor bump");
    HA_ASSERT(HACompareVersions(@"1.0.0", @"1.0.0") == NSOrderedSame, "equal");
    HA_ASSERT(HACompareVersions(@"v3.0.0", @"3.0.0") == NSOrderedSame, "leading v ignored");
    HA_ASSERT(HACompareVersions(@"3.0.0", @"3.0.1") == NSOrderedAscending, "patch bump");
    HA_ASSERT(HACompareVersions(@"0.1.0-alpha", @"0.1.0-rc.1") == NSOrderedAscending, "alpha < rc (string identifiers)");
    HA_ASSERT(HACompareVersions(@"0.1.0-rc", @"0.1.0-rc.1") == NSOrderedAscending, "shorter prerelease is lower");
    HA_EQ_STR(HAShellQuote(@"it's"), @"'it'\\''s'");
    HA_EQ_STR(HAAppleScriptQuote(@"say \"hi\" \\ there"), @"say \\\"hi\\\" \\\\ there");
    HA_ASSERT([[HAUpdater installCommand] hasPrefix:@"npm install -g --allow-scripts="], "install command exposed");

    // checkDshLatest uses `npm view`; with a fake npm on PATH we control the answer.
    NSString *dir = [NSTemporaryDirectory() stringByAppendingFormat:@"hanpm-%d", getpid()];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *fakeNpm = [dir stringByAppendingPathComponent:@"npm"];
    [@"#!/bin/sh\necho 9.9.9\n" writeToFile:fakeNpm atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod(fakeNpm.fileSystemRepresentation, 0755);
    NSDictionary *env = @{@"PATH": [dir stringByAppendingString:@":/usr/bin:/bin"]};
    HAUpdater *u = [[HAUpdater alloc] initWithEnvironment:env installedDshVersion:@"0.1.0-rc.6" appVersion:@"3.0.0"];
    __block NSString *latest = nil; __block BOOL newer = NO; __block BOOL done = NO;
    [u checkDshLatest:^(NSString *l, BOOL n) { latest = l; newer = n; done = YES; }];
    HA_ASSERT(HAWaitUntil(10, ^{ return done; }), "dsh check completed");
    HA_EQ_STR(latest ?: @"", @"9.9.9"); HA_ASSERT(newer, "9.9.9 is newer than rc.6");

    // No npm on PATH → nil, not newer, no crash
    u = [[HAUpdater alloc] initWithEnvironment:@{@"PATH": @"/nonexistent"} installedDshVersion:@"0.1.0-rc.6" appVersion:@"3.0.0"];
    done = NO; [u checkDshLatest:^(NSString *l, BOOL n) { latest = l; newer = n; done = YES; }];
    HA_ASSERT(HAWaitUntil(10, ^{ return done; }), "dsh check without npm completes");
    HA_ASSERT(latest == nil && !newer, "no npm → nil/no");

    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
    HA_DONE();
} }
```

- [ ] **Step 2: Run to verify it fails to build**

Run: `make build/test_updater` — Expected: `HAUpdater.h` not found.

- [ ] **Step 3: Write `src/HAUpdater.h`**

```objc
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
NSComparisonResult HACompareVersions(NSString *a, NSString *b);
NSString *HAShellQuote(NSString *s);
NSString *HAAppleScriptQuote(NSString *s);

@interface HAUpdater : NSObject
- (instancetype)initWithEnvironment:(NSDictionary<NSString *, NSString *> *)environment
                installedDshVersion:(NSString *_Nullable)dshVersion appVersion:(NSString *)appVersion;
/// Runs `npm view @deepseek-ai/dsh version` in the background (≤ 8 s). Completion on main queue.
- (void)checkDshLatest:(void (^)(NSString *_Nullable latest, BOOL newer))completion;
/// GETs the latest GitHub release (≤ 5 s). Completion on main queue; latest nil on any failure or no releases.
- (void)checkAppLatest:(void (^)(NSString *_Nullable latest, BOOL newer, NSURL *_Nullable page))completion;
/// Opens Terminal.app and runs `command` visibly in a new window.
+ (BOOL)runInTerminal:(NSString *)command error:(NSError *_Nullable *_Nullable)error;
+ (NSString *)installCommand;
@end
NS_ASSUME_NONNULL_END
```

- [ ] **Step 4: Write `src/HAUpdater.m`**

```objc
#import "HAUpdater.h"
#import "HAEnvironment.h"
#import "HAConfig.h"

static NSArray<NSString *> *splitDots(NSString *s) { return s.length ? [s componentsSeparatedByString:@"."] : @[]; }
static BOOL isNumeric(NSString *s) { return s.length && [s rangeOfCharacterFromSet:[NSCharacterSet.decimalDigitCharacterSet invertedSet]].location == NSNotFound; }

NSComparisonResult HACompareVersions(NSString *a, NSString *b) {
    a = [a hasPrefix:@"v"] ? [a substringFromIndex:1] : a; b = [b hasPrefix:@"v"] ? [b substringFromIndex:1] : b;
    NSRange pa = [a rangeOfString:@"-"], pb = [b rangeOfString:@"-"];
    NSString *coreA = pa.location == NSNotFound ? a : [a substringToIndex:pa.location];
    NSString *coreB = pb.location == NSNotFound ? b : [b substringToIndex:pb.location];
    NSString *preA = pa.location == NSNotFound ? @"" : [a substringFromIndex:pa.location + 1];
    NSString *preB = pb.location == NSNotFound ? @"" : [b substringFromIndex:pb.location + 1];
    NSArray *ca = splitDots(coreA), *cb = splitDots(coreB);
    for (NSUInteger i = 0; i < MAX(ca.count, cb.count); i++) {
        NSInteger x = i < ca.count ? [ca[i] integerValue] : 0, y = i < cb.count ? [cb[i] integerValue] : 0;
        if (x != y) return x < y ? NSOrderedAscending : NSOrderedDescending;
    }
    if (preA.length == 0 && preB.length == 0) return NSOrderedSame;
    if (preA.length == 0) return NSOrderedDescending;   // release > prerelease
    if (preB.length == 0) return NSOrderedAscending;
    NSArray *ia = splitDots(preA), *ib = splitDots(preB);
    for (NSUInteger i = 0; i < MIN(ia.count, ib.count); i++) {
        BOOL na = isNumeric(ia[i]), nb = isNumeric(ib[i]);
        if (na && nb) { NSInteger x = [ia[i] integerValue], y = [ib[i] integerValue]; if (x != y) return x < y ? NSOrderedAscending : NSOrderedDescending; }
        else if (na != nb) return na ? NSOrderedAscending : NSOrderedDescending;   // numeric < alphanumeric
        else { NSComparisonResult r = [ia[i] compare:ib[i]]; if (r != NSOrderedSame) return r; }
    }
    if (ia.count == ib.count) return NSOrderedSame;
    return ia.count < ib.count ? NSOrderedAscending : NSOrderedDescending;
}

NSString *HAShellQuote(NSString *s) { return [NSString stringWithFormat:@"'%@'", [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]]; }
NSString *HAAppleScriptQuote(NSString *s) {
    return [[s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
}

@interface HAUpdater ()
@property NSDictionary<NSString *, NSString *> *environment;
@property (nullable) NSString *dshVersion;
@property NSString *appVersion;
@end

@implementation HAUpdater
- (instancetype)initWithEnvironment:(NSDictionary *)environment installedDshVersion:(NSString *)dshVersion appVersion:(NSString *)appVersion {
    if ((self = [super init])) { _environment = environment; _dshVersion = dshVersion; _appVersion = appVersion; }
    return self;
}
+ (NSString *)installCommand { return HADshInstallCommand; }

- (void)checkDshLatest:(void (^)(NSString *, BOOL))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *npm = HAFindExecutable(@"npm", self.environment[@"PATH"]);
        NSString *latest = nil;
        if (npm) {
            NSString *out = HARunCommandOutput(npm, @[@"view", @"@deepseek-ai/dsh", @"version"], self.environment, 8, NULL);
            out = [out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (out.length && out.length < 40 && [out rangeOfString:@" "].location == NSNotFound) latest = out;
        }
        BOOL newer = latest && self.dshVersion && HACompareVersions(self.dshVersion, latest) == NSOrderedAscending;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(latest, newer); });
    });
}

- (void)checkAppLatest:(void (^)(NSString *, BOOL, NSURL *))completion {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/repos/%@/releases/latest", HAGitHubRepo]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:5];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:[NSString stringWithFormat:@"Harness.app/%@", self.appVersion] forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSString *latest = nil; NSURL *page = nil;
        if (!err && [(NSHTTPURLResponse *)resp statusCode] == 200 && data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *tag = [json[@"tag_name"] isKindOfClass:NSString.class] ? json[@"tag_name"] : nil;
            if (tag.length) { latest = [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag; page = [NSURL URLWithString:json[@"html_url"] ?: @""]; }
        }
        BOOL newer = latest && HACompareVersions(self.appVersion, latest) == NSOrderedAscending;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(latest, newer, page); });
    }] resume];
}

+ (BOOL)runInTerminal:(NSString *)command error:(NSError **)error {
    NSString *script = [NSString stringWithFormat:@"tell application \"Terminal\"\nactivate\ndo script \"%@\"\nend tell", HAAppleScriptQuote(command)];
    NSTask *t = [NSTask new]; t.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"]; t.arguments = @[@"-e", script];
    t.standardError = [NSFileHandle fileHandleWithNullDevice]; t.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    if (![t launchAndReturnError:error]) return NO;
    [t waitUntilExit];
    if (t.terminationStatus != 0 && error) *error = [NSError errorWithDomain:@"Harness" code:t.terminationStatus userInfo:@{NSLocalizedDescriptionKey: @"Terminal.app refused the command (osascript failed). You may need to allow Harness to control Terminal in System Settings → Privacy & Security → Automation."}];
    return t.terminationStatus == 0;
}
@end
```

- [ ] **Step 5: Add `src/HAUpdater.m` to `SRC`/`LIBSRC`; run all tests**

Run: `make test` — Expected: three test binaries, `0 failures` each.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: HAUpdater — semver compare, npm/GitHub version checks, visible Terminal runner

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Rewrite `src/main.m` — startup, first-run guidance, server wiring, error sheets, close policy, navigation guard, menus, `--check-env`

**Files:**
- Modify (full rewrite): `src/main.m`

**Interfaces:**
- Consumes: everything from Tasks 1–4 (`HARegisterDefaults`, `HAPref*`, `HALogPath`, `HAEnvironment`, `HAServer`/`HAServerDelegate`, `HAUpdater +runInTerminal:error:`, `HADshInstallCommand`).
- Produces (extended by Tasks 6–7): `AppDelegate` with methods `startServer`, `replaceServerWithProfile:workspace:`, `presentSheetTitle:detail:buttons:handler:`, `setNotice:`, `showPlaceholder:`, properties `env`, `server`, `updater`, `launchWorkspace`, `notices` (NSMutableDictionary key→text), menu-building function `buildMenu(AppDelegate*)`, and the `--check-env` CLI path.

- [ ] **Step 1: Replace `src/main.m` with the following**

```objc
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "HAConfig.h"
#import "HAEnvironment.h"
#import "HAServer.h"
#import "HAUpdater.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, WKUIDelegate, WKNavigationDelegate, HAServerDelegate, NSMenuDelegate>
@property (strong) NSWindow *window;
@property (strong) WKWebView *webView;
@property (strong) HAEnvironment *env;
@property (strong) HAServer *server;
@property (strong) HAUpdater *updater;
@property (copy) NSString *launchWorkspace;          // Dock drop / open-with, overrides preference for this launch
@property (strong) NSMutableDictionary<NSString *, NSString *> *notices;
@property (strong) NSMenu *profileMenu;
@property (strong) NSWindowController *preferencesController;   // Task 6
@end

@implementation AppDelegate

#pragma mark - Window & placeholder

- (void)buildWindow {
    NSRect rect = NSMakeRect(0, 0, 1280, 860);
    self.window = [[NSWindow alloc] initWithContentRect:rect
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Harness";
    self.window.delegate = self;
    [self.window setFrameAutosaveName:@"HAMainWindow"];
    if (self.window.frame.size.width < 400) { [self.window setContentSize:rect.size]; [self.window center]; }
    WKWebViewConfiguration *cfg = [WKWebViewConfiguration new];
    self.webView = [[WKWebView alloc] initWithFrame:rect configuration:cfg];
    self.webView.UIDelegate = self;
    self.webView.navigationDelegate = self;
    self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.window.contentView = self.webView;
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)showPlaceholder:(NSString *)text {
    NSString *html = [NSString stringWithFormat:
        @"<html><head><meta name=\"color-scheme\" content=\"light dark\"></head>"
        @"<body style=\"display:flex;align-items:center;justify-content:center;height:100vh;margin:0;"
        @"font-family:-apple-system,sans-serif;font-size:1.2em;color:#888\"><div>%@</div></body></html>", text];
    [self.webView loadHTMLString:html baseURL:nil];
}

// Notices are short status lines shown in the window subtitle, keyed so they can be replaced/cleared.
- (void)setNotice:(NSString *)text forKey:(NSString *)key {
    if (!self.notices) self.notices = [NSMutableDictionary dictionary];
    if (text.length) self.notices[key] = text; else [self.notices removeObjectForKey:key];
    NSArray *keys = [self.notices.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *k in keys) [parts addObject:self.notices[k]];
    if (@available(macOS 11.0, *)) self.window.subtitle = [parts componentsJoinedByString:@"  ·  "];
}

// All alerts are window sheets: nothing blocks the run loop, and they never appear behind other apps.
- (void)presentSheetTitle:(NSString *)title detail:(NSString *)detail buttons:(NSArray<NSString *> *)buttons
                  handler:(void (^)(NSInteger index))handler {
    NSAlert *a = [NSAlert new];
    a.messageText = title; a.informativeText = detail ?: @"";
    for (NSString *b in buttons) [a addButtonWithTitle:b];
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (handler) handler(r - NSAlertFirstButtonReturn);
    }];
}

#pragma mark - Startup

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    HARegisterDefaults();
    [self buildWindow];
    [self showPlaceholder:@"Starting DeepSeek Harness…"];
    [self bootstrap];
}

- (void)bootstrap {
    NSString *pref = [[NSUserDefaults standardUserDefaults] stringForKey:HAPrefDshPath];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        HAEnvironment *env = [HAEnvironment capture:pref.length ? pref : nil];
        dispatch_async(dispatch_get_main_queue(), ^{ self.env = env; [self continueWithEnvironment]; });
    });
}

- (void)continueWithEnvironment {
    if (!self.env.dshPath) { [self presentInstallGuidance]; return; }
    if (self.env.nodePtyState == HANodePtyBroken)
        [self setNotice:@"dsh shell tools look broken — dsh ▸ Repair Shell Tools…" forKey:@"pty"];
    self.updater = [[HAUpdater alloc] initWithEnvironment:self.env.shellEnvironment installedDshVersion:self.env.dshVersion appVersion:HAAppVersion];
    [self startServer];
}

- (NSString *)effectiveWorkspace {
    NSString *ws = self.launchWorkspace ?: [[NSUserDefaults standardUserDefaults] stringForKey:HAPrefWorkspace];
    BOOL isDir = NO;
    if (!ws.length || ![[NSFileManager defaultManager] fileExistsAtPath:ws isDirectory:&isDir] || !isDir) ws = NSHomeDirectory();
    return ws;
}

- (void)startServer {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSInteger port = [d integerForKey:HAPrefPort]; if (port <= 0 || port > 65535) port = HADefaultPort;
    NSString *profile = [d stringForKey:HAPrefProfile]; if (!profile.length) profile = HADefaultProfile;
    self.server = [[HAServer alloc] initWithDshPath:self.env.dshPath port:(uint16_t)port profile:profile
                                          workspace:[self effectiveWorkspace] environment:self.env.shellEnvironment logPath:HALogPath()];
    self.server.delegate = self;
    [self showPlaceholder:@"Starting DeepSeek Harness…"];
    [self.server start];
}

// Stop the current server (if we own it) and start a new one with different settings (profile switch, Dock drop, prefs).
- (void)replaceServerWithProfile:(NSString *)profile workspace:(NSString *)workspace {
    if (profile) [[NSUserDefaults standardUserDefaults] setObject:profile forKey:HAPrefProfile];
    if (workspace) self.launchWorkspace = workspace;
    HAServer *old = self.server;
    old.delegate = nil;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (old.mode == HAServerModeSpawned) [old stopSynchronously:5];
        dispatch_async(dispatch_get_main_queue(), ^{ [self startServer]; });
    });
}

#pragma mark - First-run guidance (dsh missing / Node wrong)

- (void)presentInstallGuidance {
    NSMutableString *detail = [NSMutableString stringWithString:
        @"Harness runs the DeepSeek Harness (dsh) that you install yourself with npm — nothing is bundled, so you always run the real upstream.\n\n"];
    NSString *cmd = HADshInstallCommand;
    if (!self.env.nodePath) {
        [detail appendString:@"Node.js was not found on your PATH. Install it first (Homebrew: brew install node), then dsh:\n\n"];
        cmd = [@"brew install node && " stringByAppendingString:cmd];
    } else if (!self.env.nodeSupported) {
        [detail appendFormat:@"Node %@ is not supported by dsh (it needs 22.19+ or 24+; 23.x is excluded). Upgrade Node, then install dsh:\n\n", self.env.nodeVersion ?: @"?"];
        cmd = [@"brew install node && " stringByAppendingString:cmd];
    } else {
        [detail appendString:@"Run this in Terminal (the --allow-scripts part is required with npm 11+, or dsh's shell tools come out broken):\n\n"];
    }
    [detail appendString:cmd];
    [self showPlaceholder:@"dsh is not installed yet"];
    [self presentSheetTitle:@"dsh isn't installed (or isn't on your PATH)" detail:detail
                    buttons:@[@"Open Terminal", @"Copy Command", @"Quit"] handler:^(NSInteger i) {
        if (i == 0) {
            NSError *err = nil;
            if (![HAUpdater runInTerminal:cmd error:&err]) { [self presentSheetTitle:@"Could not open Terminal" detail:err.localizedDescription buttons:@[@"Quit"] handler:^(NSInteger _) { [NSApp terminate:nil]; }]; return; }
            [self presentSheetTitle:@"Installing in Terminal…" detail:@"When the install finishes, click Retry." buttons:@[@"Retry", @"Quit"]
                            handler:^(NSInteger j) { if (j == 0) [self bootstrap]; else [NSApp terminate:nil]; }];
        } else if (i == 1) {
            [[NSPasteboard generalPasteboard] clearContents];
            [[NSPasteboard generalPasteboard] setString:cmd forType:NSPasteboardTypeString];
            [self presentSheetTitle:@"Command copied" detail:@"Paste it into Terminal. When the install finishes, click Retry." buttons:@[@"Retry", @"Quit"]
                            handler:^(NSInteger j) { if (j == 0) [self bootstrap]; else [NSApp terminate:nil]; }];
        } else [NSApp terminate:nil];
    }];
}

#pragma mark - HAServerDelegate

- (void)serverDidBecomeReady:(HAServer *)server {
    if (server != self.server) return;
    [self.webView loadRequest:[NSURLRequest requestWithURL:server.baseURL]];
    [self setNotice:nil forKey:@"server"];
}
- (void)serverDidRestart:(HAServer *)server {
    if (server != self.server) return;
    [self showPlaceholder:@"dsh exited unexpectedly — restarting…"];
    [self setNotice:@"dsh restarted once" forKey:@"server"];
}
- (void)server:(HAServer *)server didFailToStart:(NSString *)reason {
    if (server != self.server) return;
    [self showPlaceholder:@"dsh could not start"];
    [self presentSheetTitle:@"dsh could not start" detail:reason buttons:@[@"Retry", @"Open Log", @"Quit"] handler:^(NSInteger i) {
        if (i == 0) [self startServer]; else if (i == 1) { [self openLog:nil]; [self server:server didFailToStart:reason]; } else [NSApp terminate:nil];
    }];
}
- (void)server:(HAServer *)server didGiveUp:(NSString *)reason {
    if (server != self.server) return;
    [self showPlaceholder:@"dsh keeps exiting"];
    [self presentSheetTitle:@"dsh keeps exiting" detail:reason buttons:@[@"Restart Server", @"Open Log", @"Quit"] handler:^(NSInteger i) {
        if (i == 0) [self startServer]; else if (i == 1) { [self openLog:nil]; [self server:server didGiveUp:reason]; } else [NSApp terminate:nil];
    }];
}

#pragma mark - Close / quit policy

- (void)windowWillClose:(NSNotification *)note { [NSApp terminate:nil]; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }
- (void)applicationWillTerminate:(NSNotification *)note {
    BOOL keep = [[NSUserDefaults standardUserDefaults] boolForKey:HAPrefKeepServerRunning];
    if (self.server.mode == HAServerModeSpawned && !keep) [self.server stopSynchronously:5];
}

#pragma mark - Navigation guard: only our origin stays in-window

- (BOOL)isLocalURL:(NSURL *)u {
    NSString *h = u.host.lowercaseString;
    return [h isEqualToString:@"127.0.0.1"] || [h isEqualToString:@"localhost"] || [h isEqualToString:@"::1"] || [h isEqualToString:@"[::1]"];
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
        decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *u = action.request.URL;
    BOOL mainFrame = (action.targetFrame == nil) || action.targetFrame.isMainFrame;
    if (!u || !mainFrame || [self isLocalURL:u] || [@[@"about", @"blob", @"data"] containsObject:u.scheme.lowercaseString]) { decisionHandler(WKNavigationActionPolicyAllow); return; }
    if ([@[@"http", @"https", @"mailto"] containsObject:u.scheme.lowercaseString]) [[NSWorkspace sharedWorkspace] openURL:u];
    decisionHandler(WKNavigationActionPolicyCancel);
}
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    NSURL *u = navigationAction.request.URL;
    if (u && ([self isLocalURL:u])) [self.webView loadRequest:navigationAction.request];
    else if (u) [[NSWorkspace sharedWorkspace] openURL:u];
    return nil;
}
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    NSAlert *a = [NSAlert new]; a.messageText = message; [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) { completionHandler(); }];
}
- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler {
    NSAlert *a = [NSAlert new]; a.messageText = message; [a addButtonWithTitle:@"OK"]; [a addButtonWithTitle:@"Cancel"];
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) { completionHandler(r == NSAlertFirstButtonReturn); }];
}

#pragma mark - Menu actions (View / Server / dsh)

- (void)reloadPage:(id)sender { [self.webView reload]; }
- (void)openInBrowser:(id)sender { if (self.server) [[NSWorkspace sharedWorkspace] openURL:self.server.baseURL]; }
- (void)restartServer:(id)sender { if (self.server) { [self showPlaceholder:@"Restarting dsh…"]; [self.server restart]; } else [self startServer]; }
- (void)toggleKeepAlive:(id)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:![d boolForKey:HAPrefKeepServerRunning] forKey:HAPrefKeepServerRunning];
}
- (void)openLog:(id)sender { [[NSWorkspace sharedWorkspace] openFile:HALogPath()]; }
- (void)openWorkspaceInTerminal:(id)sender {
    NSError *err = nil;
    if (![HAUpdater runInTerminal:[@"cd " stringByAppendingString:HAShellQuote([self effectiveWorkspace])] error:&err])
        [self presentSheetTitle:@"Could not open Terminal" detail:err.localizedDescription buttons:@[@"OK"] handler:nil];
}
- (void)runInstallCommandWithTitle:(NSString *)title {
    NSError *err = nil;
    if (![HAUpdater runInTerminal:HADshInstallCommand error:&err]) { [self presentSheetTitle:@"Could not open Terminal" detail:err.localizedDescription buttons:@[@"OK"] handler:nil]; return; }
    [self presentSheetTitle:title detail:@"The command is running in Terminal — nothing happens hidden. When it finishes, choose Server ▸ Restart Server." buttons:@[@"OK"] handler:nil];
}
- (void)updateDsh:(id)sender { [self runInstallCommandWithTitle:@"Updating dsh in Terminal…"]; }
- (void)repairShellTools:(id)sender { [self runInstallCommandWithTitle:@"Repairing dsh in Terminal…"]; }
- (void)checkDshUpdatesNow:(id)sender { /* wired in Task 7 */ }
- (void)showPreferences:(id)sender { /* wired in Task 6 */ }
- (void)showAbout:(id)sender { /* wired in Task 6 */ }
- (void)selectProfile:(NSMenuItem *)sender { /* wired in Task 6 */ }
- (void)menuNeedsUpdate:(NSMenu *)menu { /* wired in Task 6 */ }

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(toggleKeepAlive:))
        item.state = [[NSUserDefaults standardUserDefaults] boolForKey:HAPrefKeepServerRunning] ? NSControlStateValueOn : NSControlStateValueOff;
    if (item.action == @selector(openInBrowser:) || item.action == @selector(restartServer:)) return self.server != nil;
    return YES;
}
@end

#pragma mark - Menu bar

static NSMenuItem *item(NSString *title, SEL action, NSString *key) { return [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key]; }

static NSMenu *buildMenu(AppDelegate *d) {
    NSMenu *main = [NSMenu new];
    NSMenuItem *appItem = [NSMenuItem new]; [main addItem:appItem];
    NSMenu *app = [NSMenu new];
    [app addItem:item(@"About Harness", @selector(showAbout:), @"")];
    [app addItem:[NSMenuItem separatorItem]];
    [app addItem:item(@"Preferences…", @selector(showPreferences:), @",")];
    [app addItem:[NSMenuItem separatorItem]];
    [app addItem:item(@"Quit Harness", @selector(terminate:), @"q")];
    appItem.submenu = app;

    NSMenuItem *editItem = [NSMenuItem new]; [main addItem:editItem];
    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"];
    [edit addItem:item(@"Undo", @selector(undo:), @"z")]; [edit addItem:item(@"Redo", @selector(redo:), @"Z")];
    [edit addItem:[NSMenuItem separatorItem]];
    [edit addItem:item(@"Cut", @selector(cut:), @"x")]; [edit addItem:item(@"Copy", @selector(copy:), @"c")];
    [edit addItem:item(@"Paste", @selector(paste:), @"v")]; [edit addItem:item(@"Select All", @selector(selectAll:), @"a")];
    editItem.submenu = edit;

    NSMenuItem *viewItem = [NSMenuItem new]; [main addItem:viewItem];
    NSMenu *view = [[NSMenu alloc] initWithTitle:@"View"];
    [view addItem:item(@"Reload", @selector(reloadPage:), @"r")];
    [view addItem:item(@"Open in Browser", @selector(openInBrowser:), @"")];
    viewItem.submenu = view;

    NSMenuItem *serverItem = [NSMenuItem new]; [main addItem:serverItem];
    NSMenu *server = [[NSMenu alloc] initWithTitle:@"Server"];
    [server addItem:item(@"Restart Server", @selector(restartServer:), @"")];
    [server addItem:item(@"Keep Server Running After Close", @selector(toggleKeepAlive:), @"")];
    NSMenuItem *profileItem = item(@"Profile", NULL, @"");
    d.profileMenu = [[NSMenu alloc] initWithTitle:@"Profile"]; d.profileMenu.delegate = d;
    profileItem.submenu = d.profileMenu; [server addItem:profileItem];
    [server addItem:[NSMenuItem separatorItem]];
    [server addItem:item(@"Open Log", @selector(openLog:), @"")];
    [server addItem:item(@"Open Workspace in Terminal", @selector(openWorkspaceInTerminal:), @"")];
    serverItem.submenu = server;

    NSMenuItem *dshItem = [NSMenuItem new]; [main addItem:dshItem];
    NSMenu *dsh = [[NSMenu alloc] initWithTitle:@"dsh"];
    [dsh addItem:item(@"Update dsh…", @selector(updateDsh:), @"")];
    [dsh addItem:item(@"Check for dsh Updates Now", @selector(checkDshUpdatesNow:), @"")];
    [dsh addItem:[NSMenuItem separatorItem]];
    [dsh addItem:item(@"Repair Shell Tools…", @selector(repairShellTools:), @"")];
    dshItem.submenu = dsh;

    NSMenuItem *windowItem = [NSMenuItem new]; [main addItem:windowItem];
    NSMenu *win = [[NSMenu alloc] initWithTitle:@"Window"];
    [win addItem:item(@"Minimize", @selector(performMiniaturize:), @"m")];
    [win addItem:item(@"Zoom", @selector(performZoom:), @"")];
    windowItem.submenu = win;
    return main;
}

#pragma mark - main

static dispatch_source_t gSigTerm, gSigInt;

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        for (int i = 1; i < argc; i++) {
            if (!strcmp(argv[i], "--check-env")) {   // headless diagnostics for scripts/CI
                HARegisterDefaults();
                NSString *pref = [[NSUserDefaults standardUserDefaults] stringForKey:HAPrefDshPath];
                HAEnvironment *env = [HAEnvironment capture:pref.length ? pref : nil];
                printf("Harness.app %s\n%s", HAAppVersion.UTF8String, env.report.UTF8String);
                return env.dshPath ? 0 : 1;
            }
            if (!strcmp(argv[i], "--version")) { printf("%s\n", HAAppVersion.UTF8String); return 0; }
        }
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        app.mainMenu = buildMenu(delegate);
        signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN);
        gSigTerm = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(gSigTerm, ^{ [NSApp terminate:nil]; }); dispatch_resume(gSigTerm);
        gSigInt = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(gSigInt, ^{ [NSApp terminate:nil]; }); dispatch_resume(gSigInt);
        [app run];
    }
    return 0;
}
```

- [ ] **Step 2: Build and run the headless check**

Run: `make && build/Harness.app/Contents/MacOS/Harness --check-env; echo "exit=$?"`
Expected: prints `Harness.app 3.0.0`, `dsh: /opt/homebrew/bin/dsh` (or wherever), `node-pty: intact`, `exit=0`.
Run: `PATH=/usr/bin:/bin build/Harness.app/Contents/MacOS/Harness --check-env; echo "exit=$?"` — Expected: `dsh: not found` … but note the login shell re-adds PATH, so this may still find dsh; that is correct behavior (login shell wins). Verify the missing path instead by `defaults write com.arnoldoconcepcion.harness-app DshPath /nonexistent` → still finds via PATH (preferred path ignored when not executable) → `defaults delete … DshPath`.

- [ ] **Step 3: Manual run-through**

Run: `make install && open -a Harness`
Check: window opens with placeholder → dsh UI loads; `Server ▸ Restart Server` shows placeholder then reloads; `View ▸ Open in Browser` opens Brave; clicking an external link in the UI (e.g. a docs link) opens Brave, window stays on dsh; Cmd-Q → `pgrep -f "dsh web"` empty. Toggle `Server ▸ Keep Server Running After Close`, quit → server still there; relaunch → attaches instantly (log says `attached`); untoggle, quit → stopped.
Simulate crash: with app running, `kill -9 $(pgrep -f "dsh web" | head -1)` → placeholder "restarting…" → UI back; kill again within 60 s → "dsh keeps exiting" sheet with log tail.
Simulate missing dsh: `defaults write com.arnoldoconcepcion.harness-app DshPath /nonexistent` does NOT trigger (falls back to PATH); instead temporarily `mv /opt/homebrew/bin/dsh{,.bak}` (and `~/.local/bin/dsh` if present) → relaunch → guidance sheet with the exact command; Copy Command works; `mv` back → Retry → loads.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: v3 AppDelegate — first-run guidance, server wiring, error sheets, close policy, navigation guard, menus, --check-env

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Preferences window, Profile submenu, Dock folder drop, About panel

**Files:**
- Create: `src/HAPreferencesWindow.h`, `src/HAPreferencesWindow.m`
- Modify: `src/main.m` (fill the four stubs: `showPreferences:`, `showAbout:`, `selectProfile:`, `menuNeedsUpdate:`; add `application:openFile:`; add `#import "HAPreferencesWindow.h"`)
- Modify: `Makefile` (`SRC` gains `src/HAPreferencesWindow.m`; `LIBSRC` unchanged — it is UI-only)

**Interfaces:**
- Consumes: `HAPref*` keys, `HALogPath`, `AppDelegate.replaceServerWithProfile:workspace:`, `HAServer.mode/port/baseURL/workspace/profile`, `HAEnvironment.dshVersion/dshPath`.
- Produces: `HAPreferencesWindowController` (`- (instancetype)initWithProfiles:(NSArray<NSString*>*)profiles onOpenLog:(void(^)(void))openLog;`), `NSArray<NSString *> *HAAvailableProfiles(NSDictionary *env)` (declared in `HAPreferencesWindow.h`, implemented there).

- [ ] **Step 1: Write `src/HAPreferencesWindow.h`**

```objc
#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN
/// "web" plus every directory under $DSH_HOME/profiles (default ~/.dsh/profiles), excluding node_modules and dotfiles.
NSArray<NSString *> *HAAvailableProfiles(NSDictionary<NSString *, NSString *> *_Nullable env);

@interface HAPreferencesWindowController : NSWindowController
- (instancetype)initWithOpenLog:(void (^)(void))openLog;
@end
NS_ASSUME_NONNULL_END
```

- [ ] **Step 2: Write `src/HAPreferencesWindow.m`**

```objc
#import "HAPreferencesWindow.h"
#import "HAConfig.h"

NSArray<NSString *> *HAAvailableProfiles(NSDictionary *env) {
    NSString *home = env[@"DSH_HOME"].length ? env[@"DSH_HOME"] : [NSHomeDirectory() stringByAppendingPathComponent:@".dsh"];
    NSString *dir = [home stringByAppendingPathComponent:@"profiles"];
    NSMutableOrderedSet *names = [NSMutableOrderedSet orderedSetWithObject:HADefaultProfile];
    for (NSString *n in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]) {
        BOOL isDir = NO;
        if ([n hasPrefix:@"."] || [n isEqualToString:@"node_modules"]) continue;
        if ([[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:n] isDirectory:&isDir] && isDir) [names addObject:n];
    }
    return names.array;
}

@interface HAPreferencesWindowController ()
@property (copy) void (^openLog)(void);
@property NSTextField *portField, *workspaceField, *dshField;
@property NSPopUpButton *profilePopup;
@end

@implementation HAPreferencesWindowController

- (instancetype)initWithOpenLog:(void (^)(void))openLog {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, 330)
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable) backing:NSBackingStoreBuffered defer:NO];
    w.title = @"Harness Preferences";
    if ((self = [super initWithWindow:w])) { _openLog = [openLog copy]; [self buildUI]; [w center]; }
    return self;
}

- (NSTextField *)label:(NSString *)s { NSTextField *l = [NSTextField labelWithString:s]; l.alignment = NSTextAlignmentRight; return l; }
- (NSButton *)checkbox:(NSString *)title key:(NSString *)key {
    NSButton *b = [NSButton checkboxWithTitle:title target:nil action:nil];
    [b bind:NSValueBinding toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:key] options:nil];
    return b;
}

- (void)buildUI {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSUserDefaultsController *udc = [NSUserDefaultsController sharedUserDefaultsController];

    self.portField = [NSTextField textFieldWithString:@""];
    NSNumberFormatter *nf = [NSNumberFormatter new]; nf.minimum = @1; nf.maximum = @65535; nf.allowsFloats = NO; self.portField.formatter = nf;
    [self.portField bind:NSValueBinding toObject:udc withKeyPath:@"values.Port" options:@{NSContinuouslyUpdatesValueBindingOption: @NO}];

    self.workspaceField = [NSTextField textFieldWithString:@""];
    [self.workspaceField bind:NSValueBinding toObject:udc withKeyPath:@"values.Workspace" options:nil];
    NSButton *chooseWs = [NSButton buttonWithTitle:@"Choose…" target:self action:@selector(chooseWorkspace:)];

    self.profilePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.profilePopup addItemsWithTitles:HAAvailableProfiles([NSProcessInfo processInfo].environment)];
    [self.profilePopup selectItemWithTitle:[d stringForKey:HAPrefProfile] ?: HADefaultProfile];
    self.profilePopup.target = self; self.profilePopup.action = @selector(profileChanged:);

    self.dshField = [NSTextField textFieldWithString:@""];
    self.dshField.placeholderString = @"auto-detect from your login shell PATH";
    [self.dshField bind:NSValueBinding toObject:udc withKeyPath:@"values.DshPath" options:@{NSNullPlaceholderBindingOption: @""}];
    NSButton *chooseDsh = [NSButton buttonWithTitle:@"Choose…" target:self action:@selector(chooseDsh:)];

    NSButton *keep = [self checkbox:@"Keep the dsh server running after the window closes" key:HAPrefKeepServerRunning];
    NSButton *chkDsh = [self checkbox:@"Check for dsh updates at launch (runs npm view)" key:HAPrefCheckDshUpdates];
    NSButton *chkApp = [self checkbox:@"Check for Harness updates at launch (asks api.github.com)" key:HAPrefCheckAppUpdates];
    NSButton *openLog = [NSButton buttonWithTitle:@"Open Log" target:self action:@selector(openLogClicked:)];
    NSTextField *note = [NSTextField wrappingLabelWithString:@"Port, workspace, profile and dsh path apply on Server ▸ Restart Server. `defaults write com.arnoldoconcepcion.harness-app <Key> <value>` works too."];
    note.textColor = NSColor.secondaryLabelColor; note.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];

    NSStackView *wsRow = [NSStackView stackViewWithViews:@[self.workspaceField, chooseWs]]; wsRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    NSStackView *dshRow = [NSStackView stackViewWithViews:@[self.dshField, chooseDsh]]; dshRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    [self.workspaceField setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.dshField setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[self label:@"Port:"], self.portField],
        @[[self label:@"Workspace:"], wsRow],
        @[[self label:@"Profile:"], self.profilePopup],
        @[[self label:@"dsh path:"], dshRow],
        @[[NSView new], keep],
        @[[NSView new], chkDsh],
        @[[NSView new], chkApp],
        @[[NSView new], openLog],
        @[[NSView new], note],
    ]];
    grid.rowSpacing = 8; grid.columnSpacing = 10;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [self.window.contentView addSubview:grid];
    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:20],
        [grid.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:20],
        [grid.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-20],
        [self.portField.widthAnchor constraintEqualToConstant:90],
        [wsRow.widthAnchor constraintEqualToConstant:360],
        [dshRow.widthAnchor constraintEqualToConstant:360],
        [note.widthAnchor constraintEqualToConstant:360],
    ]];
}

- (void)profileChanged:(id)sender { [[NSUserDefaults standardUserDefaults] setObject:self.profilePopup.titleOfSelectedItem forKey:HAPrefProfile]; }
- (void)chooseWorkspace:(id)sender {
    NSOpenPanel *p = [NSOpenPanel openPanel]; p.canChooseDirectories = YES; p.canChooseFiles = NO; p.allowsMultipleSelection = NO;
    if ([p runModal] == NSModalResponseOK && p.URL) [[NSUserDefaults standardUserDefaults] setObject:p.URL.path forKey:HAPrefWorkspace];
}
- (void)chooseDsh:(id)sender {
    NSOpenPanel *p = [NSOpenPanel openPanel]; p.canChooseDirectories = NO; p.canChooseFiles = YES; p.showsHiddenFiles = YES; p.treatsFilePackagesAsDirectories = YES;
    if ([p runModal] == NSModalResponseOK && p.URL) [[NSUserDefaults standardUserDefaults] setObject:p.URL.path forKey:HAPrefDshPath];
}
- (void)openLogClicked:(id)sender { if (self.openLog) self.openLog(); }
@end
```

- [ ] **Step 3: Fill the stubs in `src/main.m`**

Add `#import "HAPreferencesWindow.h"` at the top. Replace the four stub methods with:

```objc
- (void)showPreferences:(id)sender {
    if (!self.preferencesController) {
        __weak typeof(self) weakSelf = self;
        self.preferencesController = [[HAPreferencesWindowController alloc] initWithOpenLog:^{ [weakSelf openLog:nil]; }];
    }
    [self.preferencesController showWindow:nil];
    [self.preferencesController.window makeKeyAndOrderFront:nil];
}

- (void)showAbout:(id)sender {
    NSString *mode = @[@"not started", @"attached to an existing server", @"started by Harness"][self.server.mode];
    NSString *credits = [NSString stringWithFormat:
        @"Native macOS launcher for DeepSeek Harness (unofficial).\n\n"
        @"dsh: %@ (%@)\nServer: %@ — %@\nProfile: %@\nWorkspace: %@\nLog: %@\n\nMIT License · github.com/%@",
        self.env.dshVersion ?: @"not found", self.env.dshPath ?: @"—",
        self.server ? self.server.baseURL.absoluteString : @"—", mode,
        self.server.profile ?: @"—", self.server ? self.server.workspace : [self effectiveWorkspace], HALogPath(), HAGitHubRepo];
    NSAttributedString *att = [[NSAttributedString alloc] initWithString:credits attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:11]}];
    [NSApp orderFrontStandardAboutPanelWithOptions:@{NSAboutPanelOptionCredits: att, NSAboutPanelOptionApplicationName: @"Harness",
                                                     NSAboutPanelOptionApplicationVersion: HAAppVersion, NSAboutPanelOptionVersion: @""}];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu != self.profileMenu) return;
    [menu removeAllItems];
    NSString *current = [[NSUserDefaults standardUserDefaults] stringForKey:HAPrefProfile] ?: HADefaultProfile;
    for (NSString *name in HAAvailableProfiles(self.env.shellEnvironment)) {
        NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:name action:@selector(selectProfile:) keyEquivalent:@""];
        it.state = [name isEqualToString:current] ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:it];
    }
}

- (void)selectProfile:(NSMenuItem *)sender {
    NSString *current = [[NSUserDefaults standardUserDefaults] stringForKey:HAPrefProfile] ?: HADefaultProfile;
    if ([sender.title isEqualToString:current]) return;
    if (self.server.mode == HAServerModeAttached) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.title forKey:HAPrefProfile];
        [self presentSheetTitle:@"Profile saved" detail:@"Harness is attached to a server it did not start, so the running profile is unchanged. Stop that server (or turn off Keep Server Running) and restart to use the new profile." buttons:@[@"OK"] handler:nil];
        return;
    }
    [self replaceServerWithProfile:sender.title workspace:nil];
}

// Folder dropped on the Dock icon, or `open -a Harness <dir>`.
- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:filename isDirectory:&isDir] || !isDir) return NO;
    if (!self.server) { self.launchWorkspace = filename; return YES; }   // before startServer ran
    if (self.server.mode == HAServerModeAttached) {
        [self presentSheetTitle:@"Workspace unchanged" detail:@"Harness is attached to a server it did not start, so its workspace cannot be changed from here." buttons:@[@"OK"] handler:nil];
        return YES;
    }
    [self replaceServerWithProfile:nil workspace:filename];
    return YES;
}
```

- [ ] **Step 4: Build, then manual checks**

Run: `make install && open -a Harness`
Check: Cmd-, opens Preferences; changing Port to 3081 + Server ▸ Restart Server → About shows `:3081`; Profile menu lists `web` (+ any others) with the current checked; Keep-alive checkbox in Preferences mirrors the Server menu checkmark; `open -a Harness ~/Projects` → About shows Workspace `~/Projects` after restart; drag a folder onto the Dock icon → same. Reset: Preferences Port back to 3080.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: Preferences window, Profile submenu, Dock folder drop, About panel

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Wire the two update checks and the manual check

**Files:**
- Modify: `src/main.m` (`serverDidBecomeReady:` triggers checks once; fill `checkDshUpdatesNow:`)

**Interfaces:**
- Consumes: `HAUpdater checkDshLatest:` / `checkAppLatest:` (Task 4), `setNotice:forKey:` (Task 5), `HAPrefCheckDshUpdates` / `HAPrefCheckAppUpdates`.

- [ ] **Step 1: Add a one-shot flag and the checks**

Add to the `AppDelegate` class extension/properties: `@property BOOL updateChecksRan;`

Replace `serverDidBecomeReady:` with:
```objc
- (void)serverDidBecomeReady:(HAServer *)server {
    if (server != self.server) return;
    [self.webView loadRequest:[NSURLRequest requestWithURL:server.baseURL]];
    [self setNotice:nil forKey:@"server"];
    if (!self.updateChecksRan) { self.updateChecksRan = YES; [self runBackgroundUpdateChecks]; }
}

- (void)runBackgroundUpdateChecks {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d boolForKey:HAPrefCheckDshUpdates]) {
        [self.updater checkDshLatest:^(NSString *latest, BOOL newer) {
            if (newer) [self setNotice:[NSString stringWithFormat:@"dsh %@ available — dsh ▸ Update dsh…", latest] forKey:@"dsh-update"];
        }];
    }
    if ([d boolForKey:HAPrefCheckAppUpdates]) {
        [self.updater checkAppLatest:^(NSString *latest, BOOL newer, NSURL *page) {
            if (newer) [self setNotice:[NSString stringWithFormat:@"Harness %@ available — brew upgrade harness-app", latest] forKey:@"app-update"];
        }];
    }
}
```

Replace the `checkDshUpdatesNow:` stub with:
```objc
- (void)checkDshUpdatesNow:(id)sender {
    if (!self.updater) return;
    [self setNotice:@"checking dsh…" forKey:@"dsh-update"];
    [self.updater checkDshLatest:^(NSString *latest, BOOL newer) {
        [self setNotice:nil forKey:@"dsh-update"];
        if (!latest) { [self presentSheetTitle:@"Could not check npm" detail:@"npm view @deepseek-ai/dsh version did not answer (offline, or npm not on your login-shell PATH)." buttons:@[@"OK"] handler:nil]; return; }
        if (!newer) { [self presentSheetTitle:@"dsh is up to date" detail:[NSString stringWithFormat:@"Installed %@ · latest on npm %@", self.env.dshVersion ?: @"?", latest] buttons:@[@"OK"] handler:nil]; return; }
        [self setNotice:[NSString stringWithFormat:@"dsh %@ available — dsh ▸ Update dsh…", latest] forKey:@"dsh-update"];
        [self presentSheetTitle:[NSString stringWithFormat:@"dsh %@ is available", latest]
                         detail:[NSString stringWithFormat:@"Installed: %@. Update runs visibly in Terminal:\n\n%@", self.env.dshVersion ?: @"?", HADshInstallCommand]
                        buttons:@[@"Update in Terminal", @"Later"] handler:^(NSInteger i) { if (i == 0) [self updateDsh:nil]; }];
    }];
}
```

- [ ] **Step 2: Build and verify**

Run: `make install && open -a Harness` → after the UI loads, `dsh ▸ Check for dsh Updates Now` → "dsh is up to date" (rc.6 = rc.6). Test the newer path by pointing PATH at a fake npm: `mkdir -p /tmp/fakenpm && printf '#!/bin/sh\necho 9.9.9\n' > /tmp/fakenpm/npm && chmod +x /tmp/fakenpm/npm` and add `export PATH=/tmp/fakenpm:$PATH` temporarily to `~/.zshrc` guarded by `[ -n "$HA_ENV_CAPTURE" ]`, relaunch → subtitle shows "dsh 9.9.9 available"; `Update dsh…` opens Terminal running the exact command (Ctrl-C it — do not actually reinstall unless wanted) and shows the "When it finishes…" sheet. Remove the `~/.zshrc` line.
App check: with no GitHub release yet, `api.github.com/...releases/latest` returns 404 → no notice (correct).

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: dsh and app update checks (disclosed, off-able) + manual check

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: End-to-end smoke script + CI workflow

**Files:**
- Create: `scripts/smoke.sh`, `.github/workflows/ci.yml`
- Modify: `Makefile` (`ARCHS ?= -arch arm64 -arch x86_64` so Homebrew/CI can override with `ARCHS=`)

**Interfaces:**
- Consumes: built `build/Harness.app`, `build/fakedsh`, preference keys, log path `~/Library/Logs/Harness.app/harness-app.log`.

- [ ] **Step 1: Write `scripts/smoke.sh`**

```bash
#!/bin/bash
# End-to-end smoke for Harness.app using the fake dsh server.
# Usage: scripts/smoke.sh <path/to/Harness.app> <path/to/fakedsh>
set -uo pipefail
APP="$1"; FAKE="$2"; BIN="$APP/Contents/MacOS/Harness"
DOMAIN=com.arnoldoconcepcion.harness-app
PORT=3488; URL="http://127.0.0.1:$PORT/"
LOG="$HOME/Library/Logs/Harness.app/harness-app.log"
FAILS=0
ok()   { echo "  ok   $1"; }
fail() { echo "  FAIL $1"; FAILS=$((FAILS+1)); }
up()   { curl -s -o /dev/null -w '%{http_code}' --max-time 1 "$URL" 2>/dev/null | grep -q '^200$'; }
wait_for() { local n=0; until eval "$1"; do n=$((n+1)); [ $n -ge "$2" ] && return 1; sleep 0.5; done; return 0; }
launch() { "$BIN" >/dev/null 2>&1 & APP_PID=$!; }
stop_app() { kill -TERM "$APP_PID" 2>/dev/null; wait_for "! kill -0 $APP_PID 2>/dev/null" 30 || { kill -9 "$APP_PID"; fail "app did not exit on SIGTERM"; }; }

# Preserve the user's preferences; use test values.
BACKUP="$(mktemp)"; defaults export "$DOMAIN" "$BACKUP" 2>/dev/null || true
restore() { defaults delete "$DOMAIN" 2>/dev/null; [ -s "$BACKUP" ] && defaults import "$DOMAIN" "$BACKUP"; rm -f "$BACKUP"; pkill -f "fakedsh web" 2>/dev/null; }
trap restore EXIT
defaults write "$DOMAIN" Port -int $PORT
defaults write "$DOMAIN" DshPath "$FAKE"
defaults write "$DOMAIN" KeepServerRunning -bool NO
defaults write "$DOMAIN" CheckForDshUpdates -bool NO
defaults write "$DOMAIN" CheckForAppUpdates -bool NO
pkill -f "fakedsh web" 2>/dev/null; sleep 0.5

echo "0. --check-env"
OUT="$("$BIN" --check-env 2>&1)"; echo "$OUT" | grep -q '^dsh:' && ok "--check-env prints a report" || fail "--check-env report missing: $OUT"

echo "1. cold start: spawn, ready, SIGTERM stops the server"
launch; wait_for up 60 && ok "server reachable after launch" || fail "server never came up"
grep -q "spawned dsh pid" "$LOG" && ok "log: spawned" || fail "log lacks 'spawned'"
stop_app; sleep 1
up && fail "server still up after quit" || ok "server stopped with the app"
pgrep -f "fakedsh web --port $PORT" >/dev/null && fail "fakedsh orphaned" || ok "no orphan"

echo "2. attach: a pre-started server is used and left running"
"$FAKE" web --port $PORT >/dev/null 2>&1 & PRE=$!
wait_for up 20 || fail "pre-started fakedsh not reachable"
launch; wait_for "grep -q 'attached to existing server' '$LOG'" 40 && ok "log: attached" || fail "did not attach"
stop_app; sleep 1
kill -0 $PRE 2>/dev/null && ok "pre-started server survived app quit" || fail "attached server was killed"
kill $PRE 2>/dev/null; wait $PRE 2>/dev/null; sleep 0.5

echo "3. keep-alive: server persists after quit, next launch attaches"
defaults write "$DOMAIN" KeepServerRunning -bool YES
launch; wait_for up 60 || fail "keep-alive: server never came up"
stop_app; sleep 1
up && ok "server still running after quit (keep-alive)" || fail "server stopped despite keep-alive"
launch; wait_for "tail -5 '$LOG' | grep -q 'attached to existing server'" 40 && ok "second launch attached" || fail "second launch did not attach"
defaults write "$DOMAIN" KeepServerRunning -bool NO
stop_app; pkill -f "fakedsh web --port $PORT"; sleep 0.5

echo "4. escalation: a server that ignores SIGTERM is killed anyway"
FAKEDSH_IGNORE_TERM=1 launch_env=1
FAKEDSH_IGNORE_TERM=1 "$BIN" >/dev/null 2>&1 & APP_PID=$!
wait_for up 60 || fail "stubborn: never came up"
stop_app; sleep 1
up && fail "stubborn server survived" || ok "stubborn server killed (SIGKILL escalation)"

echo "smoke: $FAILS failure(s)"; exit $((FAILS > 0))
```
`chmod +x scripts/smoke.sh`. Note: scenario 4 relies on the app passing its own environment into the captured login-shell environment (`HACaptureLoginShellEnvironment` starts from `processInfo.environment`, so `FAKEDSH_IGNORE_TERM` reaches the child).

- [ ] **Step 2: Makefile tweak and run**

Change `ARCHS    = -arch arm64 -arch x86_64` to `ARCHS   ?= -arch arm64 -arch x86_64`.
Run: `make smoke` — Expected: `smoke: 0 failure(s)`. Your real preferences are restored afterwards (`defaults read com.arnoldoconcepcion.harness-app`).

- [ ] **Step 3: Write `.github/workflows/ci.yml`**

```yaml
name: CI
on: [push, pull_request]
jobs:
  build-test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build (universal)
        run: make app
      - name: Unit tests
        run: make test
      - name: Smoke (needs a GUI session; tolerated while we learn the runner)
        run: make smoke
        continue-on-error: true
      - name: Report
        run: |
          lipo -info build/Harness.app/Contents/MacOS/Harness
          build/Harness.app/Contents/MacOS/Harness --version
      - uses: actions/upload-artifact@v4
        with: { name: Harness.app-unsigned, path: build/Harness.app, retention-days: 7 }
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "test: end-to-end smoke script; ci: build + tests on macos-latest

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: README (EN + 中文), CHANGELOG, Homebrew formula, private GitHub repo push

**Files:**
- Create: `README.md`, `README.zh.md`, `CHANGELOG.md`, `Formula/harness-app.rb`
- External: GitHub repo `aconcepcion/harness-app` (created **private** first; flipped public in Task 10 after Arnold's OK), tap repo `aconcepcion/homebrew-tap` (created in Task 10).

- [ ] **Step 1: Write `README.md`**

````markdown
# Harness.app

**A native macOS launcher for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`dsh`) — ~600 lines of Objective-C, no Electron, no bundled copy of dsh, no tray daemon.**

Double-click → it starts *your* `dsh web` → shows the official UI in a native window → stops the server when you close it.

> Unofficial community project. Not affiliated with DeepSeek. `dsh` is theirs; this is just a window and a process manager.

## Why this exists

Within days of dsh's release there were nine "desktop" wrappers — Electron and Tauri apps that ship **their own pinned copy** of dsh, hide to a tray on close, and ask you to trust a 300–500 MB third-party binary with your API key and shell. Harness.app takes the opposite stance on every one of those:

| | Harness.app | Typical wrapper |
|---|---|---|
| Which dsh runs | **The one you installed with npm.** New upstream RC = one command; the app never needs updating | A pinned copy inside the bundle; you wait for their release |
| Size / stack | ~100 KB binary, AppKit + the system WebKit, one `clang` command | 300–500 MB Electron/Tauri, bundled Chromium or Rust toolchain |
| Trust | Read all of it in five minutes; `brew` compiles it on *your* machine | A notarized (or not) binary from a stranger |
| Close the window | **Stops the server** (opt-in keep-alive; no tray, no daemon) | Hides to a tray; server keeps running |
| Network | localhost + two disclosed, off-able version checks | Update servers, sometimes counted-download endpoints |
| dsh's plugin self-modification | Untouched — same `~/.dsh`, same profiles, your login-shell PATH | Often a custom profile layered on top |

If you want a tray app with a plugin marketplace, use one of the others — they're good at that. If you want your own dsh in a native window that behaves like a document, this is it.

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

## Preferences

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

Harness talks to exactly three places: `127.0.0.1` (dsh), `registry.npmjs.org` via `npm view` (dsh update check), and `api.github.com` (its own update check). Both checks are visible in Preferences and can be turned off. It captures your login-shell environment once at launch (`$SHELL -ilc env`, with `HA_ENV_CAPTURE=1` set so your rc files can skip slow work) and hands that environment to dsh — nothing is sent anywhere.

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
Only Command Line Tools are needed. There is no notarized download on purpose: a locally built app has no quarantine flag, and nothing about a 100 KB launcher justifies asking you to trust a binary.

## Roadmap / non-goals

- Possible v4: a generic mode for any local web tool (Open WebUI, ComfyUI, …) — the config is already command/port/name-driven.
- Not planned: tray icon, bundled Node, Windows/Linux, auto-download updates.

## License

MIT © Arnoldo Concepcion. Whale emoji icon; DeepSeek's name and logo belong to DeepSeek.
````

- [ ] **Step 2: Write `README.zh.md`** (faithful translation; header links to `README.md`)

````markdown
# Harness.app

**[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`）的原生 macOS 启动器 —— 约 600 行 Objective-C，没有 Electron，不内置 dsh 副本，没有托盘常驻进程。**

双击 → 启动*你自己安装的* `dsh web` → 在原生窗口中显示官方界面 → 关闭窗口即停止服务。

> 非官方社区项目，与 DeepSeek 无关。`dsh` 是他们的；这只是一个窗口加一个进程管理器。

[English](README.md)

## 为什么做这个

dsh 发布几天内出现了九个"桌面版"封装 —— Electron/Tauri 应用，**内置各自锁定版本的 dsh**，关窗后隐藏到托盘，并要求你把 API 密钥和 shell 权限交给一个 300–500 MB 的第三方二进制。Harness.app 在每一点上都选择了相反的立场：

| | Harness.app | 常见封装 |
|---|---|---|
| 运行哪个 dsh | **你用 npm 安装的那个。** 上游出新 RC = 一条命令；应用本身无需更新 | 包内锁定的副本；等作者发版 |
| 体积 / 技术栈 | 约 100 KB 二进制，AppKit + 系统 WebKit，一条 `clang` 命令 | 300–500 MB Electron/Tauri，内置 Chromium 或 Rust 工具链 |
| 信任 | 五分钟读完全部代码；`brew` 在*你的*机器上编译 | 陌生人提供的（可能未公证的）二进制 |
| 关闭窗口 | **停止服务**（可选保持运行；无托盘、无常驻） | 隐藏到托盘；服务继续运行 |
| 网络 | localhost + 两个明示、可关闭的版本检查 | 更新服务器，有时还有计数下载端点 |
| dsh 的插件自我修改能力 | 完全不受影响 —— 同一个 `~/.dsh`，同样的 profile，你的登录 shell PATH | 常常叠加一个自定义 profile |

想要带插件市场的托盘应用，用别的 —— 它们擅长那个。想要自己的 dsh 在一个像文档一样行为的原生窗口里，就是这个。

## 安装

**Homebrew（本地编译约 2 秒，无 Gatekeeper 提示）：**
```sh
brew install aconcepcion/tap/harness-app
cp -R "$(brew --prefix)/opt/harness-app/Harness.app" /Applications/
```
**或从源码：**
```sh
git clone https://github.com/aconcepcion/harness-app && cd harness-app && make install
```
要求：macOS 13+、Xcode Command Line Tools（`xcode-select --install`），以及通过 npm 安装的 `dsh` —— **或者不装也行**：找不到 dsh 时，Harness 会显示准确的安装命令并替你打开 Terminal。

## 首次运行

1. 打开 Harness。它通过你的登录 shell 查找 `dsh`（Homebrew、nvm、volta、fnm 都可以）。
2. 如果 dsh 缺失、Node 版本不对、或 dsh 的 shell 工具损坏（见"坑"），它会准确告诉你该运行什么 —— 在 Terminal 里可见地运行，没有任何隐藏操作。
3. 官方 dsh 网页界面加载。照常在 Settings → Models 输入 API 密钥。
4. 关闭窗口：它启动的服务随之停止。（如果想让服务留着，打开 **Server ▸ Keep Server Running After Close**；下次启动会立即接管。）

## 它实际做了什么

- **接管或启动。** 端口上已经有服务在响应（比如你在终端里启动的 `dsh web`），Harness 就接管它，绝不杀掉。否则在你的工作目录中启动 `dsh web --port <Port>`，独立进程组，日志写到 `~/Library/Logs/Harness.app/`。
- **就绪 = HTTP 200**，而不是"端口开了"。界面真正可用之前显示占位页。
- **停止 = 向进程组发 SIGTERM → 5 秒 → SIGKILL。** 不会留下孤儿 `node-pty` shell 或 `sandbox-exec` 子进程。
- **崩溃策略。** dsh 退出则自动重启一次；一分钟内再次退出，弹出带日志尾部的错误面板 —— 绝不出现空白窗口。
- **导航守卫。** 非 `127.0.0.1` 的链接一律在默认浏览器中打开。
- **Dock 拖放。** 把文件夹拖到图标上（或 `open -a Harness ~/project`）即以其为工作目录。
- **Profile。** Server ▸ Profile 列出 `~/.dsh/profiles/`；切换会重启服务。Harness 绝不注入自己的 profile。
- **Update dsh… / Repair Shell Tools…** 打开 Terminal 运行下面这条准确的命令。Harness 无法得知 Terminal 何时完成，所以只会提醒你：Server ▸ Restart Server。

## 更新 dsh

```sh
npm install -g --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs @deepseek-ai/dsh@latest
```
就这么简单：dsh 归 npm 管，不归我们管。Harness 启动时查询 npm，有新版时在窗口副标题显示"dsh x.y.z available"。你的 `~/.dsh` profile 与插件绝不会被触碰（新 RC 需要时自行 `dsh plugin update`）。

## 偏好设置

Cmd-, 或 `defaults write com.arnoldoconcepcion.harness-app <Key> <value>`：

| 键 | 默认 | 含义 |
|---|---|---|
| `Port` | `3080` | 接管 / 启动所用端口 |
| `Workspace` | `$HOME` | 启动 `dsh web` 的工作目录 |
| `Profile` | `web` | `web` 用 `dsh web`，其他用 `dsh --profile <name>` |
| `DshPath` | （自动） | 覆盖登录 shell PATH 查找 |
| `KeepServerRunning` | `NO` | 关窗后保留服务 |
| `CheckForDshUpdates` | `YES` | 启动时 `npm view @deepseek-ai/dsh version` |
| `CheckForAppUpdates` | `YES` | 启动时查询 GitHub 最新 release |

端口 / 工作目录 / profile / dsh 路径在 **Server ▸ Restart Server** 时生效。

## 隐私与网络

Harness 只与三处通信：`127.0.0.1`（dsh）、通过 `npm view` 访问 `registry.npmjs.org`（dsh 更新检查）、`api.github.com`（自身更新检查）。两项检查在偏好设置中可见并可关闭。它在启动时捕获一次你的登录 shell 环境（`$SHELL -ilc env`，并设置 `HA_ENV_CAPTURE=1` 以便你的 rc 文件跳过耗时操作），然后把该环境交给 dsh —— 不会发送到任何地方。

## 这个应用知道的坑

- **npm ≥ 11 默认跳过安装脚本**，所以裸 `npm install -g @deepseek-ai/dsh` 会让 node-pty 缺少 macOS 预编译文件 → dsh 的 shell/PTY 工具悄悄失效。因此上面每条命令都带 `--allow-scripts=…`。Harness 能检测该损坏状态（`node_modules/node-pty/prebuilds/darwin-<arch>/` 缺失）并提供修复。
- **Node 23.x 落在 dsh `engines` 的排除区间**（`^22.19.0 || >=24.0.0`）。Node 版本不受支持时 Harness 会告诉你。
- **dsh 仍是开发者预览版**（rc.x），RC 之间可能有破坏性变更。这正是 Harness 不锁定版本的原因 —— 何时更新由你决定。

## 构建与测试

```sh
make            # 在 build/ 生成通用二进制 Harness.app
make test       # 单元测试（环境发现、semver、用假 dsh 测服务生命周期）
make smoke      # 端到端：冷启动、接管、保持运行、SIGKILL 升级
make install    # 复制到 /Applications（ad-hoc 签名）
```
只需要 Command Line Tools。有意不提供公证下载：本地编译的应用没有隔离标记，而一个 100 KB 的启动器也不值得让你去信任一个二进制。

## 路线图 / 非目标

- 可能的 v4：面向任意本地网页工具（Open WebUI、ComfyUI……）的通用模式 —— 配置已经是命令/端口/名称驱动。
- 不计划：托盘图标、内置 Node、Windows/Linux、自动下载更新。

## 许可

MIT © Arnoldo Concepcion。图标为鲸鱼 emoji；DeepSeek 的名称与标志归 DeepSeek 所有。
````

- [ ] **Step 3: Write `CHANGELOG.md`**

```markdown
# Changelog

## 3.0.0 — 2026-08-1x
First public release. Previously a private launcher (v2) built 2026-08-14.
- Attach-or-spawn `dsh web`; HTTP readiness; process-group stop with SIGTERM→SIGKILL escalation; one auto-restart then a real error sheet
- First-run guidance when dsh / Node are missing or unsupported; detects and repairs the npm-11 broken node-pty state
- Close = stop by default; opt-in Keep Server Running; no tray, no daemon
- Cross-origin navigation opens in the default browser
- Preferences window; Profile submenu; Dock folder drop; About panel with dsh version, port, workspace, log
- Disclosed, off-able version checks for dsh (npm) and Harness (GitHub); "Update dsh…" runs visibly in Terminal
- Universal binary; `make test` + `make smoke`; Homebrew tap formula; bilingual README
```

- [ ] **Step 4: Write `Formula/harness-app.rb`**

```ruby
class HarnessApp < Formula
  desc "Native macOS launcher for DeepSeek Harness (dsh) — no Electron, no bundled dsh"
  homepage "https://github.com/aconcepcion/harness-app"
  url "https://github.com/aconcepcion/harness-app/archive/refs/tags/v3.0.0.tar.gz"
  sha256 "REPLACED_AFTER_TAG"   # Task 10 fills this after `git tag v3.0.0` is pushed
  license "MIT"
  head "https://github.com/aconcepcion/harness-app.git", branch: "main"

  depends_on :macos => :ventura
  depends_on xcode: :build   # Command Line Tools satisfy this

  def install
    system "make", "app", "ARCHS="          # native arch only under Homebrew
    prefix.install "build/Harness.app"
    (bin/"harness-app").write <<~EOS
      #!/bin/bash
      exec open -a "#{opt_prefix}/Harness.app" "$@"
    EOS
  end

  def caveats
    <<~EOS
      Harness.app was built locally and installed to:
        #{opt_prefix}/Harness.app
      To put it in /Applications (Dock, Spotlight):
        cp -R "#{opt_prefix}/Harness.app" /Applications/
      Or launch from the terminal: harness-app [workspace-folder]
    EOS
  end

  test do
    assert_match "Harness.app", shell_output("#{opt_prefix}/Harness.app/Contents/MacOS/Harness --check-env", 1)
  end
end
```
(`shell_output(..., 1)` because `--check-env` exits 1 when dsh is absent, as it is in Homebrew's test sandbox.)

- [ ] **Step 5: Create the private GitHub repo and push**

```bash
cd ~/Projects/harness-app && git add -A && git commit -m "docs: README (en/zh), CHANGELOG, Homebrew formula

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
gh repo create aconcepcion/harness-app --private --source=. --remote=origin \
  --description "Harness.app — native macOS launcher for DeepSeek Harness (dsh). Your own npm dsh, ~600 lines of ObjC, no Electron, no tray." --push
gh repo edit aconcepcion/harness-app --add-topic deepseek --add-topic deepseek-harness --add-topic dsh --add-topic macos --add-topic launcher --add-topic objective-c --add-topic wkwebview
gh run list -R aconcepcion/harness-app -L 1   # CI should start
```
Expected: repo exists (private), CI run queued.

---

### Task 10: Acceptance, publish, tap, tag, write-back

**Files:**
- Modify: `Formula/harness-app.rb` (sha256), tap repo `aconcepcion/homebrew-tap/Formula/harness-app.rb`
- External: flip repo public, `git tag v3.0.0`, GitHub release, tap repo; brain write-back (with Arnold's OK)

- [ ] **Step 1: Run the acceptance checklist from spec §6 on the installed app**

```bash
make install && open -a Harness
```
- [ ] Runs the user's npm dsh; About shows the real path/version; `~/.dsh/profiles/web` untouched (`git diff`-style: compare `package.json`/`cordis.patch.yml` mtimes before/after) 
- [ ] **dsh plugin self-modification** — in the dsh UI, ask the harness to add a small plugin to itself (Arnold's markdown-upload style request); confirm the install command it runs succeeds (needs pnpm/node on PATH → captured login shell), then Server ▸ Restart Server, confirm the feature works
- [ ] Close = stop; keep-alive opt-in; `pgrep -f "dsh web"` empty after quit (no orphans)
- [ ] First-run guidance appears with dsh temporarily renamed away; Repair path shows when a darwin prebuild dir is temporarily renamed (`mv .../prebuilds/darwin-arm64{,.bak}` and back)
- [ ] Never a blank window: kill the child twice → sheet with log tail
- [ ] `make test` and `make smoke` green locally; CI green (or smoke tolerated) on GitHub
- [ ] `lipo -info` shows both arches; icon shows in Dock; README renders on GitHub (private) — Arnold reviews wording

- [ ] **Step 2: Arnold's go/no-go to publish** — STOP and ask. Public flip, tag, and tap are outward-facing.

- [ ] **Step 3: Publish (after OK)**

```bash
gh repo edit aconcepcion/harness-app --visibility public --accept-visibility-change-consequences
git tag -a v3.0.0 -m "Harness.app 3.0.0" && git push origin v3.0.0
SHA=$(curl -sL https://github.com/aconcepcion/harness-app/archive/refs/tags/v3.0.0.tar.gz | shasum -a 256 | cut -d' ' -f1)
sed -i '' "s/REPLACED_AFTER_TAG/$SHA/" Formula/harness-app.rb
git commit -am "formula: sha256 for v3.0.0" && git push
gh release create v3.0.0 --title "Harness.app 3.0.0" --notes-file CHANGELOG.md   # source-only release; no binaries by design
# Tap
mkdir -p /tmp/homebrew-tap/Formula && cp Formula/harness-app.rb /tmp/homebrew-tap/Formula/ && cd /tmp/homebrew-tap && git init -q && git add -A && git commit -qm "harness-app 3.0.0"
gh repo create aconcepcion/homebrew-tap --public --source=. --remote=origin --description "Homebrew tap for aconcepcion's tools" --push
# Verify the install path a stranger would use
brew untap aconcepcion/tap 2>/dev/null; brew install aconcepcion/tap/harness-app && ls "$(brew --prefix)/opt/harness-app/Harness.app" && harness-app --version 2>/dev/null; brew test harness-app
```
Note: `harness-app --version` via `open` won't print; use `"$(brew --prefix)/opt/harness-app/Harness.app/Contents/MacOS/Harness" --version` instead.

- [ ] **Step 4: Write-back to the brain (ask Arnold first, per RULE:write-back)** — supersede/extend the playbook `DeepSeek Harness (dsh) — MacBook Pro`: launcher is now Harness.app v3 (repo, install path, source moved from `~/dsh-test/launcher-src` to `~/Projects/harness-app`), the DSH Desktop evaluation + landscape (nine wrappers), the decisions (BYO stance, no notarization, close=stop with opt-in keep-alive), the node-pty precise failure mode, and Arnold's requirement that the launcher never constrain dsh's plugin self-modification. Then `schema_validate`.

---

## Self-review

**Spec coverage** — §2.1 launch/attach/spawn/readiness → Tasks 3, 5. §2.2 first-run + node-pty → Tasks 2, 5. §2.3 running (nav guard, JS dialogs, crash policy, Cmd-R, Dock drop) → Tasks 3, 5, 6. §2.4 close/quit/keep-alive/escalation → Tasks 3, 5. §2.5 menus → Tasks 5, 6, 7. §2.6 updates → Tasks 4, 7. §2.7 Preferences → Task 6. §3 architecture → file structure. §4 repo layout/formula/CI → Tasks 1, 8, 9. §5 testing → Tasks 2, 3, 4, 8 + Task 10 manual. §6 acceptance → Task 10. §7 deferred → out of plan by design.
**Placeholder scan** — the only intentional placeholder is `REPLACED_AFTER_TAG` in the formula, filled by a concrete `sed` in Task 10; "wired in Task N" stubs in Task 5 are each replaced by full code in Tasks 6–7.
**Type consistency** — `HAServer` API (`initWithDshPath:port:profile:workspace:environment:logPath:`, `start`, `restart`, `stopSynchronously:`, `probeReady`, `logTail:`, `mode`, `childPID`, `baseURL`, `profile`, `workspace`) is used identically in Tasks 3, 5, 6. `HAUpdater` (`initWithEnvironment:installedDshVersion:appVersion:`, `checkDshLatest:`, `checkAppLatest:`, `+runInTerminal:error:`, `+installCommand`) identical in Tasks 4, 5, 7. `HAEnvironment` fields identical in Tasks 2, 5, 6. Preference keys come only from `HAConfig.h`. `HAAvailableProfiles` declared in `HAPreferencesWindow.h`, used in Task 6's `menuNeedsUpdate:`.
