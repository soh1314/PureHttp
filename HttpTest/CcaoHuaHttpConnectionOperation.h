//
//  CcaoHuaHttpConnectionOperation.h
//  CcaoHuaLogin
//
//  Created by Weep Yan on 16/8/30.
//  Copyright © 2016年 Ice_Rin Liu. All rights reserved.
//

#import "CcaoHuaURLConnectionOperation.h"
#import "CHURLResponseSerialization.h"

@interface CcaoHuaHttpConnectionOperation : CcaoHuaURLConnectionOperation
@property (readonly, nonatomic, strong, nullable) NSHTTPURLResponse *response;


@property (nonatomic, strong) CHHTTPResponseSerializer <CHURLResponseSerialization> * responseSerializer;


@property (readonly, nonatomic, strong, nullable) id responseObject;


- (void)setCompletionBlockWithSuccess:(nullable void (^)(CcaoHuaHttpConnectionOperation *operation, id responseObject))success
                              failure:(nullable void (^)(CcaoHuaHttpConnectionOperation *operation, NSError *error))failure;
@end
