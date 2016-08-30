//
//  CcaoHuaHttpManager.m
//  CcaoHuaLogin
//
//  Created by Weep Yan on 16/8/30.
//  Copyright © 2016年 Ice_Rin Liu. All rights reserved.
//

#import "CcaoHuaHttpManager.h"
#import <Availability.h>
#import <Security/Security.h>

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
#import <UIKit/UIKit.h>
#endif
@interface CcaoHuaHttpManager ()
@property (readwrite, nonatomic, strong) NSURL *baseURL;
@end
@implementation CcaoHuaHttpManager
+ (instancetype)manager {
    return [[self alloc] initWithBaseURL:nil];
}

- (instancetype)init {
    return [self initWithBaseURL:nil];
}

- (instancetype)initWithBaseURL:(NSURL *)url {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    // Ensure terminal slash for baseURL path, so that NSURL +URLWithString:relativeToURL: works as expected
    if ([[url path] length] > 0 && ![[url absoluteString] hasSuffix:@"/"]) {
        url = [url URLByAppendingPathComponent:@""];
    }
    
    self.baseURL = url;
    
    self.requestSerializer = [CHHTTPRequestSerializer serializer];
    self.responseSerializer = [CHJSONResponseSerializer serializer];
    
    self.securityPolicy = [CHSecurityPolicy defaultPolicy];
    
    self.reachabilityManager = [CHNetworkReachabilityManager sharedManager];
    
    self.operationQueue = [[NSOperationQueue alloc] init];
    
    self.shouldUseCredentialStorage = YES;
    
    return self;
}

#pragma mark -

#ifdef _SYSTEMCONFIGURATION_H
#endif

- (void)setRequestSerializer:(CHHTTPRequestSerializer <CHURLRequestSerialization> *)requestSerializer {
    NSParameterAssert(requestSerializer);
    
    _requestSerializer = requestSerializer;
}

- (void)setResponseSerializer:(CHHTTPResponseSerializer <CHURLResponseSerialization> *)responseSerializer {
    NSParameterAssert(responseSerializer);
    
    _responseSerializer = responseSerializer;
}

#pragma mark -

- (CcaoHuaHttpConnectionOperation *)HTTPRequestOperationWithHTTPMethod:(NSString *)method
                                                     URLString:(NSString *)URLString
                                                    parameters:(id)parameters
                                                       success:(void (^)(CcaoHuaHttpConnectionOperation *operation, id responseObject))success
                                                       failure:(void (^)(CcaoHuaHttpConnectionOperation *operation, NSError *error))failure
{
    NSError *serializationError = nil;
    NSMutableURLRequest *request = [self.requestSerializer requestWithMethod:method URLString:[[NSURL URLWithString:URLString relativeToURL:self.baseURL] absoluteString] parameters:parameters error:&serializationError];
    if (serializationError) {
        if (failure) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu"
            dispatch_async(self.completionQueue ?: dispatch_get_main_queue(), ^{
                failure(nil, serializationError);
            });
#pragma clang diagnostic pop
        }
        
        return nil;
    }
    
    return [self HTTPRequestOperationWithRequest:request success:success failure:failure];
}
- (CcaoHuaHttpConnectionOperation *)HTTPRequestOperationWithRequest:(NSURLRequest *)request
                                                    success:(void (^)(CcaoHuaHttpConnectionOperation *operation, id responseObject))success
                                                    failure:(void (^)(CcaoHuaHttpConnectionOperation *operation, NSError *error))failure
{
    CcaoHuaHttpConnectionOperation *operation = [[CcaoHuaHttpConnectionOperation alloc] initWithRequest:request];
    operation.responseSerializer = self.responseSerializer;
    operation.shouldUseCredentialStorage = self.shouldUseCredentialStorage;
    operation.credential = self.credential;
    operation.securityPolicy = self.securityPolicy;
    
    [operation setCompletionBlockWithSuccess:success failure:failure];
    operation.completionQueue = self.completionQueue;
    operation.completionGroup = self.completionGroup;
    
    return operation;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (id)initWithCoder:(NSCoder *)decoder {
    NSURL *baseURL = [decoder decodeObjectForKey:NSStringFromSelector(@selector(baseURL))];
    
    self = [self initWithBaseURL:baseURL];
    if (!self) {
        return nil;
    }
    
    self.requestSerializer = [decoder decodeObjectOfClass:[CHHTTPRequestSerializer class] forKey:NSStringFromSelector(@selector(requestSerializer))];
    self.responseSerializer = [decoder decodeObjectOfClass:[CHHTTPResponseSerializer class] forKey:NSStringFromSelector(@selector(responseSerializer))];
    CHSecurityPolicy *decodedPolicy = [decoder decodeObjectOfClass:[CHSecurityPolicy class] forKey:NSStringFromSelector(@selector(securityPolicy))];
    if (decodedPolicy) {
        self.securityPolicy = decodedPolicy;
    }
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.baseURL forKey:NSStringFromSelector(@selector(baseURL))];
    [coder encodeObject:self.requestSerializer forKey:NSStringFromSelector(@selector(requestSerializer))];
    [coder encodeObject:self.responseSerializer forKey:NSStringFromSelector(@selector(responseSerializer))];
    [coder encodeObject:self.securityPolicy forKey:NSStringFromSelector(@selector(securityPolicy))];
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    CcaoHuaHttpManager *HTTPClient = [[[self class] allocWithZone:zone] initWithBaseURL:self.baseURL];
    
    HTTPClient.requestSerializer = [self.requestSerializer copyWithZone:zone];
    HTTPClient.responseSerializer = [self.responseSerializer copyWithZone:zone];
    HTTPClient.securityPolicy = [self.securityPolicy copyWithZone:zone];
    
    return HTTPClient;
}
@end
