# Harness.app v3.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Harness.app 3.1.0 — install presets/skills/plugins from a Git URL, list what is installed, reveal/edit dsh files, fix the update command's npm target, add Prevent Sleep, and implement the WKWebView file chooser — without changing the app's stance (BYO dsh, nothing bundled, the app process never writes into `$DSH_HOME`).

**Architecture:** Two new pure units (`HAInstaller` for clone-target/scan/script generation, `HASleepGuard` for the IOKit assertion) plus small additions to `HAEnvironment` (dsh home, owning-npm install command). `main.m` gains menu items, three sheets and the WKUIDelegate open-panel method; every write into `$DSH_HOME` runs as a visible `bash -ex` of a script the user has just read, via the existing `HAUpdater runInTerminal:`.

**Tech Stack:** Objective-C, AppKit, WebKit, IOKit (new link), Foundation; hand-rolled test runner (`tests/HATest.h`); `make test` / `make smoke`; GitHub Actions macos-latest.

**Spec:** `docs/superpowers/specs/2026-08-18-harness-app-v3.1-design.md`

## Global Constraints

- macOS 13+, Command Line Tools only, one `clang` command per target; no Swift, no third-party code (`AGENTS.md`).
- The app process never writes into `$DSH_HOME`; every such step runs visibly in Terminal (spec §3).
- Network destinations: localhost, `npm view`, `api.github.com`, and — new — only the git host of a URL the user pastes, only when they click Fetch (spec §3). README *Privacy & network* must say so.
- Install flags defined once (`HA_DSH_INSTALL_ARGS` in `HAEnvironment.m`); every command that installs/updates dsh is composed from it (spec §4.4).
- Preference keys only in `HAConfig.h`; README Settings table must match.
- Version `3.1.0` in `HAConfig.h` and `Makefile`; CHANGELOG entry; tag `v3.1.0`; formula sha256; tap mirror.
- Conventional commit prefixes; **no AI attribution or co-author trailers anywhere** (Arnold, 2026-08-17).
- `make test` must print `0 failures` for every test binary; `make smoke` must print `smoke: 0 failure(s)`.

---

### Task 1: HAEnvironment — dsh home and owning-npm install command

**Files:**
- Modify: `src/HAEnvironment.h`, `src/HAEnvironment.m`, `src/HAPreferencesWindow.m` (use `HADshHome`)
- Test: `tests/test_environment.m`

**Interfaces:**
- Produces: `NSString *HADshHome(NSDictionary *_Nullable env)` — `env[@"DSH_HOME"]` if non-empty else `~/.dsh`; `NSString *HADshInstallCommandForPackageDir(NSString *_Nullable pkgDir)`; `HADshInstallCommand` unchanged in value.

- [ ] **Step 1: Write the failing tests** (append before `HA_DONE()` in `tests/test_environment.m`)

```objc
    // v3.1: DSH_HOME resolution
    HA_EQ_STR(HADshHome(@{@"DSH_HOME": @"/tmp/dshx"}), @"/tmp/dshx");
    HA_EQ_STR(HADshHome(@{@"DSH_HOME": @""}), [NSHomeDirectory() stringByAppendingPathComponent:@".dsh"]);
    HA_EQ_STR(HADshHome(nil), [NSHomeDirectory() stringByAppendingPathComponent:@".dsh"]);

    // v3.1: the install/update command targets the npm that owns the found dsh
    NSString *prefix = [NSTemporaryDirectory() stringByAppendingFormat:@"haprefix-%d", getpid()];
    NSString *pkg = [prefix stringByAppendingPathComponent:@"lib/node_modules/@deepseek-ai/dsh"];
    [fm createDirectoryAtPath:pkg withIntermediateDirectories:YES attributes:nil error:nil];
    HA_ASSERT([HADshInstallCommandForPackageDir(pkg) hasPrefix:[NSString stringWithFormat:@"npm --prefix '%@' install -g --allow-scripts=", prefix]], "no sibling npm → --prefix form: %s", HADshInstallCommandForPackageDir(pkg).UTF8String);
    [fm createDirectoryAtPath:[prefix stringByAppendingPathComponent:@"bin"] withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *npmBin = [prefix stringByAppendingPathComponent:@"bin/npm"];
    [@"#!/bin/sh\n" writeToFile:npmBin atomically:YES encoding:NSUTF8StringEncoding error:nil]; chmod(npmBin.fileSystemRepresentation, 0755);
    HA_ASSERT([HADshInstallCommandForPackageDir(pkg) hasPrefix:[NSString stringWithFormat:@"'%@' install -g --allow-scripts=", npmBin]], "sibling npm → quoted npm path: %s", HADshInstallCommandForPackageDir(pkg).UTF8String);
    HA_ASSERT([HADshInstallCommandForPackageDir(pkg) hasSuffix:@"@deepseek-ai/dsh@latest"], "same package spec");
    HA_EQ_STR(HADshInstallCommandForPackageDir(nil), HADshInstallCommand);
    HA_EQ_STR(HADshInstallCommandForPackageDir(@"/weird/place/dsh"), HADshInstallCommand);
    [fm removeItemAtPath:prefix error:nil];
```
(`fm` = `[NSFileManager defaultManager]`; the file already has a local — reuse or declare `NSFileManager *fm = [NSFileManager defaultManager];` and `#import <sys/stat.h>` if missing.)

- [ ] **Step 2: Run to verify it fails**

Run: `make build/test_environment 2>&1 | tail -3` — Expected: compile error `HADshHome` undeclared.

- [ ] **Step 3: Implement**

`src/HAEnvironment.h` — add after `HADshInstallCommand`:
```objc
/// $DSH_HOME from the (login-shell) environment, else ~/.dsh.
NSString *HADshHome(NSDictionary<NSString *, NSString *> *_Nullable env);
/// The dsh install/update command aimed at the npm prefix that owns `pkgDir`
/// (…/<prefix>/lib/node_modules/@deepseek-ai/dsh). Falls back to HADshInstallCommand.
NSString *HADshInstallCommandForPackageDir(NSString *_Nullable pkgDir);
```

`src/HAEnvironment.m` — replace the `HADshInstallCommand` definition with:
```objc
#import "HAUpdater.h"   // HAShellQuote

#define HA_DSH_INSTALL_ARGS "install -g --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs @deepseek-ai/dsh@latest"
NSString *const HADshInstallCommand = @"npm " HA_DSH_INSTALL_ARGS;

NSString *HADshHome(NSDictionary *env) {
    NSString *h = env[@"DSH_HOME"];
    return h.length ? h : [NSHomeDirectory() stringByAppendingPathComponent:@".dsh"];
}

NSString *HADshInstallCommandForPackageDir(NSString *pkgDir) {
    NSRange r = [pkgDir ?: @"" rangeOfString:@"/lib/node_modules/"];
    if (r.location == NSNotFound || r.location == 0) return HADshInstallCommand;
    NSString *prefix = [pkgDir substringToIndex:r.location];
    NSString *npm = [prefix stringByAppendingPathComponent:@"bin/npm"];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:npm]) return [HAShellQuote(npm) stringByAppendingString:@" " HA_DSH_INSTALL_ARGS];
    return [NSString stringWithFormat:@"npm --prefix %@ " HA_DSH_INSTALL_ARGS, HAShellQuote(prefix)];
}
```
`src/HAPreferencesWindow.m` — `HAAvailableProfiles`: replace the two `dshHome`/`home` lines with `NSString *dir = [HADshHome(env) stringByAppendingPathComponent:@"profiles"];` and `#import "HAEnvironment.h"`.

