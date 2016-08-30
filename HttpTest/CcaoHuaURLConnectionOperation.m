//
//  CcaoHuaURLConnectionOperation.m
//  CcaoHuaLogin
//
//  Created by Weep Yan on 16/8/30.
//  Copyright © 2016年 Ice_Rin Liu. All rights reserved.
//

#import "CcaoHuaURLConnectionOperation.h"
typedef NS_ENUM(NSInteger, CHOperationState) {
    CHOperationPausedState      = -1,
    CHOperationReadyState       = 1,
    CHOperationExecutingState   = 2,
    CHOperationFinishedState    = 3,
};

static NSString * const kCHNetworkingLockName = @"com.caohua.networking.operation.lock";
NSString * const CHNetworkingOperationDidStartNotification = @"com.caohua.networking.operation.start";
NSString * const CHNetworkingOperationDidFinishNotification = @"com.caohua.networking.operation.finish";

typedef void (^CHURLConnectionOperationProgressBlock)(NSUInteger bytes, long long totalBytes, long long totalBytesExpected);
typedef void (^CHURLConnectionOperationAuthenticationChallengeBlock)(NSURLConnection *connection, NSURLAuthenticationChallenge *challenge);
typedef NSCachedURLResponse * (^CHURLConnectionOperationCacheResponseBlock)(NSURLConnection *connection, NSCachedURLResponse *cachedResponse);
typedef NSURLRequest * (^CHURLConnectionOperationRedirectResponseBlock)(NSURLConnection *connection, NSURLRequest *request, NSURLResponse *redirectResponse);
typedef void (^CHURLConnectionOperationBackgroundTaskCleanupBlock)();

static inline NSString * CHKeyPathFromOperationState(CHOperationState state) {
    switch (state) {
        case CHOperationReadyState:
            return @"isReady";
        case CHOperationExecutingState:
            return @"isExecuting";
        case CHOperationFinishedState:
            return @"isFinished";
        case CHOperationPausedState:
            return @"isPaused";
        default: {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
            return @"state";
#pragma clang diagnostic pop
        }
    }
}
static dispatch_group_t url_request_operation_completion_group() {
    static dispatch_group_t af_url_request_operation_completion_group;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        af_url_request_operation_completion_group = dispatch_group_create();
    });
    
    return af_url_request_operation_completion_group;
}
static dispatch_queue_t url_request_operation_completion_queue() {
    static dispatch_queue_t af_url_request_operation_completion_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        af_url_request_operation_completion_queue = dispatch_queue_create("com.caohua.networking.operation.queue", DISPATCH_QUEUE_CONCURRENT );
    });
    return af_url_request_operation_completion_queue;
}
static inline BOOL CHStateTransitionIsValid(CHOperationState fromState, CHOperationState toState, BOOL isCancelled) {
    switch (fromState) {
        case CHOperationReadyState:
            switch (toState) {
                case CHOperationPausedState:
                case CHOperationExecutingState:
                    return YES;
                case CHOperationFinishedState:
                    return isCancelled;
                default:
                    return NO;
            }
        case CHOperationExecutingState:
            switch (toState) {
                case CHOperationPausedState:
                case CHOperationFinishedState:
                    return YES;
                default:
                    return NO;
            }
        case CHOperationFinishedState:
            return NO;
        case CHOperationPausedState:
            return toState == CHOperationReadyState;
        default: {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
            switch (toState) {
                case CHOperationPausedState:
                case CHOperationReadyState:
                case CHOperationExecutingState:
                case CHOperationFinishedState:
                    return YES;
                default:
                    return NO;
            }
        }
#pragma clang diagnostic pop
    }
}
@interface CcaoHuaURLConnectionOperation()
@property (readwrite, nonatomic, assign) CHOperationState state;
@property (readwrite, nonatomic, strong) NSRecursiveLock *lock;
@property (readwrite, nonatomic, strong) NSURLConnection *connection;
@property (readwrite, nonatomic, strong) NSURLRequest *request;
@property (readwrite, nonatomic, strong) NSURLResponse *response;
@property (readwrite, nonatomic, strong) NSError *error;
@property (readwrite, nonatomic, strong) NSData *responseData;
@property (readwrite, nonatomic, copy) NSString *responseString;
@property (readwrite, nonatomic, assign) NSStringEncoding responseStringEncoding;
@property (readwrite, nonatomic, assign) long long totalBytesRead;
@property (readwrite, nonatomic, copy) CHURLConnectionOperationBackgroundTaskCleanupBlock backgroundTaskCleanup;
@property (readwrite, nonatomic, copy) CHURLConnectionOperationProgressBlock uploadProgress;
@property (readwrite, nonatomic, copy) CHURLConnectionOperationProgressBlock downloadProgress;
@property (readwrite, nonatomic, copy) CHURLConnectionOperationAuthenticationChallengeBlock authenticationChallenge;
@property (readwrite, nonatomic, copy) CHURLConnectionOperationCacheResponseBlock cacheResponse;
@property (readwrite, nonatomic, copy) CHURLConnectionOperationRedirectResponseBlock redirectResponse;

