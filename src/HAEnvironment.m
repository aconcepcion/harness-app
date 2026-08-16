#import "HAEnvironment.h"

NSString *const HADshInstallCommand =
    @"npm install -g --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs @deepseek-ai/dsh@latest";

NSString *HARunCommandOutput(NSString *path, NSArray<NSString *> *args, NSDictionary *env,
                             NSTimeInterval timeout, int *status) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = args;
    if (env) task.environment = env;
    NSPipe *out = [NSPipe pipe];
    task.standardOutput = out;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];
    NSError *err = nil;
    if (![task launchAndReturnError:&err]) { if (status) *status = -1; return nil; }
    __block BOOL timedOut = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (task.isRunning) { timedOut = YES; [task terminate]; kill(task.processIdentifier, SIGKILL); }
    });
    NSData *data = [[out fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    if (status) *status = task.terminationStatus;
    if (timedOut) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

NSDictionary<NSString *, NSString *> *HAParseNullSeparatedEnvironment(NSData *data) {
    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    if (data.length == 0) return env;
    NSData *start = [@"__HA_ENV_START__\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *end = [@"__HA_ENV_END__" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange s = [data rangeOfData:start options:0 range:NSMakeRange(0, data.length)];
    NSUInteger from = (s.location == NSNotFound) ? 0 : NSMaxRange(s);
    NSRange e = [data rangeOfData:end options:0 range:NSMakeRange(from, data.length - from)];
    NSUInteger to = (e.location == NSNotFound) ? data.length : e.location;
    NSData *body = [data subdataWithRange:NSMakeRange(from, to - from)];
    const char *bytes = body.bytes; NSUInteger len = body.length, i = 0;
    while (i < len) {
        NSUInteger j = i; while (j < len && bytes[j] != '\0') j++;
        NSString *kv = [[NSString alloc] initWithBytes:bytes + i length:j - i encoding:NSUTF8StringEncoding];
        NSRange eq = [kv rangeOfString:@"="];
        if (eq.location != NSNotFound && eq.location > 0)
            env[[kv substringToIndex:eq.location]] = [kv substringFromIndex:eq.location + 1];
        i = j + 1;
    }
    return env;
}

NSDictionary<NSString *, NSString *> *HACaptureLoginShellEnvironment(NSTimeInterval timeout) {
    NSDictionary *procEnv = [NSProcessInfo processInfo].environment;
    NSString *shell = procEnv[@"SHELL"] ?: @"/bin/zsh";
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:shell]) shell = @"/bin/zsh";
    NSString *script = @"echo __HA_ENV_START__; env -0; echo __HA_ENV_END__";
    NSMutableDictionary *childEnv = [procEnv mutableCopy];
    childEnv[@"HA_ENV_CAPTURE"] = @"1"; // rc files may test this to skip slow/interactive work
    for (NSArray *flags in @[@[@"-ilc"], @[@"-lc"]]) {
        NSTask *task = [NSTask new];
        task.executableURL = [NSURL fileURLWithPath:shell];
        task.arguments = [flags arrayByAddingObject:script];
        task.environment = childEnv;
        task.standardInput = [NSFileHandle fileHandleWithNullDevice];
        task.standardError = [NSFileHandle fileHandleWithNullDevice];
        NSPipe *out = [NSPipe pipe]; task.standardOutput = out;
        NSError *err = nil;
        if (![task launchAndReturnError:&err]) continue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ if (task.isRunning) kill(task.processIdentifier, SIGKILL); });
        NSData *data = [[out fileHandleForReading] readDataToEndOfFile];
        [task waitUntilExit];
        NSDictionary *env = HAParseNullSeparatedEnvironment(data);
        if ([env[@"PATH"] length] > 0) return env;
    }
    return procEnv;
}

NSString *HAFindExecutable(NSString *name, NSString *pathValue) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in [pathValue ?: @"" componentsSeparatedByString:@":"]) {
        if (dir.length == 0) continue;
        NSString *p = [dir stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:p isDirectory:&isDir] && !isDir && [fm isExecutableFileAtPath:p]) return p;
    }
    return nil;
}

