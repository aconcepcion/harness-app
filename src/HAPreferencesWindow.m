#import "HAPreferencesWindow.h"
#import "HAConfig.h"
#import "HAEnvironment.h"

NSArray<NSString *> *HAAvailableProfiles(NSDictionary *env) {
    NSString *dir = [HADshHome(env) stringByAppendingPathComponent:@"profiles"];
    NSMutableOrderedSet *names = [NSMutableOrderedSet orderedSetWithObject:HADefaultProfile];
    for (NSString *n in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]) {
        BOOL isDir = NO;
        if ([n hasPrefix:@"."] || [n isEqualToString:@"node_modules"]) continue;
        if ([[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:n] isDirectory:&isDir] && isDir) [names addObject:n];
    }
    return names.array;
}

@interface HAPreferencesWindowController ()
@property (copy) void (^openLog)(void);
@property NSTextField *portField, *workspaceField, *dshField;
@property NSPopUpButton *profilePopup;
@end

@implementation HAPreferencesWindowController

- (instancetype)initWithOpenLog:(void (^)(void))openLog {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 370)
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable) backing:NSBackingStoreBuffered defer:NO];
    w.title = @"Harness Settings";
    if ((self = [super initWithWindow:w])) { _openLog = [openLog copy]; [self buildUI]; [w center]; }
    return self;
}

- (NSTextField *)label:(NSString *)s { NSTextField *l = [NSTextField labelWithString:s]; l.alignment = NSTextAlignmentRight; return l; }
- (NSButton *)checkbox:(NSString *)title key:(NSString *)key {
    NSButton *b = [NSButton checkboxWithTitle:title target:nil action:nil];
    [b bind:NSValueBinding toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:key] options:nil];
    return b;
}

- (void)buildUI {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSUserDefaultsController *udc = [NSUserDefaultsController sharedUserDefaultsController];

    self.portField = [NSTextField textFieldWithString:@""];
    NSNumberFormatter *nf = [NSNumberFormatter new]; nf.minimum = @1; nf.maximum = @65535; nf.allowsFloats = NO; nf.usesGroupingSeparator = NO; self.portField.formatter = nf;
    [self.portField bind:NSValueBinding toObject:udc withKeyPath:@"values.Port" options:@{NSContinuouslyUpdatesValueBindingOption: @NO}];

    self.workspaceField = [NSTextField textFieldWithString:@""];
    [self.workspaceField bind:NSValueBinding toObject:udc withKeyPath:@"values.Workspace" options:nil];
    NSButton *chooseWs = [NSButton buttonWithTitle:@"Choose…" target:self action:@selector(chooseWorkspace:)];

    self.profilePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.profilePopup addItemsWithTitles:HAAvailableProfiles([NSProcessInfo processInfo].environment)];
    [self.profilePopup selectItemWithTitle:[d stringForKey:HAPrefProfile] ?: HADefaultProfile];
    self.profilePopup.target = self; self.profilePopup.action = @selector(profileChanged:);

    self.dshField = [NSTextField textFieldWithString:@""];
    self.dshField.placeholderString = @"auto-detect from your login shell PATH";
    [self.dshField bind:NSValueBinding toObject:udc withKeyPath:@"values.DshPath" options:@{NSNullPlaceholderBindingOption: @""}];
    NSButton *chooseDsh = [NSButton buttonWithTitle:@"Choose…" target:self action:@selector(chooseDsh:)];

    NSButton *keep = [self checkbox:@"Keep the dsh server running after the window closes" key:HAPrefKeepServerRunning];
    NSButton *sleep = [self checkbox:@"Prevent sleep while the server is running (idle sleep only; a closed lid still sleeps)" key:HAPrefPreventSleep];
    NSButton *chkDsh = [self checkbox:@"Check for dsh updates at launch (runs npm view)" key:HAPrefCheckDshUpdates];
    NSButton *chkApp = [self checkbox:@"Check for Harness updates at launch (asks api.github.com)" key:HAPrefCheckAppUpdates];
    NSButton *openLog = [NSButton buttonWithTitle:@"Open Log" target:self action:@selector(openLogClicked:)];
    NSTextField *note = [NSTextField wrappingLabelWithString:@"Port, workspace, profile and dsh path apply on Server ▸ Restart Server. `defaults write com.arnoldoconcepcion.harness-app <Key> <value>` works too."];
    note.textColor = NSColor.secondaryLabelColor; note.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];

    NSStackView *wsRow = [NSStackView stackViewWithViews:@[self.workspaceField, chooseWs]]; wsRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    NSStackView *dshRow = [NSStackView stackViewWithViews:@[self.dshField, chooseDsh]]; dshRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    [self.workspaceField setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.dshField setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[self label:@"Port:"], self.portField],
        @[[self label:@"Workspace:"], wsRow],
        @[[self label:@"Profile:"], self.profilePopup],
        @[[self label:@"dsh path:"], dshRow],
        @[[NSView new], keep],
        @[[NSView new], sleep],
        @[[NSView new], chkDsh],
        @[[NSView new], chkApp],
        @[[NSView new], openLog],
        @[[NSView new], note],
    ]];
    grid.rowSpacing = 8; grid.columnSpacing = 10;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [self.window.contentView addSubview:grid];
    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:20],
        [grid.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:20],
        [grid.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-20],
        [self.portField.widthAnchor constraintEqualToConstant:90],
        [wsRow.widthAnchor constraintEqualToConstant:380],
        [dshRow.widthAnchor constraintEqualToConstant:380],
        [note.widthAnchor constraintEqualToConstant:380],
    ]];
}

- (void)profileChanged:(id)sender { [[NSUserDefaults standardUserDefaults] setObject:self.profilePopup.titleOfSelectedItem forKey:HAPrefProfile]; }
- (void)chooseWorkspace:(id)sender {
    NSOpenPanel *p = [NSOpenPanel openPanel]; p.canChooseDirectories = YES; p.canChooseFiles = NO; p.allowsMultipleSelection = NO;
    if ([p runModal] == NSModalResponseOK && p.URL) [[NSUserDefaults standardUserDefaults] setObject:p.URL.path forKey:HAPrefWorkspace];
}
- (void)chooseDsh:(id)sender {
    NSOpenPanel *p = [NSOpenPanel openPanel]; p.canChooseDirectories = NO; p.canChooseFiles = YES; p.showsHiddenFiles = YES; p.treatsFilePackagesAsDirectories = YES;
    if ([p runModal] == NSModalResponseOK && p.URL) [[NSUserDefaults standardUserDefaults] setObject:p.URL.path forKey:HAPrefDshPath];
}
- (void)openLogClicked:(id)sender { if (self.openLog) self.openLog(); }
@end
