#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "HAConfig.h"
#import "HAEnvironment.h"
#import "HAServer.h"
#import "HAUpdater.h"
#import "HAPreferencesWindow.h"
#import "HASleepGuard.h"
#import "HAInstaller.h"
#import <sys/stat.h>

static NSMenuItem *item(NSString *title, SEL action, NSString *key);

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, WKUIDelegate, WKNavigationDelegate, HAServerDelegate, NSMenuDelegate>
@property (strong) NSWindow *window;
@property (strong) WKWebView *webView;
@property (strong) HAEnvironment *env;
@property (strong) HAServer *server;
@property (strong) HAUpdater *updater;
@property (strong) HASleepGuard *sleepGuard;
@property (copy) NSString *launchWorkspace;          // Dock drop / open-with, overrides preference for this launch
@property (strong) NSMutableDictionary<NSString *, NSString *> *notices;
@property (strong) NSMenu *profileMenu, *presetsMenu, *skillsMenu;
@property BOOL installing;
@property (strong) NSWindowController *preferencesController;   // Task 6
@property BOOL updateChecksRan;
@end

@implementation AppDelegate

#pragma mark - Window & placeholder

- (void)buildWindow {
    NSRect rect = NSMakeRect(0, 0, 1280, 860);
    self.window = [[NSWindow alloc] initWithContentRect:rect
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Harness";
    self.window.delegate = self;
    [self.window setFrameAutosaveName:@"HAMainWindow"];
    if (self.window.frame.size.width < 400) { [self.window setContentSize:rect.size]; [self.window center]; }
    WKWebViewConfiguration *cfg = [WKWebViewConfiguration new];
    self.webView = [[WKWebView alloc] initWithFrame:rect configuration:cfg];
    self.webView.UIDelegate = self;
    self.webView.navigationDelegate = self;
    self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.window.contentView = self.webView;
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)showPlaceholder:(NSString *)text {
    NSString *html = [NSString stringWithFormat:
        @"<html><head><meta name=\"color-scheme\" content=\"light dark\"></head>"
        @"<body style=\"display:flex;align-items:center;justify-content:center;height:100vh;margin:0;"
        @"font-family:-apple-system,sans-serif;font-size:1.2em;color:#888\"><div>%@</div></body></html>", text];
    [self.webView loadHTMLString:html baseURL:nil];
}

// Notices are short status lines shown in the window subtitle, keyed so they can be replaced/cleared.
- (void)setNotice:(NSString *)text forKey:(NSString *)key {
    if (!self.notices) self.notices = [NSMutableDictionary dictionary];
    if (text.length) self.notices[key] = text; else [self.notices removeObjectForKey:key];
    NSArray *keys = [self.notices.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *k in keys) [parts addObject:self.notices[k]];
    if (@available(macOS 11.0, *)) self.window.subtitle = [parts componentsJoinedByString:@"  ·  "];
}

// All alerts are window sheets: nothing blocks the run loop, and they never appear behind other apps.
- (void)presentSheetTitle:(NSString *)title detail:(NSString *)detail buttons:(NSArray<NSString *> *)buttons
                  handler:(void (^)(NSInteger index))handler {
    NSAlert *a = [NSAlert new];
    a.messageText = title; a.informativeText = detail ?: @"";
    for (NSString *b in buttons) [a addButtonWithTitle:b];
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (handler && r >= NSAlertFirstButtonReturn) handler(r - NSAlertFirstButtonReturn);   // aborted sheets (quit) call no branch
    }];
}

#pragma mark - Startup

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    HARegisterDefaults();
    [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:HAPrefPreventSleep options:0 context:NULL];   // Settings checkbox
    [self buildWindow];
    [self showPlaceholder:@"Starting DeepSeek Harness…"];
    [self bootstrap];
}

- (void)bootstrap {
    NSString *pref = [[NSUserDefaults standardUserDefaults] stringForKey:HAPrefDshPath];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        HAEnvironment *env = [HAEnvironment capture:pref.length ? pref : nil];
        dispatch_async(dispatch_get_main_queue(), ^{ self.env = env; [self continueWithEnvironment]; });
    });
}

- (void)continueWithEnvironment {
    if (!self.env.dshPath) { [self presentInstallGuidance]; return; }
    if (self.env.nodePtyState == HANodePtyBroken)
        [self setNotice:@"dsh shell tools look broken — dsh ▸ Repair Shell Tools…" forKey:@"pty"];
    self.updater = [[HAUpdater alloc] initWithEnvironment:self.env.shellEnvironment installedDshVersion:self.env.dshVersion appVersion:HAAppVersion];
    [self startServer];
}

- (NSString *)effectiveWorkspace {
    NSString *ws = self.launchWorkspace ?: [[NSUserDefaults standardUserDefaults] stringForKey:HAPrefWorkspace];
    BOOL isDir = NO;
    if (!ws.length || ![[NSFileManager defaultManager] fileExistsAtPath:ws isDirectory:&isDir] || !isDir) ws = NSHomeDirectory();
    return ws;
}

