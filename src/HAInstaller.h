#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

// Install-from-Git support: pure functions that decide WHERE a repository is cloned, WHAT in it is a
// dsh preset / skill / plugin, and WHICH commands install it. The app never runs those commands itself;
// they are shown to the user and executed visibly in Terminal (see main.m). Conventions come from dsh:
// a preset is a directory holding preset.yml (dsh-agent-presets, user root $DSH_HOME/.agent-presets,
// id ^[a-z0-9][a-z0-9-]*$); a skill is a directory holding SKILL.md ($DSH_HOME/skills, also
// ~/.agents/skills); a plugin is installed with `dsh plugin --profile <p> add <path>`.

typedef NS_ENUM(NSInteger, HAInstallKind) { HAInstallKindPreset = 0, HAInstallKindSkill, HAInstallKindPlugin };

@interface HAInstallItem : NSObject
@property HAInstallKind kind;
@property (copy) NSString *sourceDir;              // inside the clone
@property (copy) NSString *ident;                  // preset id / skill dir name / package name
@property (copy, nullable) NSString *targetPath;   // nil for plugins
@property BOOL replacesExisting;
- (NSString *)label;   // "preset router-standard → ~/.dsh/.agent-presets/router-standard (replaces existing)"
@end

NSString *HASourcesRoot(void);                                                       // ~/Library/Application Support/Harness.app/sources
NSString *_Nullable HAInstallCloneTargetForURL(NSString *url, NSString *sourcesRoot); // nil = rejected URL
NSString *HAPresetIDFromName(NSString *name);
NSArray<HAInstallItem *> *HAScanInstallables(NSString *cloneDir, NSString *dshHome);  // presets, then skills, then plugins
NSString *HAInstallScript(NSArray<HAInstallItem *> *items, NSString *dshHome, NSString *dshPath, NSString *profile, NSString *stamp);
NSArray<NSString *> *HAInstalledPresetDirs(NSString *dshHome);                       // dirs holding preset.yml under .agent-presets
NSArray<NSString *> *HAInstalledSkillDirs(NSString *dshHome);                        // dirs holding SKILL.md under $DSH_HOME/skills, then ~/.agents/skills
NS_ASSUME_NONNULL_END