- [ ] **Step 4: Run tests** — `make test 2>&1 | tail -4` → all three binaries `0 failures`.
- [ ] **Step 5: Commit** — `git add src tests && git commit -m "feat: dsh home helper; install command targets the npm that owns dsh"`

---

### Task 2: HASleepGuard (IOKit assertion)

**Files:**
- Create: `src/HASleepGuard.h`, `src/HASleepGuard.m`; Test: `tests/test_sleepguard.m`; Modify: `Makefile` (SRC, LIBSRC, `-framework IOKit`), `src/HAConfig.h` (key + default)

**Interfaces:**
- Produces: `@interface HASleepGuard : NSObject @property (readonly) BOOL active; - (BOOL)activateWithReason:(NSString *)reason; - (void)deactivate; @end`; pref `HAPrefPreventSleep = @"PreventSleepWhileRunning"` (BOOL, default NO).

- [ ] **Step 1: Failing test** `tests/test_sleepguard.m`:
```objc
#import "HATest.h"
#import "HASleepGuard.h"
int main(void) { @autoreleasepool {
    HASleepGuard *g = [HASleepGuard new];
    HA_ASSERT(!g.active, "inactive at start");
    HA_ASSERT([g activateWithReason:@"Harness test"], "activate succeeds");
    HA_ASSERT(g.active, "active after activate");
    HA_ASSERT([g activateWithReason:@"Harness test"], "activate is idempotent");
    [g deactivate]; HA_ASSERT(!g.active, "inactive after deactivate");
    [g deactivate]; HA_ASSERT(!g.active, "deactivate is idempotent");
    HA_DONE();
} }
```
- [ ] **Step 2: Run** `make build/test_sleepguard` → fails (no header).
- [ ] **Step 3: Implement**

`src/HASleepGuard.h`:
```objc
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Holds a power-management assertion that prevents idle system sleep while active (IOPMAssertion).
@interface HASleepGuard : NSObject
@property (readonly) BOOL active;
- (BOOL)activateWithReason:(NSString *)reason;   // idempotent; NO if the system refused
- (void)deactivate;                              // idempotent
@end
NS_ASSUME_NONNULL_END
```
`src/HASleepGuard.m`:
```objc
#import "HASleepGuard.h"
#import <IOKit/pwr_mgt/IOPMLib.h>
@interface HASleepGuard () { IOPMAssertionID _assertion; }
@property (readwrite) BOOL active;
@end
@implementation HASleepGuard
- (BOOL)activateWithReason:(NSString *)reason {
    if (self.active) return YES;
    IOReturn r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep, kIOPMAssertionLevelOn,
                                             (__bridge CFStringRef)reason, &_assertion);
    self.active = (r == kIOReturnSuccess);
    return self.active;
}
- (void)deactivate { if (!self.active) return; IOPMAssertionRelease(_assertion); _assertion = 0; self.active = NO; }
- (void)dealloc { [self deactivate]; }
@end
```
`Makefile`: add `src/HASleepGuard.m` to `SRC` and `LIBSRC`; `FW = -framework Cocoa -framework WebKit -framework IOKit`; the test rule gets `-framework IOKit` too.
`src/HAConfig.h`: `static NSString *const HAPrefPreventSleep = @"PreventSleepWhileRunning"; // BOOL, default NO` and `HAPrefPreventSleep: @NO,` in `HARegisterDefaults`.

- [ ] **Step 4: Run** `make test` → 4 binaries, all `0 failures`.
- [ ] **Step 5: Commit** — `git add src tests Makefile && git commit -m "feat: HASleepGuard — idle-sleep assertion while the server runs"`

---

### Task 3: HAInstaller — clone target, scan, preset id, script

**Files:**
- Create: `src/HAInstaller.h`, `src/HAInstaller.m`; Test: `tests/test_installer.m`; Modify: `Makefile` (SRC, LIBSRC)

**Interfaces:**
- Produces:
```objc
typedef NS_ENUM(NSInteger, HAInstallKind) { HAInstallKindPreset = 0, HAInstallKindSkill, HAInstallKindPlugin };
@interface HAInstallItem : NSObject
@property HAInstallKind kind; @property (copy) NSString *sourceDir; @property (copy) NSString *ident;
@property (copy, nullable) NSString *targetPath;   // nil for plugins
@property BOOL replacesExisting;
- (NSString *)label;   // "preset router-standard → ~/.dsh/.agent-presets/router-standard (replaces existing)"
@end
NSString *HASourcesRoot(void);                                        // ~/Library/Application Support/Harness.app/sources
NSString *_Nullable HAInstallCloneTargetForURL(NSString *url, NSString *sourcesRoot);   // nil = rejected URL
NSString *HAPresetIDFromName(NSString *name);
NSArray<HAInstallItem *> *HAScanInstallables(NSString *cloneDir, NSString *dshHome);
NSString *HAInstallScript(NSArray<HAInstallItem *> *items, NSString *dshHome, NSString *dshPath, NSString *profile, NSString *stamp);
NSArray<NSString *> *HAInstalledPresetDirs(NSString *dshHome);        // dirs with preset.yml under .agent-presets, sorted
NSArray<NSString *> *HAInstalledSkillDirs(NSString *dshHome);         // dirs with SKILL.md under $DSH_HOME/skills and ~/.agents/skills
```

