#import "ASCLocalHTTPServer.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

@interface ASCLocalHTTPServer ()
{
    int _serverSocket;
    dispatch_source_t _acceptSource;
    dispatch_queue_t _serverQueue;
}
@property (nonatomic, strong) NSData *dataToServe;
@property (nonatomic, assign) NSUInteger port;
@property (nonatomic, assign, getter=isRunning) BOOL running;
@property (nonatomic, copy) void(^startCompletion)(NSString *url, NSError *error);
@property (nonatomic, assign) BOOL responseSent;
@end

@implementation ASCLocalHTTPServer

+ (instancetype)sharedInstance
{
    static id sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _serverSocket = -1;
        _running = NO;
        _responseSent = NO;
        _serverQueue = dispatch_queue_create("com.onlyoffice.localhttpserver", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)startWithData:(NSData *)data
           completion:(void(^)(NSString *url, NSError *error))completion
{
    if (self.isRunning) {
        [self stop];
    }

    self.dataToServe = data;
    self.startCompletion = completion;
    self.responseSent = NO;

    dispatch_async(_serverQueue, ^{
        [self _createSocketAndListen];
    });
}

- (void)_createSocketAndListen
{
    _serverSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (_serverSocket < 0) {
        [self _failWithMsg:@"Failed to create socket"];
        return;
    }

    int reuse = 1;
    setsockopt(_serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = inet_addr("127.0.0.1");
    addr.sin_port = 0;

    if (bind(_serverSocket, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(_serverSocket); _serverSocket = -1;
        [self _failWithMsg:@"Failed to bind to 127.0.0.1"];
        return;
    }

    if (listen(_serverSocket, 1) < 0) {
        close(_serverSocket); _serverSocket = -1;
        [self _failWithMsg:@"Failed to listen"];
        return;
    }

    struct sockaddr_in boundAddr;
    socklen_t addrLen = sizeof(boundAddr);
    getsockname(_serverSocket, (struct sockaddr *)&boundAddr, &addrLen);
    self.port = ntohs(boundAddr.sin_port);
    self.running = YES;

    NSString *url = [NSString stringWithFormat:@"http://127.0.0.1:%lu/stream", (unsigned long)self.port];
    if (self.startCompletion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.startCompletion(url, nil);
        });
    }

    _acceptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,
                                           (uintptr_t)_serverSocket,
                                           0, _serverQueue);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_acceptSource, ^{
        [weakSelf _acceptConnection];
    });
    dispatch_source_set_cancel_handler(_acceptSource, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf->_serverSocket >= 0) {
            close(strongSelf->_serverSocket);
            strongSelf->_serverSocket = -1;
        }
    });
    dispatch_resume(_acceptSource);
}

- (void)_acceptConnection
{
    struct sockaddr_in clientAddr;
    socklen_t clientAddrLen = sizeof(clientAddr);
    int client = accept(_serverSocket, (struct sockaddr *)&clientAddr, &clientAddrLen);
    if (client < 0) return;

    dispatch_async(_serverQueue, ^{
        [self _handleClient:client];
    });
}

- (void)_handleClient:(int)clientSocket
{
    char buf[4096];
    ssize_t n = recv(clientSocket, buf, sizeof(buf) - 1, 0);
    if (n > 0) {
        buf[n] = '\0';
        NSString *req = [[NSString alloc] initWithUTF8String:buf];
        if ([req hasPrefix:@"GET "]) {
            [self _sendDataResponse:clientSocket];
            self.responseSent = YES;
        }
    }
    close(clientSocket);

    if (self.responseSent) {
        dispatch_async(_serverQueue, ^{ [self _stopInternal]; });
    }
}

- (void)_sendDataResponse:(int)fd
{
    NSData *body = self.dataToServe ?: [NSData data];
    NSString *header = [NSString stringWithFormat:
        @"HTTP/1.1 200 OK\r\n"
        @"Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\r\n"
        @"Content-Length: %lu\r\n"
        @"Access-Control-Allow-Origin: *\r\n"
        @"Connection: close\r\n\r\n", (unsigned long)body.length];
    NSData *hd = [header dataUsingEncoding:NSUTF8StringEncoding];
    send(fd, hd.bytes, hd.length, 0);
    send(fd, body.bytes, body.length, 0);
}

- (void)stop { dispatch_async(_serverQueue, ^{ [self _stopInternal]; }); }

- (void)_stopInternal
{
    if (!self.running) return;
    self.running = NO;
    if (_acceptSource) { dispatch_source_cancel(_acceptSource); _acceptSource = nil; }
    self.dataToServe = nil;
    self.startCompletion = nil;
}

- (void)_failWithMsg:(NSString *)msg
{
    self.running = NO;
    if (self.startCompletion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.startCompletion(nil, [NSError errorWithDomain:@"ASCLocalHTTPServer" code:-1
                                                      userInfo:@{NSLocalizedDescriptionKey: msg}]);
        });
    }
}

- (void)dealloc { [self _stopInternal]; }

@end
