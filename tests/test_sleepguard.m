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