- (void)startServer {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSInteger port = [d integerForKey:HAPrefPort]; if (port <= 0 || port > 65535) port = HADefaultPort;
    NSString *profile = [d stringForKey:HAPrefProfile]; if (!profile.length) profile = HADefaultProfile;
    self.server = [[HAServer alloc] initWithDshPath:self.env.dshPath port:(uint16_t)port profile:profile
                                          workspace:[self effectiveWorkspace] environment:self.env.shellEnvironment logPath:HALogPath()];
    self.server.delegate = self;
    [self showPlaceholder:@"Starting DeepSeek Harness…"];
    [self.server start];
}

// Stop the current server (if we own it) and start a new one with different settings (profile switch, Dock drop, prefs).
- (void)replaceServerWithProfile:(NSString *)profile workspace:(NSString *)workspace {
    if (profile) [[NSUserDefaults standardUserDefaults] setObject:profile forKey:HAPrefProfile];
    if (workspace) self.launchWorkspace = workspace;
    HAServer *old = self.server;
    old.delegate = nil;
    [self.sleepGuard deactivate];
    [self showPlaceholder:@"Restarting dsh…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (old.mode == HAServerModeSpawned) [old stopSynchronously:5];
        dispatch_async(dispatch_get_main_queue(), ^{ [self startServer]; });
    });
}

#pragma mark - First-run guidance (dsh missing / Node wrong)

- (void)presentInstallGuidance {
    NSMutableString *detail = [NSMutableString stringWithString:
        @"Harness runs the DeepSeek Harness (dsh) that you install yourself with npm — nothing is bundled, so you always run the real upstream.\n\n"];
    NSString *cmd = HADshInstallCommand;
    if (!self.env.nodePath) {
        [detail appendString:@"Node.js was not found on your PATH. Install it first (Homebrew: brew install node), then dsh:\n\n"];
        cmd = [@"brew install node && " stringByAppendingString:cmd];
    } else if (!self.env.nodeSupported) {
        [detail appendFormat:@"Node %@ is not supported by dsh (it needs 22.19+ or 24+; 23.x is excluded). Upgrade Node, then install dsh:\n\n", self.env.nodeVersion ?: @"?"];
        cmd = [@"brew install node && " stringByAppendingString:cmd];
    } else {
        [detail appendString:@"Run this in Terminal (the --allow-scripts part is required with npm 11+, or dsh's shell tools come out broken):\n\n"];
    }
    [detail appendString:cmd];
    [self showPlaceholder:@"dsh is not installed yet"];
    [self presentSheetTitle:@"dsh isn't installed (or isn't on your PATH)" detail:detail
                    buttons:@[@"Open Terminal", @"Copy Command", @"Quit"] handler:^(NSInteger i) {
        if (i == 0) {
            NSError *err = nil;
            if (![HAUpdater runInTerminal:cmd error:&err]) { [self presentSheetTitle:@"Could not open Terminal" detail:err.localizedDescription buttons:@[@"Quit"] handler:^(NSInteger j) { [NSApp terminate:nil]; }]; return; }
            [self presentSheetTitle:@"Installing in Terminal…" detail:@"When the install finishes, click Retry." buttons:@[@"Retry", @"Quit"]
                            handler:^(NSInteger j) { if (j == 0) [self bootstrap]; else [NSApp terminate:nil]; }];
        } else if (i == 1) {
            [[NSPasteboard generalPasteboard] clearContents];
            [[NSPasteboard generalPasteboard] setString:cmd forType:NSPasteboardTypeString];
            [self presentSheetTitle:@"Command copied" detail:@"Paste it into Terminal. When the install finishes, click Retry." buttons:@[@"Retry", @"Quit"]
                            handler:^(NSInteger j) { if (j == 0) [self bootstrap]; else [NSApp terminate:nil]; }];
        } else [NSApp terminate:nil];
    }];
}

#pragma mark - HAServerDelegate

- (void)serverDidBecomeReady:(HAServer *)server {
    if (server != self.server) return;
    [self.webView loadRequest:[NSURLRequest requestWithURL:server.baseURL]];
    [self setNotice:nil forKey:@"server"];
    [self applySleepGuard];
    if (!self.updateChecksRan) { self.updateChecksRan = YES; [self runBackgroundUpdateChecks]; }
}
- (void)serverDidRestart:(HAServer *)server {
    if (server != self.server) return;
    [self showPlaceholder:@"dsh exited unexpectedly — restarting…"];
    [self setNotice:@"dsh restarted once" forKey:@"server"];
}
- (void)server:(HAServer *)server didFailToStart:(NSString *)reason {
    if (server != self.server) return;
    [self showPlaceholder:@"dsh could not start"];
    [self presentSheetTitle:@"dsh could not start" detail:reason buttons:@[@"Retry", @"Open Log", @"Quit"] handler:^(NSInteger i) {
        if (i == 0) [self startServer]; else if (i == 1) { [self openLog:nil]; [self server:server didFailToStart:reason]; } else [NSApp terminate:nil];
    }];
}
- (void)server:(HAServer *)server didGiveUp:(NSString *)reason {
    if (server != self.server) return;
    [self showPlaceholder:@"dsh keeps exiting"];
    [self presentSheetTitle:@"dsh keeps exiting" detail:reason buttons:@[@"Restart Server", @"Open Log", @"Quit"] handler:^(NSInteger i) {
        if (i == 0) [self startServer]; else if (i == 1) { [self openLog:nil]; [self server:server didGiveUp:reason]; } else [NSApp terminate:nil];
    }];
}

