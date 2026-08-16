#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN
/// "web" plus every directory under $DSH_HOME/profiles (default ~/.dsh/profiles), excluding node_modules and dotfiles.
NSArray<NSString *> *HAAvailableProfiles(NSDictionary<NSString *, NSString *> *_Nullable env);

@interface HAPreferencesWindowController : NSWindowController
- (instancetype)initWithOpenLog:(void (^)(void))openLog;
@end
NS_ASSUME_NONNULL_END
