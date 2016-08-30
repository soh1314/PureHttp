//
//  CcaoHuaHttpManager.h
//  CcaoHuaLogin
//
//  Created by Weep Yan on 16/8/30.
//  Copyright © 2016年 Ice_Rin Liu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CHURLRequestSerialization.h"
#import "CHURLResponseSerialization.h"
#import "CHSecurityPolicy.h"
#import "CHNetworkReachabilityManager.h"
#import "CcaoHuaHttpConnectionOperation.h"
@interface CcaoHuaHttpManager : NSObject <NSSecureCoding, NSCopying>
@property (readonly, nonatomic, strong, nullable) NSURL *baseURL;


@property (nonatomic, strong) CHHTTPRequestSerializer <CHURLRequestSerialization> * requestSerializer;


@property (nonatomic, strong) CHHTTPResponseSerializer <CHURLResponseSerialization> * responseSerializer;

@property (nonatomic, strong) NSOperationQueue *operationQueue;

@property (nonatomic, assign) BOOL shouldUseCredentialStorage;


@property (nonatomic, strong, nullable) NSURLCredential *credential;


@property (nonatomic, strong) CHSecurityPolicy *securityPolicy;


@property (readwrite, nonatomic, strong) CHNetworkReachabilityManager *reachabilityManager;


#if OS_OBJECT_USE_OBJC
@property (nonatomic, strong, nullable) dispatch_queue_t completionQueue;
#else
@property (nonatomic, assign, nullable) dispatch_queue_t completionQueue;
#endif

/**
 The dispatch group for the `completionBlock` of request operations. If `NULL` (default), a private dispatch group is used.
 */
#if OS_OBJECT_USE_OBJC
@property (nonatomic, strong, nullable) dispatch_group_t completionGroup;
#else
@property (nonatomic, assign, nullable) dispatch_group_t completionGroup;
#endif


+ (instancetype)manager;


- (instancetype)initWithBaseURL:(nullable NSURL *)url NS_DESIGNATED_INITIALIZER;
- (CcaoHuaHttpConnectionOperation *)HTTPRequestOperationWithRequest:(NSURLRequest *)request
                                                    success:(nullable void (^)(CcaoHuaHttpConnectionOperation *operation, id responseObject))success
                                                    failure:(nullable void (^)(CcaoHuaHttpConnectionOperation *operation, NSError *error))failure;
@end