- [ ] **Step 1: Failing tests** `tests/test_installer.m`:
```objc
#import "HATest.h"
#import "HAInstaller.h"
#import "HAUpdater.h"
static void mkfile(NSString *p, NSString *s) { [[NSFileManager defaultManager] createDirectoryAtPath:p.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil]; [s writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
int main(void) { @autoreleasepool {
    NSString *root = @"/tmp/ha-src";
    // clone targets
    HA_EQ_STR(HAInstallCloneTargetForURL(@"https://github.com/xiaobright/dsh-anchored-standard", root) ?: @"nil", @"/tmp/ha-src/github.com/xiaobright/dsh-anchored-standard");
    HA_EQ_STR(HAInstallCloneTargetForURL(@"https://github.com/Owner/Repo.git/", root) ?: @"nil", @"/tmp/ha-src/github.com/Owner/Repo");
    HA_EQ_STR(HAInstallCloneTargetForURL(@"git@github.com:owner/repo.git", root) ?: @"nil", @"/tmp/ha-src/github.com/owner/repo");
    HA_EQ_STR(HAInstallCloneTargetForURL(@"ssh://git@gitlab.com/group/sub/repo.git", root) ?: @"nil", @"/tmp/ha-src/gitlab.com/group/sub/repo");
    HA_ASSERT(HAInstallCloneTargetForURL(@"https://github.com/../etc/passwd", root) == nil, "dotdot rejected");
    HA_ASSERT(HAInstallCloneTargetForURL(@"https://github.com/", root) == nil, "no path rejected");
    HA_ASSERT(HAInstallCloneTargetForURL(@"file:///etc", root) == nil, "file scheme rejected");
    HA_ASSERT(HAInstallCloneTargetForURL(@"not a url", root) == nil, "garbage rejected");
    // preset ids
    HA_EQ_STR(HAPresetIDFromName(@"Router_Standard"), @"router-standard");
    HA_EQ_STR(HAPresetIDFromName(@"--Weird  Name!"), @"weird-name");
    HA_EQ_STR(HAPresetIDFromName(@"ok-1"), @"ok-1");
    HA_EQ_STR(HAPresetIDFromName(@"!!!"), @"preset");
    // scan a synthetic clone
    NSString *clone = [NSTemporaryDirectory() stringByAppendingFormat:@"haclone-%d", getpid()];
    NSString *home  = [NSTemporaryDirectory() stringByAppendingFormat:@"hahome-%d", getpid()];
    [[NSFileManager defaultManager] removeItemAtPath:clone error:nil]; [[NSFileManager defaultManager] removeItemAtPath:home error:nil];
    mkfile([clone stringByAppendingPathComponent:@"package.json"], @"{\"name\":\"tooling\",\"devDependencies\":{\"cordis\":\"1\"}}");   // decoy: root tooling
    mkfile([clone stringByAppendingPathComponent:@"README.md"], @"# repo");
    mkfile([clone stringByAppendingPathComponent:@"preset/router-standard/preset.yml"], @"name: Router");
    mkfile([clone stringByAppendingPathComponent:@"preset/router-standard/agent.cordis.yml"], @"[]");
    mkfile([clone stringByAppendingPathComponent:@"Combo_Anchored/preset.yml"], @"name: Combo");
    mkfile([clone stringByAppendingPathComponent:@"j-space/SKILL.md"], @"# j-space");
    mkfile([clone stringByAppendingPathComponent:@"j-space/modules/a.md"], @"x");
    mkfile([clone stringByAppendingPathComponent:@"injector/package.json"], @"{\"name\":\"dsh-super-injector\"}");
    mkfile([clone stringByAppendingPathComponent:@"injector/cordis.patch.yml"], @"[]");
    mkfile([clone stringByAppendingPathComponent:@"tool/package.json"], @"{\"name\":\"x\",\"keywords\":[\"dsh-plugin\"]}");
    mkfile([clone stringByAppendingPathComponent:@"node_modules/evil/preset.yml"], @"no");
    mkfile([clone stringByAppendingPathComponent:@".git/preset.yml"], @"no");
    mkfile([clone stringByAppendingPathComponent:@"a/b/c/d/e/deep/preset.yml"], @"too deep");
    mkfile([home stringByAppendingPathComponent:@".agent-presets/router-standard/preset.yml"], @"existing");
    NSArray<HAInstallItem *> *items = HAScanInstallables(clone, home);
    HA_ASSERT(items.count == 5, "5 items found, got %lu", (unsigned long)items.count);
    NSMutableArray *labels = [NSMutableArray array]; for (HAInstallItem *i in items) [labels addObject:i.label];
    NSString *all = [labels componentsJoinedByString:@"\n"];
    HA_ASSERT([all containsString:@"preset router-standard → "], "router-standard preset: %s", all.UTF8String);
    HA_ASSERT([all containsString:@"(replaces existing)"], "existing preset flagged");
    HA_ASSERT([all containsString:@"preset combo-anchored → "], "id sanitised");
    HA_ASSERT([all containsString:@"skill j-space → "], "skill found");
    HA_ASSERT([all containsString:@"plugin dsh-super-injector"], "plugin by cordis.patch.yml");
    HA_ASSERT([all containsString:@"plugin x"], "plugin by keyword");
    HA_ASSERT(![all containsString:@"tooling"], "root tooling package.json is not a plugin");
    HA_ASSERT(![all containsString:@"evil"] && ![all containsString:@"deep"], "node_modules/.git/deep skipped");
    HA_ASSERT(items[0].kind == HAInstallKindPreset && items[items.count-1].kind == HAInstallKindPlugin, "ordered presets, skills, plugins");
    // script
    NSString *s = HAInstallScript(items, home, @"/opt/homebrew/bin/dsh", @"web", @"20260818-120000");
    HA_ASSERT([s hasPrefix:@"#!/bin/bash\nset -eu\n"], "bash header");
    HA_ASSERT([s containsString:[NSString stringWithFormat:@"DSH_HOME=%@", HAShellQuote(home)]], "DSH_HOME line");
    HA_ASSERT([s containsString:@"mkdir -p \"$DSH_HOME/.agent-presets\" \"$DSH_HOME/skills\""], "mkdir once");
    HA_ASSERT([s containsString:@"mv \"$DSH_HOME/.agent-presets/router-standard\" \"$DSH_HOME/.agent-presets/router-standard.replaced-20260818-120000\""], "existing moved aside, never deleted");
    HA_ASSERT([s containsString:[NSString stringWithFormat:@"cp -R %@ \"$DSH_HOME/.agent-presets/router-standard\"", HAShellQuote([clone stringByAppendingPathComponent:@"preset/router-standard"])]], "cp preset");
    HA_ASSERT([s containsString:@"cp -R "] && [s containsString:@"\"$DSH_HOME/skills/j-space\""], "cp skill");
    HA_ASSERT([s containsString:[NSString stringWithFormat:@"'/opt/homebrew/bin/dsh' plugin --profile 'web' add %@", HAShellQuote([clone stringByAppendingPathComponent:@"injector"])]], "plugin add");
    HA_ASSERT(![s containsString:@"rm -rf"], "never rm -rf");
    HA_ASSERT([s containsString:@"Server ▸ Restart Server"], "closing hint");
    // installed listings
    HA_ASSERT(HAInstalledPresetDirs(home).count == 1, "one installed preset");
    HA_ASSERT(HAInstalledSkillDirs(home).count == 0, "no skills");
    [[NSFileManager defaultManager] removeItemAtPath:clone error:nil]; [[NSFileManager defaultManager] removeItemAtPath:home error:nil];
    HA_DONE();
} }
```
- [ ] **Step 2: Run** `make build/test_installer` → fails (no header).
- [ ] **Step 3: Implement** `src/HAInstaller.h` (interfaces above with `NS_ASSUME_NONNULL`) and `src/HAInstaller.m`:
```objc
#import "HAInstaller.h"
#import "HAUpdater.h"

@implementation HAInstallItem
- (NSString *)label {
    NSString *kind = @[@"preset", @"skill", @"plugin"][self.kind];
    if (self.kind == HAInstallKindPlugin) return [NSString stringWithFormat:@"plugin %@ (dsh plugin add %@)", self.ident, self.sourceDir.lastPathComponent];
    NSString *t = [self.targetPath stringByAbbreviatingWithTildeInPath];
    return [NSString stringWithFormat:@"%@ %@ → %@%@", kind, self.ident, t, self.replacesExisting ? @" (replaces existing)" : @""];
}
@end

NSString *HASourcesRoot(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Harness.app/sources"];
}

static BOOL safeComponent(NSString *c) {
    if (!c.length || [c isEqualToString:@"."] || [c isEqualToString:@".."]) return NO;
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
    return [c rangeOfCharacterFromSet:ok.invertedSet].location == NSNotFound;
}

NSString *HAInstallCloneTargetForURL(NSString *url, NSString *sourcesRoot) {
    url = [url stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *host = nil, *path = nil;
    NSRange scp = [url rangeOfString:@"@"];
    if ([url hasPrefix:@"https://"] || [url hasPrefix:@"http://"] || [url hasPrefix:@"ssh://"] || [url hasPrefix:@"git://"]) {
        NSURL *u = [NSURL URLWithString:url]; host = u.host; path = u.path;
    } else if (scp.location != NSNotFound && [url rangeOfString:@":"].location > scp.location && [url rangeOfString:@"://"].location == NSNotFound) {
        NSString *rest = [url substringFromIndex:scp.location + 1]; NSRange colon = [rest rangeOfString:@":"];
        host = [rest substringToIndex:colon.location]; path = [rest substringFromIndex:colon.location + 1];   // git@host:owner/repo.git
    } else return nil;
    if (!safeComponent(host ?: @"") || !path.length) return nil;
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *c in [path componentsSeparatedByString:@"/"]) {
        NSString *x = c; if (!x.length) continue;
        if ([x hasSuffix:@".git"]) x = [x substringToIndex:x.length - 4];
        if (!safeComponent(x)) return nil;
        [parts addObject:x];
    }
    if (parts.count == 0 || parts.count > 6) return nil;
    return [[sourcesRoot stringByAppendingPathComponent:host] stringByAppendingPathComponent:[parts componentsJoinedByString:@"/"]];
}

NSString *HAPresetIDFromName(NSString *name) {
    NSMutableString *out = [NSMutableString string]; BOOL dash = YES;   // start "in dash" so leading junk is dropped
    for (NSUInteger i = 0; i < name.length; i++) {
        unichar ch = [name.lowercaseString characterAtIndex:i];
        if ((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9')) { [out appendFormat:@"%C", ch]; dash = NO; }
        else if (!dash) { [out appendString:@"-"]; dash = YES; }
    }
    while ([out hasSuffix:@"-"]) [out deleteCharactersInRange:NSMakeRange(out.length - 1, 1)];
    return out.length ? out : @"preset";
}

static BOOL isPluginDir(NSString *dir) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSData *pj = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"package.json"]];
    if (!pj) return NO;
    if ([fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"cordis.patch.yml"]]) return YES;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:pj options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) return NO;
    if (json[@"dsh"] || json[@"cordis"]) return YES;
    NSArray *kw = [json[@"keywords"] isKindOfClass:NSArray.class] ? json[@"keywords"] : @[];
    return [kw containsObject:@"dsh-plugin"] || [kw containsObject:@"cordis-plugin"];
}
static NSString *packageName(NSString *dir) {
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"package.json"]] ?: NSData.data options:0 error:nil];
    NSString *n = [json isKindOfClass:NSDictionary.class] && [json[@"name"] isKindOfClass:NSString.class] ? json[@"name"] : nil;
    return n.length ? n : dir.lastPathComponent;
}

static void scanDir(NSString *dir, NSUInteger depth, NSString *dshHome, NSMutableArray *presets, NSMutableArray *skills, NSMutableArray *plugins) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"preset.yml"]]) {
        HAInstallItem *it = [HAInstallItem new]; it.kind = HAInstallKindPreset; it.sourceDir = dir; it.ident = HAPresetIDFromName(dir.lastPathComponent);
        it.targetPath = [[dshHome stringByAppendingPathComponent:@".agent-presets"] stringByAppendingPathComponent:it.ident];
        it.replacesExisting = [fm fileExistsAtPath:it.targetPath]; [presets addObject:it]; return;      // a preset dir is a leaf
    }
    if ([fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"SKILL.md"]]) {
        HAInstallItem *it = [HAInstallItem new]; it.kind = HAInstallKindSkill; it.sourceDir = dir; it.ident = dir.lastPathComponent;
        it.targetPath = [[dshHome stringByAppendingPathComponent:@"skills"] stringByAppendingPathComponent:it.ident];
        it.replacesExisting = [fm fileExistsAtPath:it.targetPath]; [skills addObject:it]; return;
    }
    if (isPluginDir(dir)) {
        HAInstallItem *it = [HAInstallItem new]; it.kind = HAInstallKindPlugin; it.sourceDir = dir; it.ident = packageName(dir); [plugins addObject:it]; return;
    }
    if (depth >= 4) return;
    for (NSString *n in [[fm contentsOfDirectoryAtPath:dir error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
        if ([n hasPrefix:@"."] || [n isEqualToString:@"node_modules"]) continue;
        BOOL isDir = NO; NSString *p = [dir stringByAppendingPathComponent:n];
        if ([fm fileExistsAtPath:p isDirectory:&isDir] && isDir) scanDir(p, depth + 1, dshHome, presets, skills, plugins);
    }
}

NSArray<HAInstallItem *> *HAScanInstallables(NSString *cloneDir, NSString *dshHome) {
    NSMutableArray *p = [NSMutableArray array], *s = [NSMutableArray array], *g = [NSMutableArray array];
    scanDir(cloneDir, 0, dshHome, p, s, g);
    return [[p arrayByAddingObjectsFromArray:s] arrayByAddingObjectsFromArray:g];
}

NSString *HAInstallScript(NSArray<HAInstallItem *> *items, NSString *dshHome, NSString *dshPath, NSString *profile, NSString *stamp) {
    NSMutableString *s = [NSMutableString stringWithString:@"#!/bin/bash\nset -eu\n"];
    [s appendFormat:@"DSH_HOME=%@\n", HAShellQuote(dshHome)];
    [s appendFormat:@"echo \"Harness.app: installing %lu item(s) into $DSH_HOME\"\n", (unsigned long)items.count];
    BOOL copies = NO; for (HAInstallItem *it in items) if (it.kind != HAInstallKindPlugin) copies = YES;
    if (copies) [s appendString:@"mkdir -p \"$DSH_HOME/.agent-presets\" \"$DSH_HOME/skills\"\n"];
    for (HAInstallItem *it in items) {
        if (it.kind == HAInstallKindPlugin) {
            [s appendFormat:@"%@ plugin --profile %@ add %@\n", HAShellQuote(dshPath), HAShellQuote(profile), HAShellQuote(it.sourceDir)];
            continue;
        }
        NSString *sub = it.kind == HAInstallKindPreset ? @".agent-presets" : @"skills";
        NSString *t = [NSString stringWithFormat:@"\"$DSH_HOME/%@/%@\"", sub, it.ident];
        [s appendFormat:@"if [ -e %@ ]; then mv %@ \"$DSH_HOME/%@/%@.replaced-%@\"; echo \"moved the existing %@ aside\"; fi\n", t, t, sub, it.ident, stamp, it.ident];
        [s appendFormat:@"cp -R %@ %@\necho \"installed %@ %@\"\n", HAShellQuote(it.sourceDir), t, @[@"preset", @"skill", @"plugin"][it.kind], it.ident];
    }
    [s appendString:@"echo \"Harness.app: done — choose Server ▸ Restart Server, then pick the preset in a new session.\"\n"];
    return s;
}

static NSArray<NSString *> *dirsWithMarker(NSString *parent, NSString *marker) {
    NSFileManager *fm = [NSFileManager defaultManager]; NSMutableArray *out = [NSMutableArray array];
    for (NSString *n in [[fm contentsOfDirectoryAtPath:parent error:nil] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
        if ([n hasPrefix:@"."]) continue;
        NSString *p = [parent stringByAppendingPathComponent:n];
        if ([fm fileExistsAtPath:[p stringByAppendingPathComponent:marker]]) [out addObject:p];
    }
    return out;
}
NSArray<NSString *> *HAInstalledPresetDirs(NSString *dshHome) { return dirsWithMarker([dshHome stringByAppendingPathComponent:@".agent-presets"], @"preset.yml"); }
NSArray<NSString *> *HAInstalledSkillDirs(NSString *dshHome) {
    NSArray *a = dirsWithMarker([dshHome stringByAppendingPathComponent:@"skills"], @"SKILL.md");
    NSArray *b = dirsWithMarker([NSHomeDirectory() stringByAppendingPathComponent:@".agents/skills"], @"SKILL.md");
    return [a arrayByAddingObjectsFromArray:b];
}
```
Makefile: add `src/HAInstaller.m` to `SRC` and `LIBSRC`.

