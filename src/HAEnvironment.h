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