#pragma mark - Close / quit policy

- (void)windowWillClose:(NSNotification *)note { [NSApp terminate:nil]; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }
- (void)applicationWillTerminate:(NSNotification *)note {
    [self.sleepGuard deactivate];
    [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:HAPrefPreventSleep];
    BOOL keep = [[NSUserDefaults standardUserDefaults] boolForKey:HAPrefKeepServerRunning];
    if (self.server.mode == HAServerModeSpawned && !keep) [self.server stopSynchronously:5];
}

#pragma mark - Navigation guard: only our origin stays in-window

- (BOOL)isLocalURL:(NSURL *)u {
    NSString *h = u.host.lowercaseString;
    return [h isEqualToString:@"127.0.0.1"] || [h isEqualToString:@"localhost"] || [h isEqualToString:@"::1"] || [h isEqualToString:@"[::1]"];
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
        decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *u = action.request.URL;
    BOOL mainFrame = (action.targetFrame == nil) || action.targetFrame.isMainFrame;
    if (!u || !mainFrame || [self isLocalURL:u] || [@[@"about", @"blob", @"data"] containsObject:u.scheme.lowercaseString ?: @""]) { decisionHandler(WKNavigationActionPolicyAllow); return; }
    if ([@[@"http", @"https", @"mailto"] containsObject:u.scheme.lowercaseString ?: @""]) [[NSWorkspace sharedWorkspace] openURL:u];
    decisionHandler(WKNavigationActionPolicyCancel);
}
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    NSURL *u = navigationAction.request.URL;
    if (u && [self isLocalURL:u]) [self.webView loadRequest:navigationAction.request];
    else if (u) [[NSWorkspace sharedWorkspace] openURL:u];
    return nil;
}
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    NSAlert *a = [NSAlert new]; a.messageText = message; [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) { completionHandler(); }];
}
- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler {
    NSAlert *a = [NSAlert new]; a.messageText = message; [a addButtonWithTitle:@"OK"]; [a addButtonWithTitle:@"Cancel"];
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) { completionHandler(r == NSAlertFirstButtonReturn); }];
}
// <input type=file> inside the UI: without this method WKWebView silently does nothing.
- (void)webView:(WKWebView *)webView runOpenPanelWithParameters:(WKOpenPanelParameters *)parameters initiatedByFrame:(WKFrameInfo *)frame
        completionHandler:(void (^)(NSArray<NSURL *> *_Nullable))completionHandler {
    NSOpenPanel *p = [NSOpenPanel openPanel];
    p.canChooseFiles = YES; p.canChooseDirectories = parameters.allowsDirectories; p.allowsMultipleSelection = parameters.allowsMultipleSelection;
    [p beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) { completionHandler(r == NSModalResponseOK ? p.URLs : nil); }];
}

#pragma mark - Update checks (disclosed, off-able)

- (void)runBackgroundUpdateChecks {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d boolForKey:HAPrefCheckDshUpdates]) {
        [self.updater checkDshLatest:^(NSString *latest, BOOL newer) {
            if (newer) [self setNotice:[NSString stringWithFormat:@"dsh %@ available — dsh ▸ Update dsh…", latest] forKey:@"dsh-update"];
        }];
    }
    if ([d boolForKey:HAPrefCheckAppUpdates]) {
        [self.updater checkAppLatest:^(NSString *latest, BOOL newer, NSURL *page) {
            if (newer) [self setNotice:[NSString stringWithFormat:@"Harness %@ available — brew upgrade harness-app", latest] forKey:@"app-update"];
        }];
    }
}

- (void)checkDshUpdatesNow:(id)sender {
    if (!self.updater) return;
    [self setNotice:@"checking dsh…" forKey:@"dsh-update"];
    [self.updater checkDshLatest:^(NSString *latest, BOOL newer) {
        [self setNotice:nil forKey:@"dsh-update"];
        if (!latest) { [self presentSheetTitle:@"Could not check npm" detail:@"npm view @deepseek-ai/dsh version did not answer (offline, or npm not on your login-shell PATH)." buttons:@[@"OK"] handler:nil]; return; }
        if (!newer) { [self presentSheetTitle:@"dsh is up to date" detail:[NSString stringWithFormat:@"Installed %@ · latest on npm %@", self.env.dshVersion ?: @"?", latest] buttons:@[@"OK"] handler:nil]; return; }
        [self setNotice:[NSString stringWithFormat:@"dsh %@ available — dsh ▸ Update dsh…", latest] forKey:@"dsh-update"];
        [self presentSheetTitle:[NSString stringWithFormat:@"dsh %@ is available", latest]
                         detail:[NSString stringWithFormat:@"Installed: %@. Update runs visibly in Terminal:\n\n%@", self.env.dshVersion ?: @"?", [self dshInstallCommand]]
                        buttons:@[@"Update in Terminal", @"Later"] handler:^(NSInteger i) { if (i == 0) [self updateDsh:nil]; }];
    }];
}

