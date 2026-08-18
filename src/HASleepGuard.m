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
- (void)deactivate {
    if (!self.active) return;
    IOPMAssertionRelease(_assertion); _assertion = 0; self.active = NO;
}
- (void)dealloc { [self deactivate]; }
@end
