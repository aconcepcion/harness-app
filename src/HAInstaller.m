#import "HAInstaller.h"
#import "HAUpdater.h"

static NSString *kindName(HAInstallKind k) { return @[@"preset", @"skill", @"plugin"][k]; }

@implementation HAInstallItem
- (NSString *)label {
    if (self.kind == HAInstallKindPlugin) return [NSString stringWithFormat:@"plugin %@ (dsh plugin add %@)", self.ident, self.sourceDir.lastPathComponent];
    return [NSString stringWithFormat:@"%@ %@ → %@%@", kindName(self.kind), self.ident,
            [self.targetPath stringByAbbreviatingWithTildeInPath], self.replacesExisting ? @" (replaces existing)" : @""];
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
    NSRange at = [url rangeOfString:@"@"], colon = [url rangeOfString:@":"];
    if ([url hasPrefix:@"https://"] || [url hasPrefix:@"http://"] || [url hasPrefix:@"ssh://"] || [url hasPrefix:@"git://"]) {
        NSURL *u = [NSURL URLWithString:url]; host = u.host; path = u.path;
    } else if (at.location != NSNotFound && colon.location != NSNotFound && colon.location > at.location && [url rangeOfString:@"://"].location == NSNotFound) {
        NSString *rest = [url substringFromIndex:at.location + 1]; NSRange c = [rest rangeOfString:@":"];   // git@host:owner/repo.git
        host = [rest substringToIndex:c.location]; path = [rest substringFromIndex:c.location + 1];
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
    NSMutableString *out = [NSMutableString string]; BOOL dash = YES;   // start "in a dash" so leading junk is dropped
    NSString *lower = name.lowercaseString;
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar ch = [lower characterAtIndex:i];
        if ((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9')) { [out appendFormat:@"%C", ch]; dash = NO; }
        else if (!dash) { [out appendString:@"-"]; dash = YES; }
    }
    while ([out hasSuffix:@"-"]) [out deleteCharactersInRange:NSMakeRange(out.length - 1, 1)];
    return out.length ? out : @"preset";
}

static NSDictionary *packageJSON(NSString *dir) {
    NSData *d = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"package.json"]];
    id json = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    return [json isKindOfClass:NSDictionary.class] ? json : nil;
}
static BOOL isPluginDir(NSString *dir) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:@"package.json"]]) return NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:@"cordis.patch.yml"]]) return YES;
    NSDictionary *json = packageJSON(dir);
    if (json[@"dsh"] || json[@"cordis"]) return YES;
    NSArray *kw = [json[@"keywords"] isKindOfClass:NSArray.class] ? json[@"keywords"] : @[];
    return [kw containsObject:@"dsh-plugin"] || [kw containsObject:@"cordis-plugin"];
}

static HAInstallItem *makeItem(HAInstallKind kind, NSString *dir, NSString *ident, NSString *target) {
    HAInstallItem *it = [HAInstallItem new]; it.kind = kind; it.sourceDir = dir; it.ident = ident; it.targetPath = target;
    it.replacesExisting = target && [[NSFileManager defaultManager] fileExistsAtPath:target];
    return it;
}

static void scanDir(NSString *dir, NSUInteger depth, NSString *dshHome, NSMutableArray *presets, NSMutableArray *skills, NSMutableArray *plugins) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"preset.yml"]]) {   // a preset dir is a leaf
        NSString *ident = HAPresetIDFromName(dir.lastPathComponent);
        [presets addObject:makeItem(HAInstallKindPreset, dir, ident, [[dshHome stringByAppendingPathComponent:@".agent-presets"] stringByAppendingPathComponent:ident])];
        return;
    }
    if ([fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"SKILL.md"]]) {
        NSString *ident = dir.lastPathComponent;
        [skills addObject:makeItem(HAInstallKindSkill, dir, ident, [[dshHome stringByAppendingPathComponent:@"skills"] stringByAppendingPathComponent:ident])];
        return;
    }
    if (isPluginDir(dir)) {
        NSString *name = packageJSON(dir)[@"name"];
        [plugins addObject:makeItem(HAInstallKindPlugin, dir, [name isKindOfClass:NSString.class] && [name length] ? name : dir.lastPathComponent, nil)];
        return;
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
        [s appendFormat:@"cp -R %@ %@\necho \"installed %@ %@\"\n", HAShellQuote(it.sourceDir), t, kindName(it.kind), it.ident];
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
    return [dirsWithMarker([dshHome stringByAppendingPathComponent:@"skills"], @"SKILL.md")
            arrayByAddingObjectsFromArray:dirsWithMarker([NSHomeDirectory() stringByAppendingPathComponent:@".agents/skills"], @"SKILL.md")];
}
