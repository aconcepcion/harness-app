#import "HAServer.h"
#import <fcntl.h>
#import <signal.h>
#import <spawn.h>
#import <sys/wait.h>

static const NSTimeInterval kReadyBudget = 45.0, kPollInterval = 0.4, kRestartWindow = 60.0;

@interface HAServer ()
@property (readwrite) HAServerMode mode;
@property (readwrite) pid_t childPID;
@property NSString *dshPath;
@property NSDictionary<NSString *, NSString *> *environment;
@property dispatch_queue_t queue;
@property (nullable) dispatch_source_t exitSource;
@property BOOL stopping, everReady;
@property NSDate *lastRestart;   // nil until first auto-restart
@property int generation;
- (BOOL)reapIfExited:(pid_t)pid generation:(int)gen;
@end

@implementation HAServer

- (instancetype)initWithDshPath:(NSString *)dshPath port:(uint16_t)port profile:(NSString *)profile
                      workspace:(NSString *)workspace environment:(NSDictionary *)environment logPath:(NSString *)logPath {
    if ((self = [super init])) {
        _dshPath = dshPath; _port = port; _profile = profile; _workspace = workspace; _environment = environment; _logPath = logPath;
        _baseURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u/", port]];
        _queue = dispatch_queue_create("harness.server", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

+ (NSArray<NSString *> *)argumentsForProfile:(NSString *)profile port:(uint16_t)port {
    NSString *p = [NSString stringWithFormat:@"%u", port];
    if ([profile isEqualToString:@"web"]) return @[@"web", @"--port", p];
    return @[@"--profile", profile, @"--port", p];
}

+ (BOOL)probeURL:(NSURL *)url timeout:(NSTimeInterval)timeout {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:timeout];
    __block BOOL ok = NO; dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = timeout; cfg.timeoutIntervalForResource = timeout;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    [[session dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *resp, NSError *err) {
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        ok = (err == nil && code > 0 && code < 400);
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)((timeout + 1) * NSEC_PER_SEC)));
    [session finishTasksAndInvalidate];
    return ok;
}
- (BOOL)probeReady { return [HAServer probeURL:self.baseURL timeout:1.0]; }

- (void)log:(NSString *)line {
    NSString *s = [NSString stringWithFormat:@"[harness-app %@] %@\n", [NSDate date], line];
    int fd = open(self.logPath.fileSystemRepresentation, O_WRONLY | O_APPEND | O_CREAT, 0644);
    if (fd >= 0) { (void)!write(fd, s.UTF8String, strlen(s.UTF8String)); close(fd); }
}
- (NSString *)logTail:(NSUInteger)lines {
    NSString *all = [NSString stringWithContentsOfFile:self.logPath encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSArray *arr = [all componentsSeparatedByString:@"\n"];
    NSUInteger n = MIN(lines, arr.count);
    return [[arr subarrayWithRange:NSMakeRange(arr.count - n, n)] componentsJoinedByString:@"\n"];
}

- (void)notify:(void (^)(id<HAServerDelegate>))block {
    dispatch_async(dispatch_get_main_queue(), ^{ id<HAServerDelegate> d = self.delegate; if (d) block(d); });
}

- (void)start {
    dispatch_async(self.queue, ^{
        self.stopping = NO;
        if ([self probeReady]) {
            self.mode = HAServerModeAttached; self.everReady = YES;
            [self log:[NSString stringWithFormat:@"attached to existing server on port %u", self.port]];
            [self notify:^(id<HAServerDelegate> d) { [d serverDidBecomeReady:self]; }];
            return;
        }
        [self spawnAndWait];
    });
}

// Runs on self.queue.
- (void)spawnAndWait {
    int gen = ++self.generation;
    pid_t pid = [self spawnChild];
    if (pid <= 0) { [self notify:^(id<HAServerDelegate> d) { [d server:self didFailToStart:@"Could not launch dsh (posix_spawn failed). Check the log."]; }]; return; }
    self.childPID = pid; self.mode = HAServerModeSpawned;
    [self log:[NSString stringWithFormat:@"spawned dsh pid %d: %@ %@ (cwd %@)", pid, self.dshPath,
               [[HAServer argumentsForProfile:self.profile port:self.port] componentsJoinedByString:@" "], self.workspace]];
    [self watchExitOfPID:pid generation:gen];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:kReadyBudget];
    while (!self.stopping && self.childPID == pid && [deadline timeIntervalSinceNow] > 0) {
        if ([self reapIfExited:pid generation:gen]) return;
        if ([self probeReady]) {
            self.everReady = YES;
            [self log:@"server ready"];
            [self notify:^(id<HAServerDelegate> d) { [d serverDidBecomeReady:self]; }];
            return;
        }
        [NSThread sleepForTimeInterval:kPollInterval];
    }
    if (self.stopping || self.childPID != pid) return; // exit handler already reported
    [self log:@"server did not become ready in time; stopping it"];
    [self stopSynchronously:3];
    [self notify:^(id<HAServerDelegate> d) { [d server:self didFailToStart:[NSString stringWithFormat:@"dsh did not answer on port %u within %.0f seconds.\n\n%@", self.port, kReadyBudget, [self logTail:20]]]; }];
}

- (pid_t)spawnChild {
    NSArray *args = [@[self.dshPath] arrayByAddingObjectsFromArray:[HAServer argumentsForProfile:self.profile port:self.port]];
    NSMutableArray<NSString *> *envs = [NSMutableArray array];
    [self.environment enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) { [envs addObject:[NSString stringWithFormat:@"%@=%@", k, v]]; }];
    char **argv = calloc(args.count + 1, sizeof(char *)); for (NSUInteger i = 0; i < args.count; i++) argv[i] = strdup([args[i] UTF8String]);
    char **envp = calloc(envs.count + 1, sizeof(char *)); for (NSUInteger i = 0; i < envs.count; i++) envp[i] = strdup([envs[i] UTF8String]);
    posix_spawnattr_t attr; posix_spawnattr_init(&attr);
    posix_spawnattr_setpgroup(&attr, 0);                          // new process group, pgid == child pid
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    posix_spawn_file_actions_t fa; posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&fa, 1, self.logPath.fileSystemRepresentation, O_WRONLY | O_APPEND | O_CREAT, 0644);
    posix_spawn_file_actions_addopen(&fa, 2, self.logPath.fileSystemRepresentation, O_WRONLY | O_APPEND | O_CREAT, 0644);
    posix_spawn_file_actions_addchdir_np(&fa, self.workspace.fileSystemRepresentation);
    pid_t pid = 0;
    int rc = posix_spawn(&pid, self.dshPath.fileSystemRepresentation, &fa, &attr, argv, envp);
    posix_spawn_file_actions_destroy(&fa); posix_spawnattr_destroy(&attr);
    for (char **p = argv; *p; p++) free(*p); free(argv); for (char **p = envp; *p; p++) free(*p); free(envp);
    if (rc != 0) { [self log:[NSString stringWithFormat:@"posix_spawn failed: %s", strerror(rc)]]; return -1; }
    return pid;
}

