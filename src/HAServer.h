#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HAServerMode) { HAServerModeNone = 0, HAServerModeAttached, HAServerModeSpawned };
@class HAServer;

@protocol HAServerDelegate <NSObject>
- (void)serverDidBecomeReady:(HAServer *)server;                  // load the UI (also fires after a successful auto-restart)
- (void)server:(HAServer *)server didFailToStart:(NSString *)reason;
- (void)serverDidRestart:(HAServer *)server;                      // child died; a fresh one is starting
- (void)server:(HAServer *)server didGiveUp:(NSString *)reason;   // second death within 60 s
@end

@interface HAServer : NSObject
@property (weak, nullable) id<HAServerDelegate> delegate;
@property (readonly) HAServerMode mode;
@property (readonly) uint16_t port;
@property (readonly) NSURL *baseURL;
@property (readonly) NSString *logPath;
@property (readonly) pid_t childPID;          // 0 unless spawned and alive
@property (readonly) NSString *profile;
@property (readonly) NSString *workspace;

- (instancetype)initWithDshPath:(NSString *)dshPath port:(uint16_t)port profile:(NSString *)profile
                      workspace:(NSString *)workspace environment:(NSDictionary<NSString *, NSString *> *)environment
                        logPath:(NSString *)logPath;
- (void)start;                                  // attach-or-spawn; async; delegate on main queue
- (void)restart;                                // spawned: stop + fresh spawn; attached: re-probe only
- (BOOL)stopSynchronously:(NSTimeInterval)grace; // SIGTERM group → wait ≤ grace → SIGKILL group; YES when nothing left. No-op when attached.
- (BOOL)probeReady;                             // HTTP GET baseURL, 1 s timeout
- (NSString *)logTail:(NSUInteger)lines;
+ (BOOL)probeURL:(NSURL *)url timeout:(NSTimeInterval)timeout;
+ (NSArray<NSString *> *)argumentsForProfile:(NSString *)profile port:(uint16_t)port;
@end
NS_ASSUME_NONNULL_END
