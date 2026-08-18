#import <Foundation/Foundation.h>

// Preference keys (NSUserDefaults, domain = bundle id com.arnoldoconcepcion.harness-app).
static NSString *const HAPrefPort              = @"Port";               // NSNumber, default 3080
static NSString *const HAPrefWorkspace         = @"Workspace";          // NSString path, default NSHomeDirectory()
static NSString *const HAPrefProfile           = @"Profile";            // NSString, default "web"
static NSString *const HAPrefDshPath           = @"DshPath";            // NSString, "" = auto-detect
static NSString *const HAPrefKeepServerRunning = @"KeepServerRunning";  // BOOL, default NO
static NSString *const HAPrefCheckDshUpdates   = @"CheckForDshUpdates"; // BOOL, default YES
static NSString *const HAPrefCheckAppUpdates   = @"CheckForAppUpdates"; // BOOL, default YES
static NSString *const HAPrefPreventSleep      = @"PreventSleepWhileRunning"; // BOOL, default NO

static NSString *const HAAppVersion     = @"3.1.1";
static NSString *const HAGitHubRepo     = @"aconcepcion/harness-app";
static NSString *const HADefaultProfile = @"web";
static uint16_t const HADefaultPort     = 3080;

static inline void HARegisterDefaults(void) {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        HAPrefPort: @(HADefaultPort),
        HAPrefWorkspace: NSHomeDirectory(),
        HAPrefProfile: HADefaultProfile,
        HAPrefDshPath: @"",
        HAPrefKeepServerRunning: @NO,
        HAPrefCheckDshUpdates: @YES,
        HAPrefCheckAppUpdates: @YES,
        HAPrefPreventSleep: @NO,
    }];
}

// Log lives where macOS expects app logs (Console.app picks it up).
static inline NSString *HALogPath(void) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/Harness.app"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"harness-app.log"];
}