#pragma mark - Menu actions (View / Server / dsh)

- (void)reloadPage:(id)sender { [self.webView reload]; }
- (void)openInBrowser:(id)sender { if (self.server) [[NSWorkspace sharedWorkspace] openURL:self.server.baseURL]; }
- (void)restartServer:(id)sender { [self.sleepGuard deactivate]; if (self.server) { [self showPlaceholder:@"Restarting dsh…"]; [self.server restart]; } else [self startServer]; }
- (void)toggleKeepAlive:(id)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:![d boolForKey:HAPrefKeepServerRunning] forKey:HAPrefKeepServerRunning];
}
- (void)applySleepGuard {
    if (!self.sleepGuard) self.sleepGuard = [HASleepGuard new];
    BOOL want = [[NSUserDefaults standardUserDefaults] boolForKey:HAPrefPreventSleep] && self.server != nil && self.server.mode != HAServerModeNone;
    if (want) [self.sleepGuard activateWithReason:@"Harness.app: dsh server running"]; else [self.sleepGuard deactivate];
}
- (void)togglePreventSleep:(id)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:![d boolForKey:HAPrefPreventSleep] forKey:HAPrefPreventSleep];   // the observer applies it
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:HAPrefPreventSleep]) [self applySleepGuard];
}
// Update/repair aim at the npm prefix that owns the dsh we found (a login shell may put another npm first).
- (NSString *)dshInstallCommand { return HADshInstallCommandForPackageDir(self.env.dshPackageDir); }
- (void)openLog:(id)sender { [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:HALogPath()]]; }
- (void)openWorkspaceInTerminal:(id)sender {
    NSError *err = nil;
    if (![HAUpdater runInTerminal:[@"cd " stringByAppendingString:HAShellQuote([self effectiveWorkspace])] error:&err])
        [self presentSheetTitle:@"Could not open Terminal" detail:err.localizedDescription buttons:@[@"OK"] handler:nil];
}
- (void)runInstallCommandWithTitle:(NSString *)title {
    NSError *err = nil;
    if (![HAUpdater runInTerminal:[self dshInstallCommand] error:&err]) { [self presentSheetTitle:@"Could not open Terminal" detail:err.localizedDescription buttons:@[@"OK"] handler:nil]; return; }
    [self presentSheetTitle:title detail:@"The command is running in Terminal — nothing happens hidden. When it finishes, choose Server ▸ Restart Server." buttons:@[@"OK"] handler:nil];
}
- (void)updateDsh:(id)sender { [self runInstallCommandWithTitle:@"Updating dsh in Terminal…"]; }
- (void)repairShellTools:(id)sender { [self runInstallCommandWithTitle:@"Repairing dsh in Terminal…"]; }
#pragma mark - dsh menu: reveal / edit / listings (nothing here writes)

- (NSString *)dshHome { return HADshHome(self.env.shellEnvironment); }
- (void)revealPath:(NSString *)path {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [self presentSheetTitle:@"Not there yet" detail:[NSString stringWithFormat:@"%@ does not exist. dsh creates it on first use.", [path stringByAbbreviatingWithTildeInPath]] buttons:@[@"OK"] handler:nil];
        return;
    }
    [[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""];
}
- (void)revealDshHome:(id)sender { [self revealPath:[self dshHome]]; }
- (void)revealSessions:(id)sender { [self revealPath:[[self dshHome] stringByAppendingPathComponent:@"sessions"]]; }
- (void)revealPresetsFolder:(id)sender { [self revealPath:[[self dshHome] stringByAppendingPathComponent:@".agent-presets"]]; }
- (void)revealSkillsFolder:(id)sender { [self revealPath:[[self dshHome] stringByAppendingPathComponent:@"skills"]]; }
- (void)revealMenuItemPath:(NSMenuItem *)sender { [self revealPath:sender.representedObject]; }
- (void)editProfileConfig:(id)sender {
    NSString *profile = [[NSUserDefaults standardUserDefaults] stringForKey:HAPrefProfile] ?: HADefaultProfile;
    NSString *file = [[[self dshHome] stringByAppendingPathComponent:[@"profiles/" stringByAppendingString:profile]] stringByAppendingPathComponent:@"cordis.patch.yml"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:file]) {
        [self presentSheetTitle:@"No profile config yet" detail:[NSString stringWithFormat:@"%@ does not exist. dsh writes it the first time the “%@” profile boots.", [file stringByAbbreviatingWithTildeInPath], profile]
                        buttons:@[@"Restart Server", @"OK"] handler:^(NSInteger i) { if (i == 0) [self restartServer:nil]; }];
        return;
    }
    NSURL *u = [NSURL fileURLWithPath:file];
    if (![[NSWorkspace sharedWorkspace] openURL:u]) {
        NSURL *textEdit = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"com.apple.TextEdit"];
        if (textEdit) [[NSWorkspace sharedWorkspace] openURLs:@[u] withApplicationAtURL:textEdit configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
    }
}
- (void)fillListMenu:(NSMenu *)menu dirs:(NSArray<NSString *> *)dirs revealTitle:(NSString *)revealTitle revealAction:(SEL)revealAction folder:(NSString *)folder {
    [menu removeAllItems];
    [menu addItem:item(revealTitle, revealAction, @"")];
    [menu addItem:[NSMenuItem separatorItem]];
    if (dirs.count == 0) { NSMenuItem *none = item(@"(none installed)", NULL, @""); none.enabled = NO; [menu addItem:none]; }
    for (NSString *d in dirs) {
        NSString *title = [d hasPrefix:folder] ? d.lastPathComponent : [NSString stringWithFormat:@"%@  (~/.agents)", d.lastPathComponent];
        NSMenuItem *it = item(title, @selector(revealMenuItemPath:), @""); it.representedObject = d; [menu addItem:it];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:item(@"Restart Server", @selector(restartServer:), @"")];
}