@end
@implementation CcaoHuaURLConnectionOperation
@synthesize outputStream = _outputStream;
+ (void)networkRequestThreadEntryPoint:(id)__unused object {
    @autoreleasepool {
        [[NSThread currentThread] setName:@"AFNetworking"];
        
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        [runLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
        [runLoop run];
    }
}

+ (NSThread *)networkRequestThread {
    static NSThread *_networkRequestThread = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        _networkRequestThread = [[NSThread alloc] initWithTarget:self selector:@selector(networkRequestThreadEntryPoint:) object:nil];
        [_networkRequestThread start];
    });
    
    return _networkRequestThread;
}
- (instancetype)initWithRequest:(NSURLRequest *)urlRequest {
    NSParameterAssert(urlRequest);
    
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _state = CHOperationReadyState;
    
    self.lock = [[NSRecursiveLock alloc] init];
    self.lock.name = kCHNetworkingLockName;
    
    self.runLoopModes = [NSSet setWithObject:NSRunLoopCommonModes];
    
    self.request = urlRequest;
    self.securityPolicy = [CHSecurityPolicy defaultPolicy];
    self.shouldUseCredentialStorage = YES;
    
    
    return self;
}
- (void)setResponseData:(NSData *)responseData {
    [self.lock lock];
    if (!responseData) {
        _responseData = nil;
    } else {
        _responseData = [NSData dataWithBytes:responseData.bytes length:responseData.length];
    }
    [self.lock unlock];
}

- (NSString *)responseString {
    [self.lock lock];
    if (!_responseString && self.response && self.responseData) {
        self.responseString = [[NSString alloc] initWithData:self.responseData encoding:self.responseStringEncoding];
    }
    [self.lock unlock];
    
    return _responseString;
}

- (NSStringEncoding)responseStringEncoding {
    [self.lock lock];
    if (!_responseStringEncoding && self.response) {
        NSStringEncoding stringEncoding = NSUTF8StringEncoding;
        if (self.response.textEncodingName) {
            CFStringEncoding IANAEncoding = CFStringConvertIANACharSetNameToEncoding((__bridge CFStringRef)self.response.textEncodingName);
            if (IANAEncoding != kCFStringEncodingInvalidId) {
                stringEncoding = CFStringConvertEncodingToNSStringEncoding(IANAEncoding);
            }
        }
        
        self.responseStringEncoding = stringEncoding;
    }
    [self.lock unlock];
    
    return _responseStringEncoding;
}
- (NSInputStream *)inputStream {
    return self.request.HTTPBodyStream;
}

- (void)setInputStream:(NSInputStream *)inputStream {
    NSMutableURLRequest *mutableRequest = [self.request mutableCopy];
    mutableRequest.HTTPBodyStream = inputStream;
    self.request = mutableRequest;
}

- (NSOutputStream *)outputStream {
    if (!_outputStream) {
        self.outputStream = [NSOutputStream outputStreamToMemory];
    }
    
    return _outputStream;
}

