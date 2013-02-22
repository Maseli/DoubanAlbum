//
//  DoubanAuthEngine.m
//  
//
//  Created by Tonny on 12-12-9.
//
//

#import "DoubanAuthEngine.h"
#import "SINGLETONGCD.h"
#import "DOUOAuthStore.h"
#import "DOUOAuthService.h"

@implementation DoubanAuthEngine

SINGLETON_GCD(DoubanAuthEngine)

- (id)init
{
    self = [super init];
    if (self) {
        _appClientId = kDouban_API_Key;
        _appClientSecret = kDouban_API_Secret;
    }
    return self;
}

#pragma mark - Helper

+ (NSUInteger)currentUserId{
    // 判断DoubanAuth是否有效
    if ([[DoubanAuthEngine sharedDoubanAuthEngine] isValid]) {
        // 获得DOUOAuthStore实例
        DOUOAuthStore *store = [DOUOAuthStore sharedInstance];
        // 返回userId
        return store.userId;
    }
    return NSNotFound;
}


#pragma mark - OAuth

/* 判断DoubanAuth是否有效 */
- (BOOL)isValid {
    DOUOAuthStore *store = [DOUOAuthStore sharedInstance];
    if (store.accessToken) {
        // 判断当前时间是否失效
        BOOL isValid = ![store hasExpired];
        
        SLLog(@"Auth isValid %@", isValid?@"YES":@"NO");
        return isValid;
    }
    
    SLLog(@"Auth isValid NO");
    return NO;
}

+ (NSError *)executeRefreshToken {
    DOUOAuthService *service = [DOUOAuthService sharedInstance];
    service.authorizationURL = kTokenUrl;
    
    return [service validateRefresh];
}

//check if necessory refresh access token before each request,  sync
+ (void)checkRefreshToken{
    DOUOAuthStore *store = [DOUOAuthStore sharedInstance];
    if (store.userId != 0 && store.refreshToken && [store shouldRefreshToken]) {
        [self executeRefreshToken];
    }
}

@end
