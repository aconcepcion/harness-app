#import "HATest.h"
#import "HAUpdater.h"
#import <sys/stat.h>

int main(void) { @autoreleasepool {
    HA_ASSERT(HACompareVersions(@"0.1.0-rc.6", @"0.1.0-rc.7") == NSOrderedAscending, "rc.6 < rc.7");
    HA_ASSERT(HACompareVersions(@"0.1.0-rc.10", @"0.1.0-rc.9") == NSOrderedDescending, "rc.10 > rc.9 (numeric identifiers)");
    HA_ASSERT(HACompareVersions(@"0.1.0-rc.9", @"0.1.0") == NSOrderedAscending, "prerelease < release");
    HA_ASSERT(HACompareVersions(@"0.1.0", @"0.2.0") == NSOrderedAscending, "minor bump");
    HA_ASSERT(HACompareVersions(@"1.0.0", @"1.0.0") == NSOrderedSame, "equal");
    HA_ASSERT(HACompareVersions(@"v3.0.0", @"3.0.0") == NSOrderedSame, "leading v ignored");
    HA_ASSERT(HACompareVersions(@"3.0.0", @"3.0.1") == NSOrderedAscending, "patch bump");
    HA_ASSERT(HACompareVersions(@"0.1.0-alpha", @"0.1.0-rc.1") == NSOrderedAscending, "alpha < rc (string identifiers)");
    HA_ASSERT(HACompareVersions(@"0.1.0-rc", @"0.1.0-rc.1") == NSOrderedAscending, "shorter prerelease is lower");
    HA_EQ_STR(HAShellQuote(@"it's"), @"'it'\\''s'");
    HA_EQ_STR(HAAppleScriptQuote(@"say \"hi\" \\ there"), @"say \\\"hi\\\" \\\\ there");
    HA_ASSERT([[HAUpdater installCommand] hasPrefix:@"npm install -g --allow-scripts="], "install command exposed");

    // checkDshLatest uses `npm view`; with a fake npm on PATH we control the answer.
    NSString *dir = [NSTemporaryDirectory() stringByAppendingFormat:@"hanpm-%d", getpid()];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *fakeNpm = [dir stringByAppendingPathComponent:@"npm"];
    [@"#!/bin/sh\necho 9.9.9\n" writeToFile:fakeNpm atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod(fakeNpm.fileSystemRepresentation, 0755);
    NSDictionary *env = @{@"PATH": [dir stringByAppendingString:@":/usr/bin:/bin"]};
    HAUpdater *u = [[HAUpdater alloc] initWithEnvironment:env installedDshVersion:@"0.1.0-rc.6" appVersion:@"3.0.0"];
    __block NSString *latest = nil; __block BOOL newer = NO; __block BOOL done = NO;
    [u checkDshLatest:^(NSString *l, BOOL n) { latest = l; newer = n; done = YES; }];
    HA_ASSERT(HAWaitUntil(10, ^{ return done; }), "dsh check completed");
    HA_EQ_STR(latest ?: @"", @"9.9.9"); HA_ASSERT(newer, "9.9.9 is newer than rc.6");

    // No npm on PATH → nil, not newer, no crash
    u = [[HAUpdater alloc] initWithEnvironment:@{@"PATH": @"/nonexistent"} installedDshVersion:@"0.1.0-rc.6" appVersion:@"3.0.0"];
    done = NO; [u checkDshLatest:^(NSString *l, BOOL n) { latest = l; newer = n; done = YES; }];
    HA_ASSERT(HAWaitUntil(10, ^{ return done; }), "dsh check without npm completes");
    HA_ASSERT(latest == nil && !newer, "no npm → nil/no");

    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
    HA_DONE();
} }
