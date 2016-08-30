//
//  CcaoHuaURLConnectionOperation.h
//  CcaoHuaLogin
//
//  Created by Weep Yan on 16/8/30.
//  Copyright © 2016年 Ice_Rin Liu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CHSecurityPolicy.h"
@interface CcaoHuaURLConnectionOperation : NSOperation<NSURLConnectionDelegate, NSURLConnectionDataDelegate, NSSecureCoding, NSCopying>

@property (nonatomic, strong) NSSet *runLoopModes;

@property (readonly, nonatomic, strong) NSURLRequest *request;
@property (readonly, nonatomic, strong, nullable) NSURLResponse *response;
@property (readonly, nonatomic, strong, nullable) NSError *error;
@property (readonly, nonatomic, strong, nullable) NSData *responseData;
@property (readonly, nonatomic, copy, nullable) NSString *responseString;
@property (readonly, nonatomic, assign) NSStringEncoding responseStringEncoding;
@property (nonatomic, assign) BOOL shouldUseCredentialStorage;
@property (nonatomic, strong, nullable) NSURLCredential *credential;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong, nullable) NSOutputStream *outputStream;
@property (nonatomic, strong) CHSecurityPolicy *securityPolicy;
#if OS_OBJECT_USE_OBJC
@property (nonatomic, strong, nullable) dispatch_queue_t completionQueue;
#else
@property (nonatomic, assign, nullable) dispatch_queue_t completionQueue;
#endif

#if OS_OBJECT_USE_OBJC
@property (nonatomic, strong, nullable) dispatch_group_t completionGroup;
#else
@property (nonatomic, assign, nullable) dispatch_group_t completionGroup;
#endif
- (instancetype)initWithRequest:(NSURLRequest *)urlRequest;
- (void)pause;
- (BOOL)isPaused;
- (void)resume;
@end