- [ ] **Step 4: Run** `make test` → 5 binaries, `0 failures`.
- [ ] **Step 5: Commit** — `git add src tests Makefile && git commit -m "feat: HAInstaller — clone target, preset/skill/plugin scan, install script"`

---

### Task 4: main.m — Prevent Sleep, owning-npm command, open-panel delegate, Settings checkbox

**Files:** Modify `src/main.m`, `src/HAPreferencesWindow.m`

- [ ] **Step 1: Wire HASleepGuard** — `#import "HASleepGuard.h"`; property `@property (strong) HASleepGuard *sleepGuard;`; in `serverDidBecomeReady:` call `[self applySleepGuard]`; add:
```objc
- (void)applySleepGuard {
    if (!self.sleepGuard) self.sleepGuard = [HASleepGuard new];
    BOOL want = [[NSUserDefaults standardUserDefaults] boolForKey:HAPrefPreventSleep] && self.server != nil && self.server.mode != HAServerModeNone;
    if (want) [self.sleepGuard activateWithReason:@"Harness.app: dsh server running"]; else [self.sleepGuard deactivate];
}
- (void)togglePreventSleep:(id)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:![d boolForKey:HAPrefPreventSleep] forKey:HAPrefPreventSleep];
    [self applySleepGuard];
}
```
Call `[self.sleepGuard deactivate]` in `applicationWillTerminate:` (before stopping) and in `replaceServerWithProfile:` / `restartServer:` before restart (re-applied on ready). `validateMenuItem:` sets state for `togglePreventSleep:`. Server menu: `[server addItem:item(@"Prevent Sleep While Running", @selector(togglePreventSleep:), @"")];` after Keep Server Running. Settings: `[self checkbox:@"Prevent sleep while the server is running (idle sleep only; a closed lid still sleeps)" key:HAPrefPreventSleep]` row after `keep`. Note: the Settings checkbox writes the pref directly; `applySleepGuard` also runs on next ready — acceptable, plus observe: in `AppDelegate` add `[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:HAPrefPreventSleep options:0 context:NULL]` in `applicationDidFinishLaunching:` and `observeValueForKeyPath:` → `[self applySleepGuard]` (remove observer in `applicationWillTerminate:`).