- (void)setOutputStream:(NSOutputStream *)outputStream {
    [self.lock lock];
    if (outputStream != _outputStream) {
        if (_outputStream) {
            [_outputStream close];
        }
        
        _outputStream = outputStream;
    }
    [self.lock unlock];
}
- (void)setState:(CHOperationState)state {
    if (!CHStateTransitionIsValid(self.state, state, [self isCancelled])) {
        return;
    }
    
    [self.lock lock];
    NSString *oldStateKey = CHKeyPathFromOperationState(self.state);
    NSString *newStateKey = CHKeyPathFromOperationState(state);
    
    [self willChangeValueForKey:newStateKey];
    [self willChangeValueForKey:oldStateKey];
    _state = state;
    [self didChangeValueForKey:oldStateKey];
    [self didChangeValueForKey:newStateKey];
    [self.lock unlock];
}

- (void)pause {
    if ([self isPaused] || [self isFinished] || [self isCancelled]) {
        return;
    }
    
    [self.lock lock];
    if ([self isExecuting]) {
        [self performSelector:@selector(operationDidPause) onThread:[[self class] networkRequestThread] withObject:nil waitUntilDone:NO modes:[self.runLoopModes allObjects]];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
            [notificationCenter postNotificationName:CHNetworkingOperationDidFinishNotification object:self];
        });
    }
    
    self.state = CHOperationPausedState;
    [self.lock unlock];
}

- (void)operationDidPause {
    [self.lock lock];
    [self.connection cancel];
    [self.lock unlock];
}

- (BOOL)isPaused {
    return self.state == CHOperationPausedState;
}

- (void)resume {
    if (![self isPaused]) {
        return;
    }
    
    [self.lock lock];
    self.state = CHOperationReadyState;
    
    [self start];
    [self.lock unlock];
}

#pragma mark -

- (void)setUploadProgressBlock:(void (^)(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite))block {
    self.uploadProgress = block;
}

- (void)setDownloadProgressBlock:(void (^)(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead))block {
    self.downloadProgress = block;
}

- (void)setWillSendRequestForAuthenticationChallengeBlock:(void (^)(NSURLConnection *connection, NSURLAuthenticationChallenge *challenge))block {
    self.authenticationChallenge = block;
}

- (void)setCacheResponseBlock:(NSCachedURLResponse * (^)(NSURLConnection *connection, NSCachedURLResponse *cachedResponse))block {
    self.cacheResponse = block;
}

- (void)setRedirectResponseBlock:(NSURLRequest * (^)(NSURLConnection *connection, NSURLRequest *request, NSURLResponse *redirectResponse))block {
    self.redirectResponse = block;
}

#pragma mark - NSOperation

- (void)setCompletionBlock:(void (^)(void))block {
    [self.lock lock];
    if (!block) {
        [super setCompletionBlock:nil];
    } else {
        __weak __typeof(self)weakSelf = self;
        [super setCompletionBlock:^ {
            __strong __typeof(weakSelf)strongSelf = weakSelf;
            
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu"
            dispatch_group_t group = strongSelf.completionGroup ?: url_request_operation_completion_group();
            dispatch_queue_t queue = strongSelf.completionQueue ?: dispatch_get_main_queue();
#pragma clang diagnostic pop
            
            dispatch_group_async(group, queue, ^{
                block();
            });
            
            dispatch_group_notify(group, url_request_operation_completion_queue(), ^{
                [strongSelf setCompletionBlock:nil];
            });
        }];
    }
    [self.lock unlock];
}

- (BOOL)isReady {
    return self.state == CHOperationReadyState && [super isReady];
}

- (BOOL)isExecuting {
    return self.state == CHOperationExecutingState;
}

- (BOOL)isFinished {
    return self.state ==  CHOperationFinishedState;
}

- (BOOL)isConcurrent {
    return YES;
}

- (void)start {
    [self.lock lock];
    if ([self isCancelled]) {
        [self performSelector:@selector(cancelConnection) onThread:[[self class] networkRequestThread] withObject:nil waitUntilDone:NO modes:[self.runLoopModes allObjects]];
    } else if ([self isReady]) {
        self.state = CHOperationExecutingState;
        
        [self performSelector:@selector(operationDidStart) onThread:[[self class] networkRequestThread] withObject:nil waitUntilDone:NO modes:[self.runLoopModes allObjects]];
    }
    [self.lock unlock];
}

