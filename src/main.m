#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <arpa/inet.h>

static uint16_t const kPort = 3080;
static NSString *const kURLString = @"http://127.0.0.1:3080";
static NSString *const kDshBin = @"/opt/homebrew/bin/dsh";

static BOOL portOpen(void) {
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return NO;
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(kPort);
    addr.sin_addr.s_addr = inet_addr("127.0.0.1");
    int r = connect(sock, (struct sockaddr *)&addr, sizeof(addr));
    close(sock);
    return r == 0;
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, WKUIDelegate>
@property (strong) NSWindow *window;
@property (strong) WKWebView *webView;
@property (strong) NSTask *serverChild;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    NSRect rect = NSMakeRect(0, 0, 1280, 860);
    self.window = [[NSWindow alloc]
        initWithContentRect:rect
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self.window.title = @"Harness";
    self.window.delegate = self;
    [self.window setFrameAutosaveName:@"HAMainWindow"];
    if (self.window.frame.size.width < 400) {
        [self.window setContentSize:rect.size];
        [self.window center];
    }

    self.webView = [[WKWebView alloc] initWithFrame:rect
                                      configuration:[WKWebViewConfiguration new]];
    self.webView.UIDelegate = self;
    self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.window.contentView = self.webView;
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    [self.webView loadHTMLString:
        @"<html><head><meta name=\"color-scheme\" content=\"light dark\"></head>"
        @"<body style=\"display:flex;align-items:center;justify-content:center;height:100vh;"
        @"font-family:-apple-system,sans-serif;font-size:1.2em\">"
        @"<div>Starting DeepSeek Harness&hellip;</div></body></html>"
                          baseURL:nil];

    if (!portOpen()) [self startServer];
    [self waitAndLoad:[NSDate dateWithTimeIntervalSinceNow:45]];
}

- (void)startServer {
    NSString *logDir = [NSHomeDirectory() stringByAppendingPathComponent:@".dsh/logs"];
    NSString *logPath = [logDir stringByAppendingPathComponent:@"web.log"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:logDir withIntermediateDirectories:YES attributes:nil error:nil];
    if (![fm fileExistsAtPath:logPath]) [fm createFileAtPath:logPath contents:nil attributes:nil];
    NSFileHandle *log = [NSFileHandle fileHandleForWritingAtPath:logPath];
    [log seekToEndOfFile];

    NSString *workDir = [NSHomeDirectory() stringByAppendingPathComponent:@"dsh-test"];
    if (![fm fileExistsAtPath:workDir]) workDir = NSHomeDirectory();

    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:kDshBin];
    task.arguments = @[ @"web" ];
    task.currentDirectoryURL = [NSURL fileURLWithPath:workDir];
    NSMutableDictionary *env =
        [[NSProcessInfo processInfo].environment mutableCopy];
    env[@"PATH"] = @"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    task.environment = env;
    if (log) { task.standardOutput = log; task.standardError = log; }

    NSError *error = nil;
    if ([task launchAndReturnError:&error]) {
        self.serverChild = task;
    } else {
        [self showError:[NSString stringWithFormat:
            @"Could not start the dsh server:\n%@\n\nIs %@ installed?",
            error.localizedDescription, kDshBin]];
    }
}

- (void)waitAndLoad:(NSDate *)deadline {
    if (portOpen()) {
        [self.webView loadRequest:
            [NSURLRequest requestWithURL:[NSURL URLWithString:kURLString]]];
    } else if ([deadline timeIntervalSinceNow] > 0) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [weakSelf waitAndLoad:deadline]; });
    } else {
        [self showError:@"The dsh server did not become ready within 45 seconds.\n"
                        @"Check ~/.dsh/logs/web.log."];
    }
}

- (void)showError:(NSString *)message {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Harness";
    alert.informativeText = message;
    [alert runModal];
}

// Close window => quit app => stop the server we started.
- (void)windowWillClose:(NSNotification *)note { [NSApp terminate:nil]; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }
- (void)applicationWillTerminate:(NSNotification *)note {
    if (self.serverChild && self.serverChild.isRunning) [self.serverChild terminate];
}

// Links that target a new window/tab go to the default browser (Brave here).
- (WKWebView *)webView:(WKWebView *)webView
    createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
               forNavigationAction:(WKNavigationAction *)navigationAction
                    windowFeatures:(WKWindowFeatures *)windowFeatures {
    if (navigationAction.request.URL)
        [[NSWorkspace sharedWorkspace] openURL:navigationAction.request.URL];
    return nil;
}

// Native handlers for JS dialogs, which WKWebView otherwise drops silently.
- (void)webView:(WKWebView *)webView
    runJavaScriptAlertPanelWithMessage:(NSString *)message
                      initiatedByFrame:(WKFrameInfo *)frame
                     completionHandler:(void (^)(void))completionHandler {
    NSAlert *a = [NSAlert new];
    a.messageText = message;
    [a runModal];
    completionHandler();
}

- (void)webView:(WKWebView *)webView
    runJavaScriptConfirmPanelWithMessage:(NSString *)message
                        initiatedByFrame:(WKFrameInfo *)frame
                       completionHandler:(void (^)(BOOL))completionHandler {
    NSAlert *a = [NSAlert new];
    a.messageText = message;
    [a addButtonWithTitle:@"OK"];
    [a addButtonWithTitle:@"Cancel"];
    completionHandler([a runModal] == NSAlertFirstButtonReturn);
}

- (void)reloadPage:(id)sender { [self.webView reload]; }

@end

static NSMenu *buildMenu(void) {
    NSMenu *main = [NSMenu new];

    NSMenuItem *appItem = [NSMenuItem new];
    [main addItem:appItem];
    NSMenu *appMenu = [NSMenu new];
    [appMenu addItemWithTitle:@"Quit Harness"
                       action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;

    NSMenuItem *editItem = [NSMenuItem new];
    [main addItem:editItem];
    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"];
    [edit addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [edit addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    [edit addItem:[NSMenuItem separatorItem]];
    [edit addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [edit addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [edit addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = edit;

    NSMenuItem *viewItem = [NSMenuItem new];
    [main addItem:viewItem];
    NSMenu *view = [[NSMenu alloc] initWithTitle:@"View"];
    [view addItemWithTitle:@"Reload" action:@selector(reloadPage:) keyEquivalent:@"r"];
    viewItem.submenu = view;

    NSMenuItem *windowItem = [NSMenuItem new];
    [main addItem:windowItem];
    NSMenu *win = [[NSMenu alloc] initWithTitle:@"Window"];
    [win addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [win addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    windowItem.submenu = win;

    return main;
}

static dispatch_source_t gSigTermSource;

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        app.mainMenu = buildMenu();

        // A plain SIGTERM (pkill, logout edge cases) should run the graceful
        // quit path so the child server is stopped, not orphaned.
        signal(SIGTERM, SIG_IGN);
        gSigTermSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0,
                                                dispatch_get_main_queue());
        dispatch_source_set_event_handler(gSigTermSource, ^{ [NSApp terminate:nil]; });
        dispatch_resume(gSigTermSource);

        [app run];
    }
    return 0;
}