#pragma mark - Install from Git URL (clone → detect → show the exact script → run it visibly in Terminal)

- (void)installFromGitURL:(id)sender {
    if (self.installing) { [self setNotice:@"an install is already running" forKey:@"install"]; return; }
    NSAlert *a = [NSAlert new];
    a.messageText = @"Install a dsh preset, skill or plugin from Git";
    a.informativeText = @"Paste the repository URL. Harness clones it into ~/Library/Application Support/Harness.app/sources, shows what it found, and installs only what you tick — visibly, in Terminal. Nothing is curated or bundled: you are trusting the repository you paste.";
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 440, 24)]; f.placeholderString = @"https://github.com/owner/repo"; a.accessoryView = f;
    [a addButtonWithTitle:@"Fetch"]; [a addButtonWithTitle:@"Cancel"];
    a.window.initialFirstResponder = f;
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r != NSAlertFirstButtonReturn) return;
        [self cloneAndScan:f.stringValue];
    }];
}

- (void)cloneAndScan:(NSString *)url {
    url = [url stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *target = HAInstallCloneTargetForURL(url, HASourcesRoot());
    if (!target) { [self presentSheetTitle:@"That doesn't look like a Git repository URL" detail:@"Use https://host/owner/repo, git@host:owner/repo.git or ssh://host/owner/repo." buttons:@[@"OK"] handler:nil]; return; }
    NSString *git = HAFindExecutable(@"git", self.env.shellEnvironment[@"PATH"]);
    if (!git && [[NSFileManager defaultManager] isExecutableFileAtPath:@"/usr/bin/git"]) git = @"/usr/bin/git";
    if (!git) { [self presentSheetTitle:@"git was not found" detail:@"Install the Xcode Command Line Tools:  xcode-select --install" buttons:@[@"OK"] handler:nil]; return; }
    NSString *cmd = [NSString stringWithFormat:@"%@ clone --depth 1 --recurse-submodules --shallow-submodules --quiet %@ %@ 2>&1", HAShellQuote(git), HAShellQuote(url), HAShellQuote(target)];
    self.installing = YES; [self setNotice:[NSString stringWithFormat:@"cloning %@…", url] forKey:@"install"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:target.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [fm removeItemAtPath:target error:nil];   // a cache, not user data: always fetch fresh
        NSMutableDictionary *env = [self.env.shellEnvironment mutableCopy]; env[@"GIT_TERMINAL_PROMPT"] = @"0";   // never prompt for credentials
        int status = -1;
        NSString *out = HARunCommandOutput(@"/bin/sh", @[@"-c", cmd], env, 120, &status);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.installing = NO; [self setNotice:nil forKey:@"install"];
            if (status != 0) {
                NSString *why = out.length ? out : (status == -1 ? @"git did not finish within 120 s (or it needs credentials — Harness never prompts for them)." : [NSString stringWithFormat:@"exit status %d", status]);
                [self presentSheetTitle:@"git clone failed" detail:[NSString stringWithFormat:@"%@\n\n%@", why, cmd] buttons:@[@"Copy Command", @"OK"] handler:^(NSInteger i) {
                    if (i == 0) { [[NSPasteboard generalPasteboard] clearContents]; [[NSPasteboard generalPasteboard] setString:cmd forType:NSPasteboardTypeString]; }
                }];
                return;
            }
            [self presentInstallChoicesFor:target];
        });
    });
}

