#import "HATest.h"
#import "HAEnvironment.h"
#import <sys/stat.h>

static NSString *tmpdir(void) {
    NSString *d = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"hatest-%d-%u", getpid(), arc4random()]];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}
static void touch(NSString *p, BOOL exec) {
    [[NSFileManager defaultManager] createDirectoryAtPath:[p stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] createFileAtPath:p contents:[NSData data]
        attributes:@{NSFilePosixPermissions: @(exec ? 0755 : 0644)}];
}

int main(void) { @autoreleasepool {
    // Node version rule: ^22.19.0 || >=24.0.0
    HA_ASSERT(HANodeVersionIsSupported(@"v26.7.0"), "26 supported");
    HA_ASSERT(HANodeVersionIsSupported(@"24.0.0"), "24.0.0 supported");
    HA_ASSERT(HANodeVersionIsSupported(@"22.19.0"), "22.19.0 supported");
    HA_ASSERT(HANodeVersionIsSupported(@"22.20.1"), "22.20.1 supported");
    HA_ASSERT(!HANodeVersionIsSupported(@"22.18.9"), "22.18 unsupported");
    HA_ASSERT(!HANodeVersionIsSupported(@"v23.11.0"), "23.x unsupported (the gap)");
    HA_ASSERT(!HANodeVersionIsSupported(@"20.11.0"), "20 unsupported");
    HA_ASSERT(!HANodeVersionIsSupported(@"garbage"), "garbage unsupported");

    // Env block parsing (NUL-separated, markers around it)
    NSMutableData *blob = [NSMutableData data];
    [blob appendData:[@"junk from rc file\n__HA_ENV_START__\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [blob appendData:[@"PATH=/a:/b\0HOME=/Users/x\0MULTI=line1\nline2\0" dataUsingEncoding:NSUTF8StringEncoding]];
    [blob appendData:[@"__HA_ENV_END__\n" dataUsingEncoding:NSUTF8StringEncoding]];
    NSDictionary *env = HAParseNullSeparatedEnvironment(blob);
    HA_EQ_STR(env[@"PATH"], @"/a:/b");
    HA_EQ_STR(env[@"HOME"], @"/Users/x");
    HA_EQ_STR(env[@"MULTI"], @"line1\nline2");
    HA_ASSERT(env.count == 3, "exactly 3 vars, got %lu", (unsigned long)env.count);
    HA_ASSERT(HAParseNullSeparatedEnvironment([NSData data]).count == 0, "empty → empty");

    // Executable lookup honors PATH order and executable bit
    NSString *d = tmpdir();
    touch([d stringByAppendingPathComponent:@"one/dsh"], NO);
    touch([d stringByAppendingPathComponent:@"two/dsh"], YES);
    NSString *path = [NSString stringWithFormat:@"%@/one:%@/two", d, d];
    HA_EQ_STR(HAFindExecutable(@"dsh", path), [d stringByAppendingPathComponent:@"two/dsh"]);
    HA_ASSERT(HAFindExecutable(@"nope", path) == nil, "missing → nil");
    HA_ASSERT(HAFindExecutable(@"dsh", nil) == nil, "nil PATH → nil");

    // Package dir from (symlinked) bin: <root>/bin/dsh -> ../lib/node_modules/@deepseek-ai/dsh/lib/bin.js
    NSString *pkg = [d stringByAppendingPathComponent:@"lib/node_modules/@deepseek-ai/dsh"];
    touch([pkg stringByAppendingPathComponent:@"lib/bin.js"], YES);
    [@"{\"name\":\"@deepseek-ai/dsh\",\"version\":\"0.1.0-rc.6\"}" writeToFile:[pkg stringByAppendingPathComponent:@"package.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:[d stringByAppendingPathComponent:@"bin"] withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] createSymbolicLinkAtPath:[d stringByAppendingPathComponent:@"bin/dsh"]
        withDestinationPath:@"../lib/node_modules/@deepseek-ai/dsh/lib/bin.js" error:nil];
    NSString *found = HADshPackageDirForBinary([d stringByAppendingPathComponent:@"bin/dsh"]);
    HA_ASSERT([[found stringByResolvingSymlinksInPath] isEqualToString:[pkg stringByResolvingSymlinksInPath]], "pkg dir resolved, got %s", [found UTF8String]);
    HA_ASSERT(HADshPackageDirForBinary(@"/nonexistent/dsh") == nil, "nonexistent → nil");

    // node-pty state
    HA_ASSERT(HANodePtyStateForPackageDir(pkg, @"arm64") == HANodePtyUnknown, "no node-pty dir → unknown");
    NSString *pre = [pkg stringByAppendingPathComponent:@"node_modules/node-pty/prebuilds/win32-arm64"];
    touch([pre stringByAppendingPathComponent:@"pty.node"], NO);
    HA_ASSERT(HANodePtyStateForPackageDir(pkg, @"arm64") == HANodePtyBroken, "only win32 prebuild → broken");
    NSString *dar = [pkg stringByAppendingPathComponent:@"node_modules/node-pty/prebuilds/darwin-arm64"];
    touch([dar stringByAppendingPathComponent:@"pty.node"], NO);
    touch([dar stringByAppendingPathComponent:@"spawn-helper"], NO);
    HA_ASSERT(HANodePtyStateForPackageDir(pkg, @"arm64") == HANodePtyBroken, "spawn-helper not executable → broken");
    chmod([[dar stringByAppendingPathComponent:@"spawn-helper"] fileSystemRepresentation], 0755);
    HA_ASSERT(HANodePtyStateForPackageDir(pkg, @"arm64") == HANodePtyIntact, "darwin prebuild complete → intact");
    HA_ASSERT(HANodePtyStateForPackageDir(pkg, @"x64") == HANodePtyBroken, "other arch missing → broken");

    // Command runner + timeout
    int st = -1;
    NSString *out = HARunCommandOutput(@"/bin/echo", @[@"hi"], nil, 5, &st);
    HA_EQ_STR([out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet], @"hi");
    HA_ASSERT(st == 0, "echo exit 0");
    NSDate *t0 = [NSDate date];
    out = HARunCommandOutput(@"/bin/sleep", @[@"5"], nil, 0.5, &st);
    HA_ASSERT(out == nil && [[NSDate date] timeIntervalSinceDate:t0] < 3, "timeout kills the task");

    HA_ASSERT([HACurrentNodeArch() isEqualToString:@"arm64"] || [HACurrentNodeArch() isEqualToString:@"x64"], "arch string");
    HA_ASSERT([HADshInstallCommand containsString:@"--allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs"], "install command carries allow-scripts");

    // Real capture smoke (this machine): must not throw, PATH non-empty
    NSDictionary *real = HACaptureLoginShellEnvironment(8);
    HA_ASSERT([real[@"PATH"] length] > 0, "captured PATH");
    [[NSFileManager defaultManager] removeItemAtPath:d error:nil];
    HA_DONE();
} }
