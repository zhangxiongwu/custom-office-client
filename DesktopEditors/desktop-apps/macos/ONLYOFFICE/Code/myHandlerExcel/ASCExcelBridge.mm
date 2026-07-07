#import "ASCExcelBridge.h"
#import "ASCLocalHTTPServer.h"
#import "ASCConstants.h"
#import "mac_application.h"
#import "NSString+Extensions.h"

@interface ASCExcelBridge ()
@property (nonatomic, strong) ASCLocalHTTPServer *httpServer;
@end

@implementation ASCExcelBridge

+ (instancetype)sharedInstance
{
    static id instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _httpServer = [ASCLocalHTTPServer sharedInstance];
    }
    return self;
}

- (void)handleCustomExcelQuery:(NSString *)queryString
{
    if (!queryString || queryString.length == 0) return;

    // Extract base64-encoded data from execCommand
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_onJSCommand:)
                                                 name:CEFEventNameEditorAppActionRequest
                                               object:nil];

    // Forward JSON config to JS via execCommand
    [self _sendToJS:[NSString stringWithFormat:@"myHandlerExcel:handle"] param:queryString];
}

- (void)_sendToJS:(NSString *)command param:(NSString *)param
{
    NSEditorApi::CAscExecCommandJS *pCmd = new NSEditorApi::CAscExecCommandJS;
    pCmd->put_Command([command stdwstring]);
    pCmd->put_Param([param stdwstring]);

    NSEditorApi::CAscMenuEvent *pEvent = new NSEditorApi::CAscMenuEvent(ASC_MENU_EVENT_TYPE_CEF_EXECUTE_COMMAND_JS);
    pEvent->m_pData = pCmd;

    CAscApplicationManager *appManager = [NSAscApplicationWorker getAppManager];
    appManager->SetEventToAllMainWindows(pEvent);
}

- (void)_onJSCommand:(NSNotification *)notification
{
    if (!notification || !notification.userInfo) return;
    id json = notification.userInfo;
    NSString *action = json[@"action"];
    if (!action) return;

    if ([action hasPrefix:@"myHandlerExcel:startServer:"]) {
        NSString *base64 = [action substringFromIndex:[@"myHandlerExcel:startServer:" length]];
        [self _startServerWithBase64:base64];

        // TODO: detach observer after handling
    }
}

- (void)_startServerWithBase64:(NSString *)base64
{
    if (!base64 || base64.length == 0) return;

    NSData *data = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
    if (!data) return;

    [self.httpServer startWithData:data completion:^(NSString *url, NSError *error) {
        if (error || !url) {
            NSLog(@"[ASCExcelBridge] HTTP server start failed: %@", error);
            return;
        }
        NSLog(@"[ASCExcelBridge] HTTP server at %@", url);
        [self _openEditorWithURL:url];
    }];
}

- (void)_openEditorWithURL:(NSString *)urlString
{
    [[NSNotificationCenter defaultCenter] postNotificationName:CEFEventNameCreateTab
                                                        object:nil
                                                      userInfo:@{
                                                          @"action": @(ASCTabActionOpenUrl),
                                                          @"url": urlString,
                                                          @"active": @(YES)
                                                      }];
}

- (void)shutdown
{
    [self.httpServer stop];
}

@end