- [ ] **Step 2: Owning-npm command** — replace every use of `HADshInstallCommand` in `main.m` **except** `presentInstallGuidance` with `[self dshInstallCommand]`:
```objc
- (NSString *)dshInstallCommand { return HADshInstallCommandForPackageDir(self.env.dshPackageDir); }
```
(`runInstallCommandWithTitle:` and the update sheet in `checkDshUpdatesNow:`.)

- [ ] **Step 3: Open panel delegate** — add to the WKUIDelegate section:
```objc
- (void)webView:(WKWebView *)webView runOpenPanelWithParameters:(WKOpenPanelParameters *)parameters initiatedByFrame:(WKFrameInfo *)frame
        completionHandler:(void (^)(NSArray<NSURL *> *_Nullable))completionHandler {
    NSOpenPanel *p = [NSOpenPanel openPanel];
    p.canChooseFiles = YES; p.canChooseDirectories = parameters.allowsDirectories; p.allowsMultipleSelection = parameters.allowsMultipleSelection;
    [p beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) { completionHandler(r == NSModalResponseOK ? p.URLs : nil); }];
}
```
- [ ] **Step 4: Build + test** — `make app test` → builds, all `0 failures`.
- [ ] **Step 5: Commit** — `git commit -am "feat: Prevent Sleep While Running; update command targets owning npm; WKWebView file chooser"`

---

### Task 5: main.m — dsh menu: Reveal items, Edit Profile Config, Presets ▸ / Skills ▸

**Files:** Modify `src/main.m`