- (void)handleExitOfPID:(pid_t)pid status:(int)status generation:(int)gen {
    if (self.childPID != pid || self.generation != gen) return;
    self.childPID = 0;
    if (self.exitSource) { dispatch_source_cancel(self.exitSource); self.exitSource = nil; }
    NSString *how = WIFSIGNALED(status) ? [NSString stringWithFormat:@"signal %d", WTERMSIG(status)] : [NSString stringWithFormat:@"status %d", WEXITSTATUS(status)];
    [self log:[NSString stringWithFormat:@"dsh pid %d exited (%@)", pid, how]];
    if (self.stopping) return;
    if (!self.everReady) {
        [self notify:^(id<HAServerDelegate> d) { [d server:self didFailToStart:[NSString stringWithFormat:@"dsh exited before it was ready (%@).\\n\\n%@", how, [self logTail:20]]]; }];
        return;
    }
    BOOL recentlyRestarted = self.lastRestart && [[NSDate date] timeIntervalSinceDate:self.lastRestart] < kRestartWindow;
    if (recentlyRestarted) {
        [self log:@"second failure within 60s — giving up"];
        [self notify:^(id<HAServerDelegate> d) { [d server:self didGiveUp:[NSString stringWithFormat:@"dsh keeps exiting (%@).\\n\\n%@", how, [self logTail:30]]]; }];
        return;
    }
    self.lastRestart = [NSDate date];
    [self log:@"unexpected exit — restarting once"];
    [self notify:^(id<HAServerDelegate> d) { [d serverDidRestart:self]; }];
    [self spawnAndWait];
}

// Returns YES if the child has already exited (and handles it).
- (BOOL)reapIfExited:(pid_t)pid generation:(int)gen {
    int status = 0;
    pid_t r = waitpid(pid, &status, WNOHANG);
    if (r == pid) { [self handleExitOfPID:pid status:status generation:gen]; return YES; }
    return NO;
}

- (void)watchExitOfPID:(pid_t)pid generation:(int)gen {
    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, pid, DISPATCH_PROC_EXIT, self.queue);
    self.exitSource = src;
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(src, ^{
        typeof(self) self = weakSelf; if (!self) return;
        [self reapIfExited:pid generation:gen];
    });
    dispatch_resume(src);
    // The child may have died before the source was armed (kqueue will not fire for a zombie).
    [self reapIfExited:pid generation:gen];
}


- (void)restart {
    dispatch_async(self.queue, ^{
        if (self.mode == HAServerModeAttached) {
            BOOL ok = [self probeReady];
            [self notify:^(id<HAServerDelegate> d) { if (ok) [d serverDidBecomeReady:self]; else [d server:self didFailToStart:@"The attached server is no longer answering."]; }];
            return;
        }
        [self stopSynchronously:5];
        self.stopping = NO; self.everReady = NO; self.lastRestart = nil;
        [self spawnAndWait];
    });
}

- (BOOL)stopSynchronously:(NSTimeInterval)grace {
    if (self.mode != HAServerModeSpawned) return YES;
    pid_t pid = self.childPID;
    self.stopping = YES;
    if (pid <= 0) return YES;
    [self log:[NSString stringWithFormat:@"stopping dsh pid %d (SIGTERM group, %.0fs grace)", pid, grace]];
    killpg(pid, SIGTERM);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:grace];
    while ([deadline timeIntervalSinceNow] > 0) {
        int status = 0; pid_t r = waitpid(pid, &status, WNOHANG);
        if (r == pid || (r < 0 && errno == ECHILD)) break;
        if (kill(pid, 0) != 0) break;
        [NSThread sleepForTimeInterval:0.1];
    }
    if (kill(pid, 0) == 0) [self log:@"grace expired — SIGKILL group"];
    killpg(pid, SIGKILL); // also sweeps lingering group members (grandchildren) after the leader is gone
    int status = 0; for (int i = 0; i < 20 && waitpid(pid, &status, WNOHANG) == 0; i++) [NSThread sleepForTimeInterval:0.05];
    if (self.exitSource) { dispatch_source_cancel(self.exitSource); self.exitSource = nil; }
    self.childPID = 0;
    return kill(pid, 0) != 0;
}
@end
