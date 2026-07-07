/*
 * Local HTTP server for serving in-memory data on 127.0.0.1 only.
 * Two-phase: store data via POST-like API, serve via GET.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ASCLocalHTTPServer : NSObject

@property (nonatomic, readonly) NSUInteger port;
@property (nonatomic, readonly, getter=isRunning) BOOL running;

+ (instancetype)sharedInstance;

- (void)startWithData:(NSData *)data
           completion:(void(^)(NSString * _Nullable url, NSError * _Nullable error))completion;

- (void)stop;

@end

NS_ASSUME_NONNULL_END