- [ ] **Step 1: Actions**
```objc
- (NSString *)dshHome { return HADshHome(self.env.shellEnvironment); }
- (void)revealPath:(NSString *)path {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) { [self presentSheetTitle:@"Not there yet" detail:[NSString stringWithFormat:@"%@ does not exist. dsh creates it on first use.", [path stringByAbbreviatingWithTildeInPath]] buttons:@[@"OK"] handler:nil]; return; }
    [[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""];
}
- (void)revealDshHome:(id)sender { [self revealPath:[self dshHome]]; }
- (void)revealSessions:(id)sender { [self revealPath:[[self dshHome] stringByAppendingPathComponent:@"sessions"]]; }
- (void)revealPresetsFolder:(id)sender { [self revealPath:[[self dshHome] stringByAppendingPathComponent:@".agent-presets"]]; }
- (void)revealSkillsFolder:(id)sender { [self revealPath:[[self dshHome] stringByAppendingPathComponent:@"skills"]]; }
- (void)revealMenuItemPath:(NSMenuItem *)sender { [self revealPath:sender.representedObject]; }
- (void)editProfileConfig:(id)sender {
    NSString *profile = [[NSUserDefaults standardUserDefaults] stringForKey:HAPrefProfile] ?: HADefaultProfile;
    NSString *file = [[[self dshHome] stringByAppendingPathComponent:[@"profiles/" stringByAppendingString:profile]] stringByAppendingPathComponent:@"cordis.patch.yml"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:file]) {
        [self presentSheetTitle:@"No profile config yet" detail:[NSString stringWithFormat:@"%@ does not exist. dsh writes it the first time the “%@” profile boots.", [file stringByAbbreviatingWithTildeInPath], profile]
                        buttons:@[@"Restart Server", @"OK"] handler:^(NSInteger i) { if (i == 0) [self restartServer:nil]; }];
        return;
    }
    NSURL *u = [NSURL fileURLWithPath:file];
    if (![[NSWorkspace sharedWorkspace] openURL:u]) {
        NSURL *textEdit = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"com.apple.TextEdit"];
        if (textEdit) [[NSWorkspace sharedWorkspace] openURLs:@[u] withApplicationAtURL:textEdit configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
    }
}
```
- [ ] **Step 2: Submenus** — properties `presetsMenu`, `skillsMenu`; extend `menuNeedsUpdate:`:
```objc
- (void)fillListMenu:(NSMenu *)menu dirs:(NSArray<NSString *> *)dirs revealTitle:(NSString *)revealTitle revealAction:(SEL)revealAction folder:(NSString *)folder {
    [menu removeAllItems];
    NSMenuItem *rev = item(revealTitle, revealAction, @""); rev.target = self; [menu addItem:rev];
    [menu addItem:[NSMenuItem separatorItem]];
    if (dirs.count == 0) { NSMenuItem *none = item(@"(none installed)", NULL, @""); none.enabled = NO; [menu addItem:none]; }
    for (NSString *d in dirs) {
        NSString *title = [d hasPrefix:folder] ? d.lastPathComponent : [NSString stringWithFormat:@"%@  (~/.agents)", d.lastPathComponent];
        NSMenuItem *it = item(title, @selector(revealMenuItemPath:), @""); it.target = self; it.representedObject = d; [menu addItem:it];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *rs = item(@"Restart Server", @selector(restartServer:), @""); rs.target = self; [menu addItem:rs];
}
```
and in `menuNeedsUpdate:`:
```objc
    if (menu == self.presetsMenu) { [self fillListMenu:menu dirs:HAInstalledPresetDirs([self dshHome]) revealTitle:@"Reveal Presets Folder" revealAction:@selector(revealPresetsFolder:) folder:[[self dshHome] stringByAppendingPathComponent:@".agent-presets"]]; return; }
    if (menu == self.skillsMenu)  { [self fillListMenu:menu dirs:HAInstalledSkillDirs([self dshHome])  revealTitle:@"Reveal Skills Folder"  revealAction:@selector(revealSkillsFolder:)  folder:[[self dshHome] stringByAppendingPathComponent:@"skills"]]; return; }
    if (menu != self.profileMenu) return;
```
(`item()` is a file-static defined below the class — move the static helper above `@implementation AppDelegate` or forward-declare it.) `validateMenuItem:` must return YES for `revealMenuItemPath:` etc. (default branch already does); `restartServer:` returns `self.server != nil`.

- [ ] **Step 3: Menu bar** (dsh menu, in `buildMenu`):
```objc
    [dsh addItem:[NSMenuItem separatorItem]];
    [dsh addItem:item(@"Install from Git URL…", @selector(installFromGitURL:), @"")];      // Task 6
    NSMenuItem *presetsItem = item(@"Presets", NULL, @""); d.presetsMenu = [[NSMenu alloc] initWithTitle:@"Presets"]; d.presetsMenu.delegate = d; presetsItem.submenu = d.presetsMenu; [dsh addItem:presetsItem];
    NSMenuItem *skillsItem = item(@"Skills", NULL, @""); d.skillsMenu = [[NSMenu alloc] initWithTitle:@"Skills"]; d.skillsMenu.delegate = d; skillsItem.submenu = d.skillsMenu; [dsh addItem:skillsItem];
    [dsh addItem:[NSMenuItem separatorItem]];
    [dsh addItem:item(@"Reveal dsh Home", @selector(revealDshHome:), @"")];
    [dsh addItem:item(@"Reveal Sessions", @selector(revealSessions:), @"")];
    [dsh addItem:item(@"Edit Profile Config…", @selector(editProfileConfig:), @"")];
    [dsh addItem:[NSMenuItem separatorItem]];
    [dsh addItem:item(@"Repair Shell Tools…", @selector(repairShellTools:), @"")];
```
(remove the old separator + Repair line so Repair appears once, last.) Temporarily stub `installFromGitURL:` (empty) so it builds; Task 6 fills it.

- [ ] **Step 4: Build, launch, click through** — `make app && open build/Harness.app`; menu items open Finder / editor; quit. `make test` still green.
- [ ] **Step 5: Commit** — `git commit -am "feat: dsh menu — Presets/Skills listings, Reveal dsh Home/Sessions, Edit Profile Config"`

---

### Task 6: main.m — Install from Git URL… flow

**Files:** Modify `src/main.m`

