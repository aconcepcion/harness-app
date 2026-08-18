#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Holds a power-management assertion that prevents idle system sleep while active (IOPMAssertion).
/// Idle sleep only: a closed MacBook lid still sleeps unless macOS clamshell rules apply.
@interface HASleepGuard : NSObject
@property (readonly) BOOL active;
- (BOOL)activateWithReason:(NSString *)reason;   // idempotent; NO if the system refused
- (void)deactivate;                              // idempotent
@end
NS_ASSUME_NONNULL_END
