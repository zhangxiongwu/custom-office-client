/*
 * Bridge between native URL routing and JS business logic.
 * Native only: parse oo-office:// URL → forward to JS via execCommand.
 * JS calls back: execCommand("myHandlerExcel:startServer", base64Data)
 *   → native starts ASCLocalHTTPServer and opens editor URL.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ASCExcelBridge : NSObject

+ (instancetype)sharedInstance;

/// Called from AppDelegate when oo-office://action|excel-decode| is matched
- (void)handleCustomExcelQuery:(NSString *)queryString;

/// Called from AppDelegate on app termination
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