- [ ] **Step 1: URL prompt + clone (off main thread)**
```objc
@property BOOL installing;
- (void)installFromGitURL:(id)sender {
    if (self.installing) { [self setNotice:@"an install is already running" forKey:@"install"]; return; }
    NSAlert *a = [NSAlert new];
    a.messageText = @"Install a dsh preset, skill or plugin from Git";
    a.informativeText = @"Paste the repository URL. Harness clones it (into ~/Library/Application Support/Harness.app/sources), shows what it found, and installs only what you tick — visibly, in Terminal. Nothing is curated or bundled; you are trusting the repository you paste.";
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 420, 24)]; f.placeholderString = @"https://github.com/owner/repo"; a.accessoryView = f;
    [a addButtonWithTitle:@"Fetch"]; [a addButtonWithTitle:@"Cancel"];
    a.window.initialFirstResponder = f;
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r != NSAlertFirstButtonReturn) return;
        [self cloneAndScan:f.stringValue];
    }];
}
- (void)cloneAndScan:(NSString *)url {
    NSString *target = HAInstallCloneTargetForURL(url, HASourcesRoot());
    if (!target) { [self presentSheetTitle:@"That doesn't look like a Git repository URL" detail:@"Use https://host/owner/repo, git@host:owner/repo.git or ssh://…" buttons:@[@"OK"] handler:nil]; return; }
    NSString *git = HAFindExecutable(@"git", self.env.shellEnvironment[@"PATH"]) ?: ([[NSFileManager defaultManager] isExecutableFileAtPath:@"/usr/bin/git"] ? @"/usr/bin/git" : nil);
    if (!git) { [self presentSheetTitle:@"git was not found" detail:@"Install the Xcode Command Line Tools: xcode-select --install" buttons:@[@"OK"] handler:nil]; return; }
    self.installing = YES; [self setNotice:[NSString stringWithFormat:@"cloning %@…", url] forKey:@"install"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:target.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [fm removeItemAtPath:target error:nil];
        int status = -1;
        NSMutableDictionary *env = [self.env.shellEnvironment mutableCopy]; env[@"GIT_TERMINAL_PROMPT"] = @"0";
        NSString *out = HARunCommandOutput(git, @[@"clone", @"--depth", @"1", @"--recurse-submodules", @"--shallow-submodules", @"--quiet", url, target], env, 120, &status);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.installing = NO; [self setNotice:nil forKey:@"install"];
            if (status != 0) {
                NSString *cmd = [NSString stringWithFormat:@"git clone --depth 1 --recurse-submodules %@ %@", HAShellQuote(url), HAShellQuote(target)];
                [self presentSheetTitle:@"git clone failed" detail:[NSString stringWithFormat:@"%@\n\n%@", out.length ? out : (status == -1 ? @"git did not answer within 120 s (or needs credentials — Harness never prompts for them)." : [NSString stringWithFormat:@"exit status %d", status]), cmd]
                                buttons:@[@"Copy Command", @"OK"] handler:^(NSInteger i) { if (i == 0) { [[NSPasteboard generalPasteboard] clearContents]; [[NSPasteboard generalPasteboard] setString:cmd forType:NSPasteboardTypeString]; } }];
                return;
            }
            [self presentInstallChoicesFor:target url:url];
        });
    });
}
```
Note `HARunCommandOutput` discards stderr; to show git's error, wrap: use `@[@"-c", @"…"]`? Simpler: run `/bin/sh -c "git clone … 2>&1"` — build the shell line with `HAShellQuote` for url/target and pass to `HARunCommandOutput(@"/bin/sh", @[@"-c", line], env, 120, &status)`. Do that.

- [ ] **Step 2: Choices sheet + Terminal hand-off**
```objc
- (void)presentInstallChoicesFor:(NSString *)clone url:(NSString *)url {
    NSArray<HAInstallItem *> *items = HAScanInstallables(clone, [self dshHome]);
    NSString *readme = nil; for (NSString *n in @[@"README.md", @"readme.md", @"README", @"README.zh-CN.md"]) if ([[NSFileManager defaultManager] fileExistsAtPath:[clone stringByAppendingPathComponent:n]]) { readme = [clone stringByAppendingPathComponent:n]; break; }
    if (items.count == 0) {
        [self presentSheetTitle:@"No presets, skills or plugins recognised" detail:@"Harness looks for directories with preset.yml (agent presets), SKILL.md (skills) or package.json + cordis.patch.yml (plugins). This repository has none at depth ≤ 4, so follow its own instructions."
                        buttons:@[@"Reveal Clone", readme ? @"Open README" : @"OK"] handler:^(NSInteger i) {
            if (i == 0) [[NSWorkspace sharedWorkspace] selectFile:clone inFileViewerRootedAtPath:@""];
            else if (readme) [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:readme]];
        }];
        return;
    }
    NSAlert *a = [NSAlert new];
    a.messageText = [NSString stringWithFormat:@"Found in %@", clone.lastPathComponent];
    a.informativeText = @"Tick what to install. Presets go to $DSH_HOME/.agent-presets, skills to $DSH_HOME/skills; plugins run `dsh plugin add`. Anything already there is moved aside (never deleted). The full script is shown before it runs.";
    NSStackView *stack = [NSStackView stackViewWithViews:@[]]; stack.orientation = NSUserInterfaceLayoutOrientationVertical; stack.alignment = NSLayoutAttributeLeading; stack.spacing = 4;
    NSMutableArray<NSButton *> *boxes = [NSMutableArray array];
    for (HAInstallItem *it in items) { NSButton *b = [NSButton checkboxWithTitle:it.label target:nil action:nil]; b.state = NSControlStateValueOn; [stack addArrangedSubview:b]; [boxes addObject:b]; }
    stack.frame = NSMakeRect(0, 0, 520, MAX(24, 22 * items.count)); a.accessoryView = stack;
    [a addButtonWithTitle:@"Continue"]; [a addButtonWithTitle:@"Reveal Clone"]; [a addButtonWithTitle:@"Cancel"];
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r == NSAlertSecondButtonReturn) { [[NSWorkspace sharedWorkspace] selectFile:clone inFileViewerRootedAtPath:@""]; return; }
        if (r != NSAlertFirstButtonReturn) return;
        NSMutableArray *chosen = [NSMutableArray array];
        for (NSUInteger i = 0; i < items.count; i++) if (boxes[i].state == NSControlStateValueOn) [chosen addObject:items[i]];
        if (!chosen.count) return;
        [self confirmAndRunInstall:chosen clone:clone];
    }];
}
- (void)confirmAndRunInstall:(NSArray<HAInstallItem *> *)items clone:(NSString *)clone {
    NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"yyyyMMdd-HHmmss"; NSString *stamp = [df stringFromDate:[NSDate date]];
    NSString *profile = [[NSUserDefaults standardUserDefaults] stringForKey:HAPrefProfile] ?: HADefaultProfile;
    NSString *script = HAInstallScript(items, [self dshHome], self.env.dshPath, profile, stamp);
    NSString *file = [HASourcesRoot() stringByAppendingFormat:@"/install-%@.sh", stamp];
    [script writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod(file.fileSystemRepresentation, 0700);
    NSAlert *a = [NSAlert new]; a.messageText = @"This is exactly what will run in Terminal";
    a.informativeText = [NSString stringWithFormat:@"Saved as %@ — Terminal runs it with bash -ex, echoing every command.", [file stringByAbbreviatingWithTildeInPath]];
    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 560, 200)]; tv.string = script; tv.editable = NO; tv.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 560, 200)]; sv.documentView = tv; sv.hasVerticalScrollBar = YES; sv.borderType = NSBezelBorder; a.accessoryView = sv;
    [a addButtonWithTitle:@"Install in Terminal"]; [a addButtonWithTitle:@"Copy Script"]; [a addButtonWithTitle:@"Cancel"];
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r == NSAlertSecondButtonReturn) { [[NSPasteboard generalPasteboard] clearContents]; [[NSPasteboard generalPasteboard] setString:script forType:NSPasteboardTypeString]; return; }
        if (r != NSAlertFirstButtonReturn) return;
        NSError *err = nil;
        if (![HAUpdater runInTerminal:[@"bash -ex " stringByAppendingString:HAShellQuote(file)] error:&err]) { [self presentSheetTitle:@"Could not open Terminal" detail:err.localizedDescription buttons:@[@"OK"] handler:nil]; return; }
        [self presentSheetTitle:@"Installing in Terminal…" detail:@"Every command is echoed there. When it finishes, choose Server ▸ Restart Server, then pick the preset (or use the skill) in a new session." buttons:@[@"OK"] handler:nil];
    }];
}
```
`#import "HAInstaller.h"` and `#import <sys/stat.h>` in `main.m`.

