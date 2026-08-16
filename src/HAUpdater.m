#import "HAUpdater.h"
#import "HAEnvironment.h"
#import "HAConfig.h"

static NSArray<NSString *> *splitDots(NSString *s) { return s.length ? [s componentsSeparatedByString:@"."] : @[]; }
static BOOL isNumeric(NSString *s) { return s.length && [s rangeOfCharacterFromSet:[NSCharacterSet.decimalDigitCharacterSet invertedSet]].location == NSNotFound; }

NSComparisonResult HACompareVersions(NSString *a, NSString *b) {
    a = [a hasPrefix:@"v"] ? [a substringFromIndex:1] : a; b = [b hasPrefix:@"v"] ? [b substringFromIndex:1] : b;
    NSRange pa = [a rangeOfString:@"-"], pb = [b rangeOfString:@"-"];
    NSString *coreA = pa.location == NSNotFound ? a : [a substringToIndex:pa.location];
    NSString *coreB = pb.location == NSNotFound ? b : [b substringToIndex:pb.location];
    NSString *preA = pa.location == NSNotFound ? @"" : [a substringFromIndex:pa.location + 1];
    NSString *preB = pb.location == NSNotFound ? @"" : [b substringFromIndex:pb.location + 1];
    NSArray *ca = splitDots(coreA), *cb = splitDots(coreB);
    for (NSUInteger i = 0; i < MAX(ca.count, cb.count); i++) {
        NSInteger x = i < ca.count ? [ca[i] integerValue] : 0, y = i < cb.count ? [cb[i] integerValue] : 0;
        if (x != y) return x < y ? NSOrderedAscending : NSOrderedDescending;
    }
    if (preA.length == 0 && preB.length == 0) return NSOrderedSame;
    if (preA.length == 0) return NSOrderedDescending;   // release > prerelease
    if (preB.length == 0) return NSOrderedAscending;
    NSArray *ia = splitDots(preA), *ib = splitDots(preB);
    for (NSUInteger i = 0; i < MIN(ia.count, ib.count); i++) {
        BOOL na = isNumeric(ia[i]), nb = isNumeric(ib[i]);
        if (na && nb) { NSInteger x = [ia[i] integerValue], y = [ib[i] integerValue]; if (x != y) return x < y ? NSOrderedAscending : NSOrderedDescending; }
        else if (na != nb) return na ? NSOrderedAscending : NSOrderedDescending;   // numeric < alphanumeric
        else { NSComparisonResult r = [ia[i] compare:ib[i]]; if (r != NSOrderedSame) return r; }
    }
    if (ia.count == ib.count) return NSOrderedSame;
    return ia.count < ib.count ? NSOrderedAscending : NSOrderedDescending;
}

NSString *HAShellQuote(NSString *s) { return [NSString stringWithFormat:@"'%@'", [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]]; }
NSString *HAAppleScriptQuote(NSString *s) {
    return [[s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
}

@interface HAUpdater ()
@property NSDictionary<NSString *, NSString *> *environment;
@property (nullable) NSString *dshVersion;
@property NSString *appVersion;
@end

@implementation HAUpdater
- (instancetype)initWithEnvironment:(NSDictionary *)environment installedDshVersion:(NSString *)dshVersion appVersion:(NSString *)appVersion {
    if ((self = [super init])) { _environment = environment; _dshVersion = dshVersion; _appVersion = appVersion; }
    return self;
}
+ (NSString *)installCommand { return HADshInstallCommand; }

- (void)checkDshLatest:(void (^)(NSString *, BOOL))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *npm = HAFindExecutable(@"npm", self.environment[@"PATH"]);
        NSString *latest = nil;
        if (npm) {
            NSString *out = HARunCommandOutput(npm, @[@"view", @"@deepseek-ai/dsh", @"version"], self.environment, 8, NULL);
            out = [out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (out.length && out.length < 40 && [out rangeOfString:@" "].location == NSNotFound) latest = out;
        }
        BOOL newer = latest && self.dshVersion && HACompareVersions(self.dshVersion, latest) == NSOrderedAscending;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(latest, newer); });
    });
}

- (void)checkAppLatest:(void (^)(NSString *, BOOL, NSURL *))completion {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/repos/%@/releases/latest", HAGitHubRepo]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:5];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:[NSString stringWithFormat:@"Harness.app/%@", self.appVersion] forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSString *latest = nil; NSURL *page = nil;
        if (!err && [(NSHTTPURLResponse *)resp statusCode] == 200 && data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *tag = [json[@"tag_name"] isKindOfClass:NSString.class] ? json[@"tag_name"] : nil;
            if (tag.length) { latest = [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag; page = [NSURL URLWithString:json[@"html_url"] ?: @""]; }
        }
        BOOL newer = latest && HACompareVersions(self.appVersion, latest) == NSOrderedAscending;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(latest, newer, page); });
    }] resume];
}

+ (BOOL)runInTerminal:(NSString *)command error:(NSError **)error {
    NSString *script = [NSString stringWithFormat:@"tell application \"Terminal\"\nactivate\ndo script \"%@\"\nend tell", HAAppleScriptQuote(command)];
    NSTask *t = [NSTask new]; t.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"]; t.arguments = @[@"-e", script];
    t.standardError = [NSFileHandle fileHandleWithNullDevice]; t.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    if (![t launchAndReturnError:error]) return NO;
    [t waitUntilExit];
    if (t.terminationStatus != 0 && error) *error = [NSError errorWithDomain:@"Harness" code:t.terminationStatus userInfo:@{NSLocalizedDescriptionKey: @"Terminal.app refused the command (osascript failed). You may need to allow Harness to control Terminal in System Settings → Privacy & Security → Automation."}];
    return t.terminationStatus == 0;
}
@end