- (void)presentInstallChoicesFor:(NSString *)clone {
    NSArray<HAInstallItem *> *items = HAScanInstallables(clone, [self dshHome]);
    NSString *readme = nil;
    for (NSString *n in @[@"README.md", @"readme.md", @"README", @"README.zh-CN.md", @"README.zh.md"])
        if ([[NSFileManager defaultManager] fileExistsAtPath:[clone stringByAppendingPathComponent:n]]) { readme = [clone stringByAppendingPathComponent:n]; break; }
    if (items.count == 0) {
        [self presentSheetTitle:@"No presets, skills or plugins recognised"
                         detail:@"Harness looks for directories holding preset.yml (agent presets), SKILL.md (skills), or package.json plus cordis.patch.yml (plugins), up to four levels deep. This repository has none, so follow its own instructions."
                        buttons:@[@"Reveal Clone", readme ? @"Open README" : @"OK"] handler:^(NSInteger i) {
            if (i == 0) [[NSWorkspace sharedWorkspace] selectFile:clone inFileViewerRootedAtPath:@""];
            else if (readme) [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:readme]];
        }];
        return;
    }
    NSAlert *a = [NSAlert new];
    a.messageText = [NSString stringWithFormat:@"Found in %@", clone.lastPathComponent];
    a.informativeText = @"Tick what to install. Presets go to $DSH_HOME/.agent-presets, skills to $DSH_HOME/skills; plugins run `dsh plugin add`. Anything already there is moved aside, never deleted. You will see the exact script before it runs.";
    NSStackView *stack = [NSStackView stackViewWithViews:@[]]; stack.orientation = NSUserInterfaceLayoutOrientationVertical; stack.alignment = NSLayoutAttributeLeading; stack.spacing = 4;
    NSMutableArray<NSButton *> *boxes = [NSMutableArray array];
    for (HAInstallItem *it in items) { NSButton *b = [NSButton checkboxWithTitle:it.label target:nil action:nil]; b.state = NSControlStateValueOn; [stack addArrangedSubview:b]; [boxes addObject:b]; }
    stack.frame = NSMakeRect(0, 0, 560, MAX(24, 22 * (CGFloat)items.count)); a.accessoryView = stack;
    [a addButtonWithTitle:@"Continue"]; [a addButtonWithTitle:@"Reveal Clone"]; [a addButtonWithTitle:@"Cancel"];
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r == NSAlertSecondButtonReturn) { [[NSWorkspace sharedWorkspace] selectFile:clone inFileViewerRootedAtPath:@""]; return; }
        if (r != NSAlertFirstButtonReturn) return;
        NSMutableArray *chosen = [NSMutableArray array];
        for (NSUInteger i = 0; i < items.count; i++) if (boxes[i].state == NSControlStateValueOn) [chosen addObject:items[i]];
        if (chosen.count) [self confirmAndRunInstall:chosen];
    }];
}

- (void)confirmAndRunInstall:(NSArray<HAInstallItem *> *)items {
    NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"yyyyMMdd-HHmmss"; NSString *stamp = [df stringFromDate:[NSDate date]];
    NSString *profile = [[NSUserDefaults standardUserDefaults] stringForKey:HAPrefProfile] ?: HADefaultProfile;
    NSString *script = HAInstallScript(items, [self dshHome], self.env.dshPath, profile, stamp);
    NSString *file = [HASourcesRoot() stringByAppendingFormat:@"/install-%@.sh", stamp];
    [[NSFileManager defaultManager] createDirectoryAtPath:HASourcesRoot() withIntermediateDirectories:YES attributes:nil error:nil];
    [script writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod(file.fileSystemRepresentation, 0700);
    NSAlert *a = [NSAlert new];
    a.messageText = @"This is exactly what will run in Terminal";
    a.informativeText = [NSString stringWithFormat:@"Saved as %@. Terminal runs it with bash -ex, echoing every command; it stops at the first error.", [file stringByAbbreviatingWithTildeInPath]];
    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 600, 220)];
    NSTextView *tv = [[NSTextView alloc] initWithFrame:sv.bounds]; tv.string = script; tv.editable = NO; tv.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    tv.autoresizingMask = NSViewWidthSizable; tv.horizontallyResizable = NO; tv.textContainer.widthTracksTextView = YES;
    sv.documentView = tv; sv.hasVerticalScroller = YES; sv.borderType = NSBezelBorder; a.accessoryView = sv;
    [a addButtonWithTitle:@"Install in Terminal"]; [a addButtonWithTitle:@"Copy Script"]; [a addButtonWithTitle:@"Cancel"];
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r == NSAlertSecondButtonReturn) { [[NSPasteboard generalPasteboard] clearContents]; [[NSPasteboard generalPasteboard] setString:script forType:NSPasteboardTypeString]; return; }
        if (r != NSAlertFirstButtonReturn) return;
        NSError *err = nil;
        if (![HAUpdater runInTerminal:[@"bash -ex " stringByAppendingString:HAShellQuote(file)] error:&err]) { [self presentSheetTitle:@"Could not open Terminal" detail:err.localizedDescription buttons:@[@"OK"] handler:nil]; return; }
        [self presentSheetTitle:@"Installing in Terminal…" detail:@"Every command is echoed there. When it finishes, choose Server ▸ Restart Server, then pick the preset (or use the skill) in a new session." buttons:@[@"OK"] handler:nil];
    }];
}

- (void)showPreferences:(id)sender {
    if (!self.preferencesController) {
        __weak typeof(self) weakSelf = self;
        self.preferencesController = [[HAPreferencesWindowController alloc] initWithOpenLog:^{ [weakSelf openLog:nil]; }];
    }
    [self.preferencesController showWindow:nil];
    [self.preferencesController.window makeKeyAndOrderFront:nil];
}