- [ ] **Step 3: Build; live test with a real repo** — `make app && open build/Harness.app`; dsh ▸ Install from Git URL… → `https://github.com/Tiger3807861189/J-Space-Cognition-Suite-V3.6` → sheet shows `skill j-space → ~/.dsh/skills/j-space`; Cancel (do not install on Arnold's machine without his say — the Terminal step is his manual acceptance). Repeat with `https://github.com/xiaobright/dsh-anchored-standard` → seven presets, no plugin. Try `https://github.com/aconcepcion/harness-app` → "No presets…" sheet with Open README.
- [ ] **Step 4: `make test`** green. **Step 5: Commit** — `git commit -am "feat: Install from Git URL — clone, detect presets/skills/plugins, install visibly in Terminal"`

---

### Task 7: Smoke scenario, version bump, CHANGELOG

**Files:** Modify `scripts/smoke.sh`, `Makefile` (VERSION), `src/HAConfig.h` (HAAppVersion), `CHANGELOG.md`

- [ ] **Step 1: Smoke 5** (before the final `echo "smoke: …"`; also add `defaults write "$DOMAIN" PreventSleepWhileRunning -bool NO` to the setup block):
```bash
echo "5. prevent-sleep: assertion held while running, released on quit"
defaults write "$DOMAIN" PreventSleepWhileRunning -bool YES
launch; wait_for up 60 || fail "prevent-sleep: server never came up"
wait_for "pmset -g assertions | grep -q 'Harness.app: dsh server running'" 20 && ok "IOPM assertion present" || fail "no sleep assertion while running"
stop_app; sleep 1
pmset -g assertions | grep -q 'Harness.app: dsh server running' && fail "assertion survived quit" || ok "assertion released"
defaults write "$DOMAIN" PreventSleepWhileRunning -bool NO
```
- [ ] **Step 2: Bump** `VERSION = 3.1.0`, `HAAppVersion = @"3.1.0"`. CHANGELOG entry:
```
## 3.1.0 — 2026-08-18
- dsh ▸ Install from Git URL…: clone a preset / skill / plugin repository, tick what to install, run it visibly in Terminal (presets → $DSH_HOME/.agent-presets, skills → $DSH_HOME/skills, plugins → dsh plugin add); existing items are moved aside, never deleted
- dsh ▸ Presets / Skills submenus list what is installed (Reveal in Finder, Restart Server)
- dsh ▸ Reveal dsh Home, Reveal Sessions, Edit Profile Config… (cordis.patch.yml)
- Update dsh… / Repair Shell Tools… now target the npm prefix that owns the found dsh (no second copy when the login shell's first npm differs)
- Server ▸ Prevent Sleep While Running (idle-sleep assertion; off by default)
- File choosers inside the web UI now open a native panel (WKUIDelegate runOpenPanel)
- Privacy: Install from Git URL contacts only the host of the URL you paste, only when you click Fetch
```
- [ ] **Step 3: Run** `make clean && make app test smoke` → `0 failures` ×5, `smoke: 0 failure(s)`, `--version` prints 3.1.0.
- [ ] **Step 4: Commit** — `git commit -am "test: smoke scenario for Prevent Sleep; build: 3.1.0; changelog"`

---

### Task 8: Docs — README EN/中文/ES, AGENTS.md, plan status

**Files:** Modify `README.md`, `README.zh.md`, `README.es.md`, `AGENTS.md`

- [ ] **Step 1: README.md** — (a) hero paragraph: "…stops it when you close the window. ~1,500 lines of Objective-C." (use the real `wc -l src/*.m src/*.h` total, rounded); (b) after *What it actually does* add section **Presets, skills and plugins** (what Install from Git URL does, where things go, the never-delete rule, the two submenus, the Reveal/Edit items, one-line honesty: "Harness does not curate or vet repositories"); (c) *What it actually does* bullets: add **Prevent Sleep**, **File choosers**; (d) Settings table: add `PreventSleepWhileRunning` (BOOL, NO); (e) *Privacy & network*: add the git-host sentence; (f) *For AI agents* Configure block: `defaults write com.arnoldoconcepcion.harness-app PreventSleepWhileRunning -bool NO`; (g) menu list in the "The parts that are ours" caption unchanged (screenshots regenerated in Task 9 if possible). Update the "1,200 lines" mentions everywhere (`grep -n "1,200"`).
- [ ] **Step 2: README.zh.md / README.es.md** — same edits, translated (keep command lines identical).
- [ ] **Step 3: AGENTS.md** — Layout: add `HAInstaller.[mh]`, `HASleepGuard.[mh]`; Conventions: network line gains "and the git host of a URL the user pastes (Install from Git URL…)"; invariant sentence: "never write into `~/.dsh` **from the app process** — installs run visibly in Terminal"; test list mentions `test_installer`, `test_sleepguard`.
- [ ] **Step 4: Commit** — `git commit -am "docs: v3.1 README (en/zh/es), AGENTS.md"`

---

### Task 9: Release 3.1.0

- [ ] **Step 1:** `make clean && make app test smoke` green; `git status` clean; `git log` shows no attribution trailers (`git log --format=%B | grep -i -E 'co-authored|claude|generated with'` → empty).
- [ ] **Step 2:** Menu screenshots: try automated capture (open app, AppleScript click menu bar item "dsh"/"Server" via System Events, `screencapture -R`); if Accessibility is not granted, keep the 3.0 images and list "regenerate menu-dsh.png / menu-server.png" as an owed manual item.
- [ ] **Step 3:** `git checkout main && git merge --ff-only feat/v3.1 && git push origin main && git branch -d feat/v3.1`; wait for CI green (`gh run watch`).
- [ ] **Step 4:** `git tag -a v3.1.0 -m "Harness.app 3.1.0" && git push origin v3.1.0`; `gh release create v3.1.0 --title "Harness.app 3.1.0" --notes-file <(CHANGELOG 3.1.0 section)`.
- [ ] **Step 5:** Formula: `curl -sL https://github.com/aconcepcion/harness-app/archive/refs/tags/v3.1.0.tar.gz | shasum -a 256`; update `Formula/harness-app.rb` url + sha256; commit + push to main; mirror to `aconcepcion/homebrew-tap` (clone to scratch, replace `Formula/harness-app.rb`, commit "harness-app 3.1.0", push). Verify: `brew update && brew upgrade harness-app && brew test harness-app` and `/opt/homebrew/opt/harness-app/Harness.app/Contents/MacOS/Harness --version` → 3.1.0; `make install` for `/Applications`.
- [ ] **Step 6:** Report to Arnold with the owed manual checks (Install a real preset end-to-end incl. Terminal step; file chooser inside UI; Prevent Sleep vs `pmset`; screenshots if not regenerated).
