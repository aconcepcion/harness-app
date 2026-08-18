#import "HATest.h"
#import "HAInstaller.h"
#import "HAUpdater.h"

static void mkfile(NSString *p, NSString *s) {
    [[NSFileManager defaultManager] createDirectoryAtPath:p.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [s writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

int main(void) { @autoreleasepool {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *root = @"/tmp/ha-src";

    // Clone target derived from the URL; anything that could escape the sources root is rejected.
    HA_EQ_STR(HAInstallCloneTargetForURL(@"https://github.com/xiaobright/dsh-anchored-standard", root) ?: @"nil", @"/tmp/ha-src/github.com/xiaobright/dsh-anchored-standard");
    HA_EQ_STR(HAInstallCloneTargetForURL(@"  https://github.com/Owner/Repo.git/ ", root) ?: @"nil", @"/tmp/ha-src/github.com/Owner/Repo");
    HA_EQ_STR(HAInstallCloneTargetForURL(@"git@github.com:owner/repo.git", root) ?: @"nil", @"/tmp/ha-src/github.com/owner/repo");
    HA_EQ_STR(HAInstallCloneTargetForURL(@"ssh://git@gitlab.com/group/sub/repo.git", root) ?: @"nil", @"/tmp/ha-src/gitlab.com/group/sub/repo");
    HA_ASSERT(HAInstallCloneTargetForURL(@"https://github.com/../etc/passwd", root) == nil, "dotdot rejected");
    HA_ASSERT(HAInstallCloneTargetForURL(@"https://github.com/", root) == nil, "no path rejected");
    HA_ASSERT(HAInstallCloneTargetForURL(@"file:///etc", root) == nil, "file scheme rejected");
    HA_ASSERT(HAInstallCloneTargetForURL(@"not a url", root) == nil, "garbage rejected");
    HA_ASSERT(HAInstallCloneTargetForURL(@"", root) == nil, "empty rejected");

    // Preset ids: dsh requires ^[a-z0-9][a-z0-9-]*$
    HA_EQ_STR(HAPresetIDFromName(@"Router_Standard"), @"router-standard");
    HA_EQ_STR(HAPresetIDFromName(@"--Weird  Name!"), @"weird-name");
    HA_EQ_STR(HAPresetIDFromName(@"ok-1"), @"ok-1");
    HA_EQ_STR(HAPresetIDFromName(@"!!!"), @"preset");

    // Scan a synthetic clone shaped like the real community repos.
    NSString *clone = [NSTemporaryDirectory() stringByAppendingFormat:@"haclone-%d", getpid()];
    NSString *home  = [NSTemporaryDirectory() stringByAppendingFormat:@"hahome-%d", getpid()];
    [fm removeItemAtPath:clone error:nil]; [fm removeItemAtPath:home error:nil];
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
    HA_ASSERT(items[0].kind == HAInstallKindPreset && items[items.count - 1].kind == HAInstallKindPlugin, "ordered presets, skills, plugins");

    // The script: bash -eu, one mkdir, move-aside (never delete), cp -R, dsh plugin add, closing hint.
    NSString *s = HAInstallScript(items, home, @"/opt/homebrew/bin/dsh", @"web", @"20260818-120000");
    HA_ASSERT([s hasPrefix:@"#!/bin/bash\nset -eu\n"], "bash header");
    HA_ASSERT(([s containsString:[NSString stringWithFormat:@"DSH_HOME=%@", HAShellQuote(home)]]), "DSH_HOME line");
    HA_ASSERT([s containsString:@"mkdir -p \"$DSH_HOME/.agent-presets\" \"$DSH_HOME/skills\""], "mkdir once");
    HA_ASSERT([s containsString:@"mv \"$DSH_HOME/.agent-presets/router-standard\" \"$DSH_HOME/.agent-presets/router-standard.replaced-20260818-120000\""], "existing moved aside");
    HA_ASSERT(([s containsString:[NSString stringWithFormat:@"cp -R %@ \"$DSH_HOME/.agent-presets/router-standard\"", HAShellQuote([clone stringByAppendingPathComponent:@"preset/router-standard"])]]), "cp preset");
    HA_ASSERT([s containsString:@"\"$DSH_HOME/skills/j-space\""], "cp skill");
    HA_ASSERT(([s containsString:[NSString stringWithFormat:@"'/opt/homebrew/bin/dsh' plugin --profile 'web' add %@", HAShellQuote([clone stringByAppendingPathComponent:@"injector"])]]), "plugin add");
    HA_ASSERT(![s containsString:@"rm -rf"], "never rm -rf");
    HA_ASSERT([s containsString:@"Server ▸ Restart Server"], "closing hint");
    NSUInteger mkdirs = [[s componentsSeparatedByString:@"mkdir -p"] count] - 1;
    HA_ASSERT(mkdirs == 1, "exactly one mkdir, got %lu", (unsigned long)mkdirs);

    // Installed listings
    HA_ASSERT(HAInstalledPresetDirs(home).count == 1, "one installed preset");
    HA_ASSERT(HAInstalledSkillDirs(home).count == 0, "no skills");
    HA_ASSERT([HASourcesRoot() hasSuffix:@"Library/Application Support/Harness.app/sources"], "sources root under Application Support");

    [fm removeItemAtPath:clone error:nil]; [fm removeItemAtPath:home error:nil];
    HA_DONE();
} }
