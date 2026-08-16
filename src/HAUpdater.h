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