- (void)operationDidStart {
    [self.lock lock];
    if (![self isCancelled]) {
        self.connection = [[NSURLConnection alloc] initWithRequest:self.request delegate:self startImmediately:NO];
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        for (NSString *runLoopMode in self.runLoopModes) {
            [self.connection scheduleInRunLoop:runLoop forMode:runLoopMode];
            [self.outputStream scheduleInRunLoop:runLoop forMode:runLoopMode];
        }
        
        [self.outputStream open];
        [self.connection start];
    }
    [self.lock unlock];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:CHNetworkingOperationDidStartNotification object:self];
    });
}

- (void)finish {
    [self.lock lock];
    self.state = CHOperationFinishedState;
    [self.lock unlock];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:CHNetworkingOperationDidFinishNotification object:self];
    });
}

- (void)cancel {
    [self.lock lock];
    if (![self isFinished] && ![self isCancelled]) {
        [super cancel];
        
        if ([self isExecuting]) {
            [self performSelector:@selector(cancelConnection) onThread:[[self class] networkRequestThread] withObject:nil waitUntilDone:NO modes:[self.runLoopModes allObjects]];
        }
    }
    [self.lock unlock];
}

- (void)cancelConnection {
    NSDictionary *userInfo = nil;
    if ([self.request URL]) {
        userInfo = @{NSURLErrorFailingURLErrorKey : [self.request URL]};
    }
    NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:userInfo];
    
    if (![self isFinished]) {
        if (self.connection) {
            [self.connection cancel];
            [self performSelector:@selector(connection:didFailWithError:) withObject:self.connection withObject:error];
        } else {
            // Accommodate race condition where `self.connection` has not yet been set before cancellation
            self.error = error;
            [self finish];
        }
    }
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (id)initWithCoder:(NSCoder *)decoder {
    NSURLRequest *request = [decoder decodeObjectOfClass:[NSURLRequest class] forKey:NSStringFromSelector(@selector(request))];
    
    self = [self initWithRequest:request];
    if (!self) {
        return nil;
    }
    
    self.state = (CHOperationState)[[decoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(state))] integerValue];
    self.response = [decoder decodeObjectOfClass:[NSHTTPURLResponse class] forKey:NSStringFromSelector(@selector(response))];
    self.error = [decoder decodeObjectOfClass:[NSError class] forKey:NSStringFromSelector(@selector(error))];
    self.responseData = [decoder decodeObjectOfClass:[NSData class] forKey:NSStringFromSelector(@selector(responseData))];
    self.totalBytesRead = [[decoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(totalBytesRead))] longLongValue];
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [self pause];
    
    [coder encodeObject:self.request forKey:NSStringFromSelector(@selector(request))];
    
    switch (self.state) {
        case CHOperationExecutingState:
        case CHOperationPausedState:
            [coder encodeInteger:CHOperationReadyState forKey:NSStringFromSelector(@selector(state))];
            break;
        default:
            [coder encodeInteger:self.state forKey:NSStringFromSelector(@selector(state))];
            break;
    }
    
    [coder encodeObject:self.response forKey:NSStringFromSelector(@selector(response))];
    [coder encodeObject:self.error forKey:NSStringFromSelector(@selector(error))];
    [coder encodeObject:self.responseData forKey:NSStringFromSelector(@selector(responseData))];
    [coder encodeInt64:self.totalBytesRead forKey:NSStringFromSelector(@selector(totalBytesRead))];
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    CcaoHuaURLConnectionOperation *operation = [(CcaoHuaURLConnectionOperation *)[[self class] allocWithZone:zone] initWithRequest:self.request];
    
    operation.uploadProgress = self.uploadProgress;
    operation.downloadProgress = self.downloadProgress;
    operation.authenticationChallenge = self.authenticationChallenge;
    operation.cacheResponse = self.cacheResponse;
    operation.redirectResponse = self.redirectResponse;
    operation.completionQueue = self.completionQueue;
    operation.completionGroup = self.completionGroup;
    
    return operation;
}

@end
