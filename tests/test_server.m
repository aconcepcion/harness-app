#import "HATest.h"
#import "HAServer.h"
#import <signal.h>
#import <sys/wait.h>

@interface Recorder : NSObject <HAServerDelegate>
@property int ready, failed, restarted, gaveUp; @property NSString *lastReason;
@end
@implementation Recorder
- (void)serverDidBecomeReady:(HAServer *)s { self.ready++; }
- (void)server:(HAServer *)s didFailToStart:(NSString *)r { self.failed++; self.lastReason = r; }
- (void)serverDidRestart:(HAServer *)s { self.restarted++; }
- (void)server:(HAServer *)s didGiveUp:(NSString *)r { self.gaveUp++; self.lastReason = r; }
@end

static BOOL alive(pid_t pid) { return pid > 0 && (kill(pid, 0) == 0 || errno == EPERM); }
static pid_t childOf(pid_t pid) { // first child pid via pgrep -P
    NSTask *t = [NSTask new]; t.executableURL = [NSURL fileURLWithPath:@"/usr/bin/pgrep"]; t.arguments = @[@"-P", @(pid).stringValue];
    NSPipe *p = [NSPipe pipe]; t.standardOutput = p; [t launchAndReturnError:nil];
    NSString *s = [[NSString alloc] initWithData:[[p fileHandleForReading] readDataToEndOfFile] encoding:NSUTF8StringEncoding];
    [t waitUntilExit]; return (pid_t)[[s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] intValue];
}
static HAServer *make(NSString *fake, uint16_t port, NSDictionary *extraEnv, NSString *log) {
    NSMutableDictionary *env = [[NSProcessInfo processInfo].environment mutableCopy];
    [env addEntriesFromDictionary:extraEnv ?: @{}];
    return [[HAServer alloc] initWithDshPath:fake port:port profile:@"web" workspace:NSTemporaryDirectory() environment:env logPath:log];
}

int main(void) { @autoreleasepool {
    NSString *fake = [NSProcessInfo processInfo].environment[@"FAKEDSH"];
    NSString *log = [NSTemporaryDirectory() stringByAppendingFormat:@"hatest-%d.log", getpid()];
    HA_ASSERT(fake.length && [[NSFileManager defaultManager] isExecutableFileAtPath:fake], "FAKEDSH env must point to built fakedsh");

    // argumentsForProfile
    HA_ASSERT([[HAServer argumentsForProfile:@"web" port:3080] isEqual:(@[@"web", @"--port", @"3080"])], "web args");
    HA_ASSERT([[HAServer argumentsForProfile:@"lab" port:3099] isEqual:(@[@"--profile", @"lab", @"--port", @"3099"])], "custom profile args");

    // 1. Cold start: spawn, ready, stop → no process left
    Recorder *r = [Recorder new];
    HAServer *s = make(fake, 3391, nil, log); s.delegate = r; [s start];
    HA_ASSERT(HAWaitUntil(10, ^{ return (BOOL)(r.ready == 1); }), "cold start became ready");
    HA_ASSERT(s.mode == HAServerModeSpawned, "mode spawned");
    HA_ASSERT([HAServer probeURL:s.baseURL timeout:2], "probe 200");
    pid_t pid = s.childPID; HA_ASSERT(alive(pid), "child alive");
    HA_ASSERT([s stopSynchronously:5], "stopped gracefully");
    HA_ASSERT(!alive(pid), "child gone after stop");
    HA_ASSERT(![HAServer probeURL:s.baseURL timeout:1], "port closed after stop");
    HA_ASSERT([[s logTail:50] containsString:@"fakedsh: listening"], "log captured child stderr");

    // 2. Attach: pre-started server is used and never killed
    NSTask *pre = [NSTask new]; pre.executableURL = [NSURL fileURLWithPath:fake]; pre.arguments = @[@"web", @"--port", @"3392"];
    pre.standardError = [NSFileHandle fileHandleWithNullDevice]; [pre launchAndReturnError:nil];
    HA_ASSERT(HAWaitUntil(5, ^{ return [HAServer probeURL:[NSURL URLWithString:@"http://127.0.0.1:3392/"] timeout:1]; }), "pre-started listening");
    r = [Recorder new]; s = make(fake, 3392, nil, log); s.delegate = r; [s start];
    HA_ASSERT(HAWaitUntil(10, ^{ return (BOOL)(r.ready == 1); }), "attach became ready");
    HA_ASSERT(s.mode == HAServerModeAttached, "mode attached");
    HA_ASSERT([s stopSynchronously:2], "stop is a no-op when attached");
    HA_ASSERT(pre.isRunning, "attached server still running");
    [pre terminate]; [pre waitUntilExit];

    // 3. Escalation: child ignores SIGTERM and has its own child → both killed, no orphans
    r = [Recorder new]; s = make(fake, 3393, @{@"FAKEDSH_IGNORE_TERM": @"1", @"FAKEDSH_SPAWN_CHILD": @"1"}, log); s.delegate = r; [s start];
    HA_ASSERT(HAWaitUntil(10, ^{ return (BOOL)(r.ready == 1); }), "stubborn child ready");
    pid = s.childPID; pid_t grandchild = childOf(pid);
    HA_ASSERT(grandchild > 0 && alive(grandchild), "grandchild exists (pid %d)", grandchild);
    NSDate *t0 = [NSDate date];
    HA_ASSERT([s stopSynchronously:1.0], "escalated stop returned");
    HA_ASSERT([[NSDate date] timeIntervalSinceDate:t0] < 4, "escalation bounded (~1s grace)");
    HA_ASSERT(!alive(pid), "stubborn child killed");
    HA_ASSERT(HAWaitUntil(3, ^{ return (BOOL)!alive(grandchild); }), "grandchild killed with the group");

    // 4. Crash policy: dies once → auto restart; dies again within 60s → give up
    r = [Recorder new]; s = make(fake, 3394, @{@"FAKEDSH_EXIT_AFTER": @"1"}, log); s.delegate = r; [s start];
    HA_ASSERT(HAWaitUntil(10, ^{ return (BOOL)(r.ready >= 1); }), "crashy child ready once");
    HA_ASSERT(HAWaitUntil(15, ^{ return (BOOL)(r.restarted == 1); }), "one auto restart");
    HA_ASSERT(HAWaitUntil(15, ^{ return (BOOL)(r.gaveUp == 1); }), "gave up on second crash");
    HA_ASSERT(r.lastReason.length > 0, "give-up reason includes log tail");
    [s stopSynchronously:2];

    // 5. Never becomes ready → didFailToStart with reason
    r = [Recorder new]; s = [[HAServer alloc] initWithDshPath:@"/usr/bin/false" port:3395 profile:@"web" workspace:NSTemporaryDirectory()
        environment:[NSProcessInfo processInfo].environment logPath:log]; s.delegate = r; [s start];
    HA_ASSERT(HAWaitUntil(10, ^{ return (BOOL)(r.failed == 1); }), "exiting child reports failure quickly");
    HA_ASSERT(r.lastReason.length > 0, "failure has a reason");

    [[NSFileManager defaultManager] removeItemAtPath:log error:nil];
    HA_DONE();
} }
