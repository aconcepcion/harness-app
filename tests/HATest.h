#import <Foundation/Foundation.h>
static int HAFailures = 0, HAChecks = 0;
#define HA_ASSERT(cond, ...) do { HAChecks++; if (!(cond)) { HAFailures++; \
    fprintf(stderr, "  FAIL %s:%d: ", __FILE__, __LINE__); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } } while (0)
#define HA_EQ_STR(a, b) HA_ASSERT([(a) isEqualToString:(b)], "expected \"%s\" got \"%s\"", [(b) UTF8String], [(a) UTF8String])
#define HA_DONE() do { printf("%s: %d checks, %d failures\n", __FILE__, HAChecks, HAFailures); return HAFailures ? 1 : 0; } while (0)
// Spin the main run loop until block returns YES or timeout; returns whether it did.
static inline BOOL HAWaitUntil(NSTimeInterval timeout, BOOL (^cond)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!cond()) {
        if ([deadline timeIntervalSinceNow] <= 0) return NO;
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return YES;
}
