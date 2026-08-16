#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "HAConfig.h"
#import "HAEnvironment.h"
#import "HAServer.h"
#import "HAUpdater.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, WKUIDelegate, WKNavigationDelegate, HAServerDelegate, NSMenuDelegate>
@property (strong) NSWindow *window;
@property (strong) WKWebView *webView;
@property (strong) HAEnvironment *env;
@property (strong) HAServer *server;
@property (strong) HAUpdater *updater;
@property (copy) NSString *launchWorkspace;          // Dock drop / open-with, overrides preference for this launch
@property (strong) NSMutableDictionary<NSString *, NSString *> *notices;
@property (strong) NSMenu *profileMenu;
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
                         detail:[NSString stringWithFormat:@"Installed: %@. Update runs visibly in Terminal:\n\n%@", self.env.dshVersion ?: @"?", HADshInstallCommand]
                        buttons:@[@"Update in Terminal", @"Later"] handler:^(NSInteger i) { if (i == 0) [self updateDsh:nil]; }];
    }];
}

#pragma mark - Menu actions (View / Server / dsh)

- (void)reloadPage:(id)sender { [self.webView reload]; }
- (void)openInBrowser:(id)sender { if (self.server) [[NSWorkspace sharedWorkspace] openURL:self.server.baseURL]; }
- (void)restartServer:(id)sender { if (self.server) { [self showPlaceholder:@"Restarting dsh…"]; [self.server restart]; } else [self startServer]; }
- (void)toggleKeepAlive:(id)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:![d boolForKey:HAPrefKeepServerRunning] forKey:HAPrefKeepServerRunning];
}
- (void)openLog:(id)sender { [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:HALogPath()]]; }
- (void)openWorkspaceInTerminal:(id)sender {
    NSError *err = nil;
    if (![HAUpdater runInTerminal:[@"cd " stringByAppendingString:HAShellQuote([self effectiveWorkspace])] error:&err])
        [self presentSheetTitle:@"Could not open Terminal" detail:err.localizedDescription buttons:@[@"OK"] handler:nil];
}
- (void)runInstallCommandWithTitle:(NSString *)title {
    NSError *err = nil;
    if (![HAUpdater runInTerminal:HADshInstallCommand error:&err]) { [self presentSheetTitle:@"Could not open Terminal" detail:err.localizedDescription buttons:@[@"OK"] handler:nil]; return; }
    [self presentSheetTitle:title detail:@"The command is running in Terminal — nothing happens hidden. When it finishes, choose Server ▸ Restart Server." buttons:@[@"OK"] handler:nil];
}
- (void)updateDsh:(id)sender { [self runInstallCommandWithTitle:@"Updating dsh in Terminal…"]; }
- (void)repairShellTools:(id)sender { [self runInstallCommandWithTitle:@"Repairing dsh in Terminal…"]; }
- (void)showPreferences:(id)sender { /* wired in Task 6 */ }
- (void)showAbout:(id)sender { /* wired in Task 6 */ }
- (void)selectProfile:(NSMenuItem *)sender { /* wired in Task 6 */ }
- (void)menuNeedsUpdate:(NSMenu *)menu { /* wired in Task 6 */ }

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(toggleKeepAlive:))
        item.state = [[NSUserDefaults standardUserDefaults] boolForKey:HAPrefKeepServerRunning] ? NSControlStateValueOn : NSControlStateValueOff;
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
    [app addItem:item(@"Preferences…", @selector(showPreferences:), @",")];
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