- (void)showAbout:(id)sender {
    NSString *mode = @[@"not started", @"attached to an existing server", @"started by Harness"][self.server.mode];
    NSString *credits = [NSString stringWithFormat:
        @"Native macOS launcher for DeepSeek Harness (unofficial).\n\n"
        @"dsh: %@ (%@)\nServer: %@ — %@\nProfile: %@\nWorkspace: %@\nLog: %@\n\nMIT License · github.com/%@",
        self.env.dshVersion ?: @"not found", self.env.dshPath ?: @"—",
        self.server ? self.server.baseURL.absoluteString : @"—", mode,
        self.server.profile ?: @"—", self.server ? self.server.workspace : [self effectiveWorkspace], HALogPath(), HAGitHubRepo];
    NSAttributedString *att = [[NSAttributedString alloc] initWithString:credits attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:11]}];
    [NSApp orderFrontStandardAboutPanelWithOptions:@{NSAboutPanelOptionCredits: att, NSAboutPanelOptionApplicationName: @"Harness",
                                                     NSAboutPanelOptionApplicationVersion: HAAppVersion, NSAboutPanelOptionVersion: @""}];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu == self.presetsMenu) { [self fillListMenu:menu dirs:HAInstalledPresetDirs([self dshHome]) revealTitle:@"Reveal Presets Folder" revealAction:@selector(revealPresetsFolder:) folder:[[self dshHome] stringByAppendingPathComponent:@".agent-presets"]]; return; }
    if (menu == self.skillsMenu)  { [self fillListMenu:menu dirs:HAInstalledSkillDirs([self dshHome])  revealTitle:@"Reveal Skills Folder"  revealAction:@selector(revealSkillsFolder:)  folder:[[self dshHome] stringByAppendingPathComponent:@"skills"]]; return; }
    if (menu != self.profileMenu) return;
    [menu removeAllItems];
    NSString *current = [[NSUserDefaults standardUserDefaults] stringForKey:HAPrefProfile] ?: HADefaultProfile;
    for (NSString *name in HAAvailableProfiles(self.env.shellEnvironment)) {
        NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:name action:@selector(selectProfile:) keyEquivalent:@""];
        it.state = [name isEqualToString:current] ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:it];
    }
}

- (void)selectProfile:(NSMenuItem *)sender {
    NSString *current = [[NSUserDefaults standardUserDefaults] stringForKey:HAPrefProfile] ?: HADefaultProfile;
    if ([sender.title isEqualToString:current]) return;
    if (self.server.mode == HAServerModeAttached) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.title forKey:HAPrefProfile];
        [self presentSheetTitle:@"Profile saved" detail:@"Harness is attached to a server it did not start, so the running profile is unchanged. Stop that server (or turn off Keep Server Running) and restart to use the new profile." buttons:@[@"OK"] handler:nil];
        return;
    }
    [self replaceServerWithProfile:sender.title workspace:nil];
}

// Folder dropped on the Dock icon, or `open -a Harness <dir>`.
- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:filename isDirectory:&isDir] || !isDir) return NO;
    if (!self.server) { self.launchWorkspace = filename; return YES; }   // before startServer ran
    if (self.server.mode == HAServerModeAttached) {
        [self presentSheetTitle:@"Workspace unchanged" detail:@"Harness is attached to a server it did not start, so its workspace cannot be changed from here." buttons:@[@"OK"] handler:nil];
        return YES;
    }
    [self replaceServerWithProfile:nil workspace:filename];
    return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(toggleKeepAlive:))
        item.state = [[NSUserDefaults standardUserDefaults] boolForKey:HAPrefKeepServerRunning] ? NSControlStateValueOn : NSControlStateValueOff;
    if (item.action == @selector(togglePreventSleep:))
        item.state = [[NSUserDefaults standardUserDefaults] boolForKey:HAPrefPreventSleep] ? NSControlStateValueOn : NSControlStateValueOff;
    if (item.action == @selector(openInBrowser:) || item.action == @selector(restartServer:)) return self.server != nil;
    return YES;
}
@end

#pragma mark - Menu bar

static NSMenuItem *item(NSString *title, SEL action, NSString *key) { return [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key]; }