BOOL HANodeVersionIsSupported(NSString *version) {
    NSString *v = [version hasPrefix:@"v"] ? [version substringFromIndex:1] : version;
    NSArray *parts = [[v stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsSeparatedByString:@"."];
    if (parts.count < 2) return NO;
    NSScanner *sc = [NSScanner scannerWithString:parts[0]]; NSInteger major = -1, minor = -1;
    if (![sc scanInteger:&major] || !sc.isAtEnd) return NO;
    sc = [NSScanner scannerWithString:parts[1]]; if (![sc scanInteger:&minor]) return NO;
    return (major == 22 && minor >= 19) || major >= 24;
}

NSString *HADshPackageDirForBinary(NSString *binPath) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:binPath]) return nil;
    NSString *real = [binPath stringByResolvingSymlinksInPath];
    NSString *dir = [real stringByDeletingLastPathComponent];
    for (int i = 0; i < 6 && dir.length > 1; i++) {
        NSString *pj = [dir stringByAppendingPathComponent:@"package.json"];
        NSData *d = [NSData dataWithContentsOfFile:pj];
        if (d) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            if ([json[@"name"] isEqual:@"@deepseek-ai/dsh"]) return dir;
        }
        dir = [dir stringByDeletingLastPathComponent];
    }
    return nil;
}

HANodePtyState HANodePtyStateForPackageDir(NSString *pkgDir, NSString *arch) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *pty = [pkgDir stringByAppendingPathComponent:@"node_modules/node-pty"];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:pty isDirectory:&isDir] || !isDir) return HANodePtyUnknown;
    if ([fm fileExistsAtPath:[pty stringByAppendingPathComponent:@"build/Release/pty.node"]]) return HANodePtyIntact;
    NSString *pre = [pty stringByAppendingFormat:@"/prebuilds/darwin-%@", arch];
    NSString *helper = [pre stringByAppendingPathComponent:@"spawn-helper"];
    if ([fm fileExistsAtPath:[pre stringByAppendingPathComponent:@"pty.node"]] &&
        [fm fileExistsAtPath:helper] && [fm isExecutableFileAtPath:helper]) return HANodePtyIntact;
    return HANodePtyBroken;
}

NSString *HACurrentNodeArch(void) {
#if defined(__arm64__)
    return @"arm64";
#else
    return @"x64";
#endif
}

@interface HAEnvironment ()
@property (readwrite) NSDictionary<NSString *, NSString *> *shellEnvironment;
@property (readwrite, nullable) NSString *dshPath, *dshVersion, *dshPackageDir, *nodePath, *nodeVersion;
@property (readwrite) BOOL nodeSupported;
@property (readwrite) HANodePtyState nodePtyState;
@end

@implementation HAEnvironment
+ (instancetype)capture:(NSString *)preferredDshPath {
    HAEnvironment *e = [HAEnvironment new];
    e.shellEnvironment = HACaptureLoginShellEnvironment(8);
    NSString *path = e.shellEnvironment[@"PATH"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (preferredDshPath.length && [fm isExecutableFileAtPath:preferredDshPath]) e.dshPath = preferredDshPath;
    else e.dshPath = HAFindExecutable(@"dsh", path);
    e.nodePath = HAFindExecutable(@"node", path);
    if (e.nodePath) {
        NSString *v = HARunCommandOutput(e.nodePath, @[@"--version"], e.shellEnvironment, 5, NULL);
        v = [v stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (v.length) { e.nodeVersion = [v hasPrefix:@"v"] ? [v substringFromIndex:1] : v; e.nodeSupported = HANodeVersionIsSupported(v); }
    }
    if (e.dshPath) {
        NSString *v = HARunCommandOutput(e.dshPath, @[@"--version"], e.shellEnvironment, 8, NULL);
        v = [v stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (v.length) e.dshVersion = v;
        e.dshPackageDir = HADshPackageDirForBinary(e.dshPath);
        e.nodePtyState = e.dshPackageDir ? HANodePtyStateForPackageDir(e.dshPackageDir, HACurrentNodeArch()) : HANodePtyUnknown;
    }
    return e;
}
- (NSString *)report {
    NSString *pty = @[@"unknown", @"intact", @"BROKEN"][self.nodePtyState];
    return [NSString stringWithFormat:
        @"shell PATH: %@\ndsh: %@\ndsh version: %@\ndsh package: %@\nnode: %@\nnode version: %@ (%@)\nnode-pty: %@\nDSH_HOME: %@\n",
        self.shellEnvironment[@"PATH"] ?: @"", self.dshPath ?: @"not found", self.dshVersion ?: @"?",
        self.dshPackageDir ?: @"?", self.nodePath ?: @"not found", self.nodeVersion ?: @"?",
        self.nodeSupported ? @"supported" : @"UNSUPPORTED", pty, self.shellEnvironment[@"DSH_HOME"] ?: @"(default ~/.dsh)"];
}
@end