static NSMenu *buildMenu(AppDelegate *d) {
    NSMenu *main = [NSMenu new];
    NSMenuItem *appItem = [NSMenuItem new]; [main addItem:appItem];
    NSMenu *app = [NSMenu new];
    [app addItem:item(@"About Harness", @selector(showAbout:), @"")];
    [app addItem:[NSMenuItem separatorItem]];
    [app addItem:item(@"Settings…", @selector(showPreferences:), @",")];
    [app addItem:[NSMenuItem separatorItem]];
    [app addItem:item(@"Quit Harness", @selector(terminate:), @"q")];
    appItem.submenu = app;

    NSMenuItem *editItem = [NSMenuItem new]; [main addItem:editItem];
    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"];
    [edit addItem:item(@"Undo", @selector(undo:), @"z")]; [edit addItem:item(@"Redo", @selector(redo:), @"Z")];
    [edit addItem:[NSMenuItem separatorItem]];
    [edit addItem:item(@"Cut", @selector(cut:), @"x")]; [edit addItem:item(@"Copy", @selector(copy:), @"c")];
    [edit addItem:item(@"Paste", @selector(paste:), @"v")]; [edit addItem:item(@"Select All", @selector(selectAll:), @"a")];
    editItem.submenu = edit;

    NSMenuItem *viewItem = [NSMenuItem new]; [main addItem:viewItem];
    NSMenu *view = [[NSMenu alloc] initWithTitle:@"View"];
    [view addItem:item(@"Reload", @selector(reloadPage:), @"r")];
    [view addItem:item(@"Open in Browser", @selector(openInBrowser:), @"")];
    viewItem.submenu = view;

    NSMenuItem *serverItem = [NSMenuItem new]; [main addItem:serverItem];
    NSMenu *server = [[NSMenu alloc] initWithTitle:@"Server"];
    [server addItem:item(@"Restart Server", @selector(restartServer:), @"")];
    [server addItem:item(@"Keep Server Running After Close", @selector(toggleKeepAlive:), @"")];
    [server addItem:item(@"Prevent Sleep While Running", @selector(togglePreventSleep:), @"")];
    NSMenuItem *profileItem = item(@"Profile", NULL, @"");
    d.profileMenu = [[NSMenu alloc] initWithTitle:@"Profile"]; d.profileMenu.delegate = d;
    profileItem.submenu = d.profileMenu; [server addItem:profileItem];
    [server addItem:[NSMenuItem separatorItem]];
    [server addItem:item(@"Open Log", @selector(openLog:), @"")];
    [server addItem:item(@"Open Workspace in Terminal", @selector(openWorkspaceInTerminal:), @"")];
    serverItem.submenu = server;

    NSMenuItem *dshItem = [NSMenuItem new]; [main addItem:dshItem];
    NSMenu *dsh = [[NSMenu alloc] initWithTitle:@"dsh"];
    [dsh addItem:item(@"Update dsh…", @selector(updateDsh:), @"")];
    [dsh addItem:item(@"Check for dsh Updates Now", @selector(checkDshUpdatesNow:), @"")];
    [dsh addItem:[NSMenuItem separatorItem]];
    [dsh addItem:item(@"Install from Git URL…", @selector(installFromGitURL:), @"")];
    NSMenuItem *presetsItem = item(@"Presets", NULL, @""); d.presetsMenu = [[NSMenu alloc] initWithTitle:@"Presets"]; d.presetsMenu.delegate = d; presetsItem.submenu = d.presetsMenu; [dsh addItem:presetsItem];
    NSMenuItem *skillsItem = item(@"Skills", NULL, @""); d.skillsMenu = [[NSMenu alloc] initWithTitle:@"Skills"]; d.skillsMenu.delegate = d; skillsItem.submenu = d.skillsMenu; [dsh addItem:skillsItem];
    [dsh addItem:[NSMenuItem separatorItem]];
    [dsh addItem:item(@"Reveal dsh Home", @selector(revealDshHome:), @"")];
    [dsh addItem:item(@"Reveal Sessions", @selector(revealSessions:), @"")];
    [dsh addItem:item(@"Edit Profile Config…", @selector(editProfileConfig:), @"")];
    [dsh addItem:[NSMenuItem separatorItem]];
    [dsh addItem:item(@"Repair Shell Tools…", @selector(repairShellTools:), @"")];
    dshItem.submenu = dsh;

    NSMenuItem *windowItem = [NSMenuItem new]; [main addItem:windowItem];
    NSMenu *win = [[NSMenu alloc] initWithTitle:@"Window"];
    [win addItem:item(@"Minimize", @selector(performMiniaturize:), @"m")];
    [win addItem:item(@"Zoom", @selector(performZoom:), @"")];
    windowItem.submenu = win;
    return main;
}

// An NSAlert sheet holds a modal session during which NSApplication silently ignores terminate:.
// Dismiss sheets and modal sessions first so Cmd-Q, window close, AppleScript quit and SIGTERM all work.
@interface HAApplication : NSApplication
@end
@implementation HAApplication
- (void)terminate:(id)sender {
    for (NSWindow *w in self.windows) if (w.attachedSheet) [w endSheet:w.attachedSheet returnCode:NSModalResponseAbort];
    if (self.modalWindow) [self stopModalWithCode:NSModalResponseAbort];
    dispatch_async(dispatch_get_main_queue(), ^{ [super terminate:sender]; });
}
@end

#pragma mark - main

static dispatch_source_t gSigTerm, gSigInt;

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        for (int i = 1; i < argc; i++) {
            if (!strcmp(argv[i], "--check-env")) {   // headless diagnostics for scripts/CI
                HARegisterDefaults();
                NSString *pref = [[NSUserDefaults standardUserDefaults] stringForKey:HAPrefDshPath];
                HAEnvironment *env = [HAEnvironment capture:pref.length ? pref : nil];
                printf("Harness.app %s\n%s", HAAppVersion.UTF8String, env.report.UTF8String);
                return env.dshPath ? 0 : 1;
            }
            if (!strcmp(argv[i], "--version")) { printf("%s\n", HAAppVersion.UTF8String); return 0; }
        }
        NSApplication *app = [HAApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        app.mainMenu = buildMenu(delegate);
        signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN);
        gSigTerm = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(gSigTerm, ^{ [NSApp terminate:nil]; }); dispatch_resume(gSigTerm);
        gSigInt = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(gSigInt, ^{ [NSApp terminate:nil]; }); dispatch_resume(gSigInt);
        [app run];
    }
    return 0;
}
