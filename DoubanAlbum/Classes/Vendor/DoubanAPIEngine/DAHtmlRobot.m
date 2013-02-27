//
//  DAHtmlRobot.m
//  DoubanAlbum
//
//  Created by Tonny on 12-12-10.
//  Copyright (c) 2012年 SlowsLab. All rights reserved.
//

#import "DAHtmlRobot.h"
#import "SINGLETONGCD.h"
#import "GCDHelper.h"
#import "NSStringAddition.h"
#import "JSONKit.h"
#import "DAHttpClient.h"

static NSInteger const CacheMaxCacheAge = 60*60*24*1; // 5 days, it's safe within 5 days, not been clean when cleanM

static NSString * const kDoubanAlbumDataPath = @"DoubanAlbumData";
static NSString * const kPhotosInAlbumPath = @"PhotosInAlbum";
static NSString * const kUserAlbumPath = @"AlbumsForUser";

//相册 url
NSString * const kPhotosInAlbumUrlFomater = @"pa_urlformater"; //@"http://www.douban.com/photos/album/%@?start=%d",
NSString * const kPhotosInAlbumCountPerPage = @"pa_cperpage";//18
//相册 照片Id
static NSString * const kPhotosIdInAlbumExpression = @"pa_id_express";//http://www.douban.com/photos/photo/[0-9]*/
//相册 相册描述
static NSString * const kAlbumDescribeExpression = @"pa_de_express";//<div id=\"link-report\" class=\"pl\" style=\"padding-bottom:30px\">

///////////////////////////////////////////////////

//相册集 url
static NSString * const kUserAlbumUrlFomater = @"ua_urlfomater"; //http://www.douban.com/people/%@/photos?start=%d
static NSString * const kUserAlbumCountPerPage = @"ua_cperpage"; //16
//相册集 相册id
static NSString * const kUserAlbumIdExpression = @"ua_id_express"; //http://www.douban.com/photos/album/[0-9]*/
//相册集 相册封面
static NSString * const kAlbumCoverInUserAlbumsExpression = @"uac_express";//<img class=\"album\" src=\"http://
//相册集 相册名字
static NSString * const kAlbumNameInUserAlbumsExpress = @"ua_name_express"; //<a href=\"http://www.douban.com/photos/album/%@/\">

static NSDictionary *RobotCommands_Default;
static NSMutableDictionary *RobotCommands;

@implementation DAHtmlRobot

SINGLETON_GCD(DAHtmlRobot)

+ (void)initialize{
    if (self == [DAHtmlRobot class]) {
        [self initialCacheFolder];
        
        RobotCommands_Default = @{
            kPhotosIdInAlbumExpression:@"http://www.douban.com/photos/photo/[0-9]*/",
            kAlbumDescribeExpression:@"<div id=\"link-report\" class=\"pl\" style=\"padding-bottom:30px\">",
            kUserAlbumIdExpression:@"http://www.douban.com/photos/album/[0-9]*/",
            kAlbumCoverInUserAlbumsExpression:@"<img class=\"album\" src=\"http://",
        
            kUserAlbumUrlFomater:@"http://www.douban.com/people/%@/photos?start=%d",
            kPhotosInAlbumUrlFomater:@"http://www.douban.com/photos/album/%@?start=%d",
        
            kAlbumNameInUserAlbumsExpress:@"<a href=\"http://www.douban.com/photos/album/%@/\">",
        
            kUserAlbumCountPerPage:@(16),
            kPhotosInAlbumCountPerPage:@(18)
        };
    }
}

+ (void)setRobotCommands:(NSDictionary *)dic{
    SLLog(@"dic %@", dic);
    
    if (dic.count == RobotCommands_Default.count) {
        RobotCommands = [NSMutableDictionary dictionaryWithDictionary:dic];
        
        NSString *httpString = @"http___3ww.";
        [dic enumerateKeysAndObjectsUsingBlock:^(id key, NSString *obj, BOOL *stop) {
            NSMutableString *muObj = [NSMutableString stringWithString:obj];;
            
            NSRange range = [obj rangeOfString:httpString];
            if (range.location != NSNotFound) {
                muObj = [NSMutableString stringWithString:obj];
                [muObj replaceCharactersInRange:range withString:@"http://www."];
            }
        
            range = [muObj rangeOfString:@"&lt;"];
            while (range.location != NSNotFound) {
                [muObj replaceCharactersInRange:range withString:@"<"];
                range = [muObj rangeOfString:@"&lt;"];
            }
            
            range = [muObj rangeOfString:@"&gt;"];
            while (range.location != NSNotFound) {
                [muObj replaceCharactersInRange:range withString:@">"];
                range = [muObj rangeOfString:@"&gt;"];
            }
            
            RobotCommands[key] = muObj;
        }];
        
        SLLog(@"RobotCommands %@", RobotCommands);
    }
}

+ (NSString *)commandFor:(NSString *)key{
    if (RobotCommands) {
        return RobotCommands[key];
    }else{
        return RobotCommands_Default[key];
    }
}

+ (void)initialCacheFolder{
    [GCDHelper dispatchBlock:^{
        NSString *categoryPath = [APP_CACHES_PATH stringByAppendingPathComponent:kDoubanAlbumDataPath];
        
        NSFileManager *manager = [NSFileManager defaultManager];
        if (![manager fileExistsAtPath:categoryPath])
        {
            [manager createDirectoryAtPath:categoryPath
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:NULL];
        }
        
        NSString *photoListInAlbumCachePath = [APP_CACHES_PATH stringByAppendingPathComponent:kPhotosInAlbumPath];
        
        if (![manager fileExistsAtPath:photoListInAlbumCachePath])
        {
            [manager createDirectoryAtPath:photoListInAlbumCachePath
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:NULL];
        }
        
        NSString *albumListForUserCachePath = [APP_CACHES_PATH stringByAppendingPathComponent:kUserAlbumPath];
        if (![manager fileExistsAtPath:albumListForUserCachePath])
        {
            [manager createDirectoryAtPath:albumListForUserCachePath
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:NULL];
        }
    } completion:^{
        [self cleanOuttimeImageInDisk];
    }];
}

+ (NSOperationQueue *)sharedOperationQueue {
    static NSOperationQueue *_operationQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _operationQueue = [[NSOperationQueue alloc] init];
        [_operationQueue setMaxConcurrentOperationCount:NSOperationQueueDefaultMaxConcurrentOperationCount];
    });
    
    return _operationQueue;
}

+ (void)requestCategoryLocalData:(SLDictionaryBlock)localBolck completion:(SLDictionaryBlock)completion{
    
    if (localBolck) {
        localBolck([self latestDoubanAlbumData]);
    }
//    NSString *path = [[NSBundle mainBundle] pathForResource:@"DoubanAlbumData_Local" ofType:@"plist"];
//    
//    NSDictionary *dic = [NSDictionary dictionaryWithContentsOfFile:path];
//    completion(dic);
//#warning  
//    return;
    
    static NSString *url  = @"http://www.douban.com/note/251470569/";
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:[self sharedOperationQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                               __block BOOL needUpdateView = YES;
                               __block id result = nil;
                               [GCDHelper dispatchBlock:^{
                                   NSString *resultString = nil;
                                   if (error == nil) {
                                       NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                                       NSRange startR = [html rangeOfString:@"---start---"];
                                       NSRange endR = [html rangeOfString:@"---end---"];
                                       
                                       if (startR.location != NSNotFound && endR.location != NSNotFound) {
                                           NSUInteger start = startR.location+startR.length;
                                           NSString *content = [html substringWithRange:NSMakeRange(start, endR.location-start)];
                                           
                                           NSMutableString *muString = [NSMutableString stringWithString:content];
                                           
                                           NSRange range = [muString rangeOfString:@"&quot;"];
                                           while (range.location != NSNotFound) {
                                               [muString replaceCharactersInRange:range withString:@"\""];
                                               range = [muString rangeOfString:@"&quot;"];
                                           }
                                           
                                           SLLog(@"content %@", muString);
                                           
                                           resultString = muString;
                                       }
                                   }
                                   
                                   if (resultString == nil) {
                                       NSString *path = [[NSBundle mainBundle] pathForResource:@"DoubanAlbumData_Local" ofType:@"plist"];
                                       result = [NSDictionary dictionaryWithContentsOfFile:path];
                                   }else{
                                       result = [resultString objectFromJSONString];
                                       
                                       if ([result count] > 0) {
                                           needUpdateView = [self cacheDoubanAlbumData:result];
                                       }
                                   }
                               } completion:^{
                                   NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithDictionary:result];
                                   dic[@"needUpdateView"] = @(needUpdateView);
                                   
                                   completion(dic);
                               }];
                           }];

}

+ (void) photosInAlbum:(NSUInteger)albumId start:(NSUInteger)start completion:(SLDictionaryBlock)completion{
    [self dataWithDataType:DoubanDataTypePhotosInAlbum
                  userName:nil
                   albumId:albumId
                     start:start
                completion:^(id dic) {
                    completion(dic);
                }];
}

+ (void)userAlbumsWithUserName:(NSString *)userName start:(NSUInteger)start completion:(SLArrayBlock)completion{
    [self dataWithDataType:DoubanDataTypeAlbumsForUser
                  userName:userName
                   albumId:0
                     start:start
                completion:^(id array) {
                    completion(array);
                }];
}

/* 根据条件抓取网页数据,然后写入到 */
+ (void)dataWithDataType:(DoubanDataType)dataType userName:(NSString *)userName albumId:(NSUInteger)albumId start:(NSUInteger)start completion:(SLObjectBlock)completion{
    NSString *fomatter = nil;
    NSUInteger countPerPage = 0;
    NSString *target = nil;

    // 这里根据类型的不同,其实只有两种,无非是相册列表和相片列表,抓相册列表的数据需要有people的userName,抓相片列表的数据需要有相册的albumId
    if (dataType == DoubanDataTypeAlbumsForUser) { //用户相册列表
        // 设置URL的格式
        fomatter = [self commandFor:kUserAlbumUrlFomater];
        // 设置单页显示多数相册——16个
        countPerPage = [[self commandFor:kUserAlbumCountPerPage] integerValue];
        
        target = userName;
    }else if (dataType == DoubanDataTypePhotosInAlbum) { ////相册图片
        // 设置URL的格式
        fomatter = [self commandFor:kPhotosInAlbumUrlFomater];
        // 设置单页显示多少照片——18个
        countPerPage = [[self commandFor:kPhotosInAlbumCountPerPage] integerValue];
        
        target = [@(albumId) description];
    }
        
    [self cachedDataWithAlbumId:albumId
                       userName:userName
                          start:start
                     completion:^(id dic) {
                         // 这个dic是之前程序异步从CACHE中取的一些数据(相册或者照片)
                         NSUInteger count = 0;
                         if (dataType == DoubanDataTypePhotosInAlbum){
                             count = [[dic valueForKey:@"photoIds"] count];
                         }else{
                             count = [dic count];
                         }
                         
                         // 
                         if (count == countPerPage) {
                             completion(dic);
                         }else{
                             // 根据格式拼好一个URL链接
                             NSString *url = [NSString stringWithFormat:fomatter, target, start];
                             
                             SLLog(@"url %@", url);
                             
                             // 显示网络请求指示图标
                             [DAHttpClient incrementActivityCount];
                             // 创建URLRequest
                             NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
                             [NSURLConnection sendAsynchronousRequest:request
                                                                queue:[self sharedOperationQueue]
                                                    completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                                                    // 取消显示网络请求指示图标
                                                        [DAHttpClient decrementActivityCount];
                                                    // 如果没有报错
                                                        if (error == nil) {
                                                            __block id results = nil;
                                                            [GCDHelper dispatchBlock:^{
                                                                if (dataType == DoubanDataTypePhotosInAlbum){
                                                    // 声明一个存储解析结果的Map
                                                        results = [NSMutableDictionary dictionaryWithCapacity:2];
                                                                    // 从请求获取的data中解析数据
                                                                    [self analysePhotosInAlbumWithData:data withResults:results express:[self commandFor:kPhotosIdInAlbumExpression]];
                                                                    // 在CACHE路径写plist存results[@"photoIds"]
                                                                    [self cacheData:results[@"photoIds"] forUser:nil forAlbum:albumId start:start];
                                                                    
                                                                    NSString *des = results[Key_Album_Describe];
                                                                    if (des.length > 0) {
                                                                        // 把描述写到CACHE的plist文件中
                                                                        [DAHtmlRobot cacheAlbumDescribe:des forAlbum:albumId];
                                                                    }
                                                                }else{
                                                                    // 用户相册列表
                                                                    results = [NSMutableArray arrayWithCapacity:countPerPage];
                                                                    // 从请求获取的data中解析数据
                                                                    [self analyseUserAlbumsWithData:data withResults:results];
                                                                    // 在CACHE路径写plist存results
                                                                    [self cacheData:results forUser:userName forAlbum:0 start:start];
                                                                }
                                                            } completion:^{
                                                                completion(results);
                                                            }];
                                                        }else{
                                                    // 如果请求失败
                                                            dispatch_async(dispatch_get_main_queue(), ^{
                                                                completion(nil);
                                                            });
                                                        }
                                                    }];
                         }
                     }];
}

/* 使用正则分析网页抓回的数据(HTML),得到照片的id集合以及介绍文字 */
+ (void)analysePhotosInAlbumWithData:(NSData *)data withResults:(NSMutableDictionary *)results express:(NSString *)express{
    
    NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    // MYDEBUG
    NSLog(@"HTML: %@",html);
    
    NSError *err;
    // 声明正则表达式
    NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern:express options:NSRegularExpressionCaseInsensitive error:&err];
    // 如果正则成功实例化
    if (err == nil) {
        // 匹配相册id或照片id
        NSArray *matches = [regex matchesInString:html options:0 range:NSMakeRange(0, [html length])];
        
        NSMutableArray *photoIds = [NSMutableArray arrayWithCapacity:matches.count];
        for (NSTextCheckingResult *result in matches) {
            // express参数示例:http://www.douban.com/photos/photo/[0-9]*/
            // 这个是为了定位活动参数在express里所处的相对位置
            NSUInteger preL = [express rangeOfString:@"[0"].location;
            
            // 根据result的结果位置与相对位置求和,得到活动参匹配到结果的location
            // 再等到那个参数对应结果的length,最后-1是为了去掉结尾的'/'符号只保留数字
            NSString *photo = [html substringWithRange:NSMakeRange(result.range.location+preL, result.range.length-preL-1)];
            // 如果当前的id集合中没有这个id,就添加到id集合中
            if (![photoIds containsObject:photo]) {
                [photoIds addObject:photo];
            }
        }
        
        results[@"photoIds"] = photoIds;
    }
    
    ////////抓 相册描述
    // 声明正则
    regex = [[NSRegularExpression alloc] initWithPattern:[self commandFor:kAlbumDescribeExpression]
                                                 options:NSRegularExpressionCaseInsensitive
                                                   error:&err];
    if (err == nil) {
        // 如果声明成功,匹配相册描述
        NSArray *matches = [regex matchesInString:html options:NSMatchingReportCompletion range:NSMakeRange(0, [html length])];
        // 貌似这OC没有泛型,取匹配到的最后一个结果
        NSTextCheckingResult *result = [matches lastObject];
        if (result) {
            // start是匹配到的结果之后的第一个字符,所以+length
            NSUInteger start = result.range.location+result.range.length;
            
            // 在start之后一个字符开始到结尾搜</div>,返回第一个结果的location
            NSUInteger end = [html rangeOfString:@"</div>" options:0 range:NSMakeRange(start, html.length-start-1)].location;
            
            // 计算描述串的长度,按照位置取出描述内容
            NSString *describe = [html substringWithRange:NSMakeRange(start, end-start)];
            // 设置相册描述
            results[Key_Album_Describe] = describe;
        }
    }
    
    SLLog(@"count %d \n%@ %@", [results count], @"photos", results);
}

/* 使用正则分析网页抓回的数据(HTML),得到相册的封面图片id、名称 */
+ (void)analyseUserAlbumsWithData:(NSData *)data withResults:(NSMutableArray *)results{
    NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    NSError *err;
    NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern:[self commandFor:kUserAlbumIdExpression] options:NSRegularExpressionCaseInsensitive error:&err];
    if (err == nil) {
        NSArray *matches = [regex matchesInString:html options:0 range:NSMakeRange(0, [html length])];
        
        NSMutableArray *temAlbum = [NSMutableArray arrayWithCapacity:matches.count];
        
        NSUInteger preL = [[self commandFor:kUserAlbumIdExpression] rangeOfString:@"[0"].location;
        // 迭代结果,分析
        for (NSTextCheckingResult *result0 in matches) {
            NSString *albumId = [html substringWithRange:NSMakeRange(result0.range.location+preL, result0.range.length-preL-1)];
            // 如果这个相册的id不存在,获取其id、封面地址、相册名字信息放入返回的结果集
            if (![temAlbum containsObject:albumId]) {
                [temAlbum addObject:albumId];
                
                NSMutableDictionary *albumDic = [NSMutableDictionary dictionaryWithCapacity:3];
                albumDic[Key_Album_Id] = albumId;
                
                ////////相册封面
                NSString *albumCoverE = [self commandFor:kAlbumCoverInUserAlbumsExpression];
                NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern:albumCoverE options:NSRegularExpressionCaseInsensitive error:&err];
                NSUInteger start = result0.range.location+result0.range.length;
                NSArray *matches = [regex matchesInString:html options:NSMatchingReportCompletion range:NSMakeRange(start, [html length]-start-1)];
                if (matches.count > 0) {
                    NSTextCheckingResult *result = [matches objectAtIndex:0];
                    NSRange range = result.range;
                    
                    NSRange range2 = [html rangeOfString:@"\"/></a>" options:0 range:NSMakeRange(range.location, html.length-range.location-1)]; //
                    
                    NSString *albumCover = [html substringWithRange:NSMakeRange(range.location+range.length, range2.location-range.location-range.length)];
                    
                    ///私有相册 访问不到图片
                    if ([albumCover containString:@"otho.douban"]) {
                        NSArray *array = [albumCover componentsSeparatedByString:@"/"];
                        NSString *lastString = [array lastObject];
                        if ([lastString containString:@".jpg"]) {
                            albumCover = [NSString stringWithFormat:@"img3.douban.com/view/photo/albumcover/public/p%@", [lastString substringFromIndex:1]];
                        }
                    }
                    
                    albumDic[Key_Album_Cover] = albumCover;
                }
                
                ////////相册名字
                NSString *nameExpress = [NSString stringWithFormat:[self commandFor:kAlbumNameInUserAlbumsExpress], albumId];
                regex = [[NSRegularExpression alloc] initWithPattern:nameExpress
                                                             options:NSRegularExpressionCaseInsensitive
                                                               error:&err];
                start = result0.range.location+result0.range.length;
                matches = [regex matchesInString:html options:NSMatchingReportCompletion range:NSMakeRange(start, [html length]-start-1)];
                if (matches.count > 0) {
                    NSTextCheckingResult *result = [matches objectAtIndex:0];
                    
                    start = result.range.location+result.range.length;
                    NSRange endRange = [html rangeOfString:@"</a>" options:0 range:NSMakeRange(start, html.length-start-1)];
                    NSString *albumName = [html substringWithRange:NSMakeRange(start, endRange.location-start)];
                    albumDic[Key_Album_Name] = albumName;
                }
                
                [results addObject:albumDic];
            }
        }
    }
    
    SLLog(@"count %d \n%@ %@", [results count], @"albums", results);
}

@end


@implementation DAHtmlRobot (Cache)

+ (NSDictionary *)latestDoubanAlbumData{
    NSString *latestDataVersion = [USER_DEFAULT objectForKey:@"Key_Latest_Data_Version"];
    
    NSDictionary *dic = nil;
//#warning 
    if (latestDataVersion) {
        NSString *cacheFolderPath = [APP_CACHES_PATH stringByAppendingPathComponent:kDoubanAlbumDataPath];
        NSString *path = [NSString stringWithFormat:@"%@/%@.plist", cacheFolderPath, latestDataVersion];
        
        dic = [NSDictionary dictionaryWithContentsOfFile:path];
    }
    
    if (!dic) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"DoubanAlbumData_Local" ofType:@"plist"];
        dic = [NSDictionary dictionaryWithContentsOfFile:path];
    }
    
    return dic;
}

+ (BOOL)cacheDoubanAlbumData:(NSDictionary *)result{
    NSString *newDataVersion = result[@"data_version"];
    NSString *latestDataVersion = [USER_DEFAULT objectForKey:@"Key_Latest_Data_Version"];
    if ([newDataVersion compare:latestDataVersion] != NSOrderedSame) {
        NSString *cacheFolderPath = [APP_CACHES_PATH stringByAppendingPathComponent:kDoubanAlbumDataPath];
        NSString *path = [NSString stringWithFormat:@"%@/%@.plist", cacheFolderPath, newDataVersion];
        [result writeToFile:path atomically:YES];
        
        [USER_DEFAULT setObject:newDataVersion forKey:@"Key_Latest_Data_Version"];
        [USER_DEFAULT synchronize];
        
        return YES;
    }
    
    return NO;
}

////用户相册列表
+ (void)cachedAlbumsForUser:(NSString *)userName start:(NSUInteger)start completion:(SLArrayBlock)completion{
    [self cachedDataWithAlbumId:0
                        userName:userName
                           start:start
                      completion:completion];
}

+ (void)cacheAlbums:(NSArray *)albums forUser:(NSString *)userName start:(NSUInteger)start{
    [self cacheData:albums forUser:userName forAlbum:0 start:start];
}

////相册图片
+ (void)cachedPhotosForAlbum:(NSUInteger)albumId start:(NSUInteger)start completion:(SLArrayBlock)completion{
    [self cachedDataWithAlbumId:albumId
                        userName:nil
                           start:start
                      completion:completion];
}

+ (void)cachePhotos:(NSArray *)photos forAlbum:(NSUInteger)albumId start:(NSUInteger)start{
    [self cacheData:photos forUser:nil forAlbum:albumId start:start];
}

+ (void)cachedDataWithAlbumId:(NSUInteger)albumId userName:(NSString *)userName start:(NSUInteger)start completion:(SLObjectBlock)completion{
    NSString *fomatter = nil;
    NSString *fileName = nil;
    NSUInteger countPerPage = 0;
    if (userName) { //用户相册列表
        fomatter = kUserAlbumPath;
        fileName = userName;
        countPerPage = [[self commandFor:kUserAlbumCountPerPage] integerValue];
    }else{ //相册图片
        fomatter = kPhotosInAlbumPath;
        fileName = [@(albumId) description];
        countPerPage = [[self commandFor:kPhotosInAlbumCountPerPage] integerValue];
    }
    
    // 从CACHE的plist取出数据写结果,可能是相册集合或者是照片集合
    __block NSMutableArray *results = nil;
    // 从CACHE的plist取出相册描述信息
    __block NSString *albumDescribe = nil;
    // 一些异步代码
    [GCDHelper dispatchBlock:^{
        
        /************ 先是一个从CACHE中取数据的过程 ************/
        
        NSString *photoListInAlbumCachePath = [APP_CACHES_PATH stringByAppendingPathComponent:fomatter];
        NSString *path = [NSString stringWithFormat:@"%@/%@.plist", photoListInAlbumCachePath, fileName];
        
        NSMutableDictionary *orginDic = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
        
        // 计算迭代次数,最多为一页的额定数量(视类型定)
        NSUInteger loop = MIN(countPerPage, orginDic.count);
        // 创建结果集,每迭代一个数据
        results = [NSMutableArray arrayWithCapacity:loop];
        
        SLLog(@"读取 %@ %@ start %d count %d", userName?@"userAlbum":[NSString stringWithFormat:@"album %d", albumId], userName?userName:[@(albumId) description], start, loop);
        
        // 从start的index开始取数据,写结果集
        int i;
        for (i = 0; i < loop; i++) {
            id photoId = [orginDic objectForKey:[@(i+start) description]];
            if (!photoId) return ;
            
            [results addObject:photoId];
        }
        
        // 如果是加载相册中图片的话,取相册描述的相关信息
        if (albumId) {
            albumDescribe = [orginDic objectForKey:Key_Album_Describe];
        }
    } completion:^{
        /********** 获取完数据这些结果需要传递到下一步 **********/
        if (albumId) {
            // 如果是照片集合(一个相册),
            NSMutableDictionary *muDic = [@{@"photoIds":results} mutableCopy];
            if (albumDescribe.length > 0) {
                muDic[Key_Album_Describe] = albumDescribe;
            }
            // 传递拷贝了的一份结果
            completion(muDic);
        }else{
            completion(results);
        }
    }];
}

/* 将相册描述写到CACHE的plist文件中 */
+ (void)cacheAlbumDescribe:(NSString *)des forAlbum:(NSUInteger)albumId{
    // 找到CACHE下对应目录的路径
    NSString *photoListInAlbumCachePath = [APP_CACHES_PATH stringByAppendingPathComponent:kPhotosInAlbumPath];
    NSString *path = [NSString stringWithFormat:@"%@/%@.plist", photoListInAlbumCachePath, [@(albumId) description]];
    
    NSMutableDictionary *orginDic = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
    [orginDic setObject:des forKey:Key_Album_Describe];
    
    [orginDic writeToFile:path atomically:YES];
}

/*
 * 把照片id/相册信息列表转为Map写成plist文件(key从0开始),放在CACHE路径下
 * 通过username
 * data:照片id数组
 * start:作为Map中key的id,由于有分页的问题,所以每页数据开始的值是不一样的,只有第一页的start为0
 */
+ (void)cacheData:(NSArray *)data forUser:(NSString *)userName forAlbum:(NSUInteger)albumId start:(NSUInteger)start{
    if (data.count == 0) return;
    
    NSString *fomatter = nil;
    NSString *fileName = nil;
    NSUInteger countPerPage = 0;
    // 通过userName参数判断显示哪种类型
    if (userName) { //用户相册列表
        fomatter = kUserAlbumPath;
        fileName = userName;
        countPerPage = [[self commandFor:kUserAlbumCountPerPage] integerValue];
    }else{ //相册图片
#ifdef DEBUG
        NSAssert(albumId, @"albumId is 0");
#endif
        fomatter = kPhotosInAlbumPath;
        fileName = [@(albumId) description];
        countPerPage = [[self commandFor:kPhotosInAlbumCountPerPage] integerValue];
    }
    
    // 获取CACHE路径,并在结尾拼了一个文件夹的名字
    NSString *photoListInAlbumCachePath = [APP_CACHES_PATH stringByAppendingPathComponent:fomatter];
    NSString *path = [NSString stringWithFormat:@"%@/%@.plist", photoListInAlbumCachePath, fileName];
    
    NSMutableDictionary *newAddedDic = [NSMutableDictionary dictionaryWithCapacity:data.count];
    // 又是一个像闭包一样的写法,可以使用一个代码块迭代整个数组
    [data enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        newAddedDic[[@(idx+start) description]] = obj;
    }];
    
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:path])
    {
        // 新建一个plist存放Map的数据
        SLLog(@"创建 %@ %@ start %d count %d", userName?@"userAlbum":@"album", userName?userName:[@(albumId) description], start, newAddedDic.count);
        [newAddedDic writeToFile:path atomically:YES];
    }else{
        // 更新一个plist,先实例化为Map,把另一个Map添加到这个Map中,再将其写为文件
        SLLog(@"更新 %@ %@ start %d count %d", userName?@"userAlbum":@"album", userName?userName:[@(albumId) description], start, newAddedDic.count);
        NSMutableDictionary *orginDic = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
        [orginDic addEntriesFromDictionary:newAddedDic];
        
        [orginDic writeToFile:path atomically:YES];
    }
}

+ (void)emptyDisk{
    NSString *doubanAlbumCachePath = [APP_CACHES_PATH stringByAppendingPathComponent:kDoubanAlbumDataPath];
    [[NSFileManager defaultManager] removeItemAtPath:doubanAlbumCachePath error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:doubanAlbumCachePath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    
    NSString *photoListInAlbumCachePath = [APP_CACHES_PATH stringByAppendingPathComponent:kPhotosInAlbumPath];
    
    [[NSFileManager defaultManager] removeItemAtPath:photoListInAlbumCachePath error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:photoListInAlbumCachePath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    
    NSString *userAlbumsCachePath = [APP_CACHES_PATH stringByAppendingPathComponent:kUserAlbumPath];
    [[NSFileManager defaultManager] removeItemAtPath:userAlbumsCachePath error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:userAlbumsCachePath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
}

+ (void)cleanOuttimeImageInDisk{
    [GCDHelper dispatchBlock:^{
        NSDate *expirationDate = [NSDate dateWithTimeIntervalSinceNow:-CacheMaxCacheAge];
        
        NSString *photoListInAlbumCachePath = [APP_CACHES_PATH stringByAppendingPathComponent:kPhotosInAlbumPath];
        NSDirectoryEnumerator *fileEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:photoListInAlbumCachePath];
        for (NSString *fileName in fileEnumerator)
        {
            NSString *filePath = [photoListInAlbumCachePath stringByAppendingPathComponent:fileName];
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
            if ([[[attrs fileModificationDate] laterDate:expirationDate] isEqualToDate:expirationDate])
            {
                [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
            }
        }
        
        /////////
        NSString *userAlbumsCachePath = [APP_CACHES_PATH stringByAppendingPathComponent:kUserAlbumPath];
        fileEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:userAlbumsCachePath];
        for (NSString *fileName in fileEnumerator)
        {
            NSString *filePath = [userAlbumsCachePath stringByAppendingPathComponent:fileName];
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
            if ([[[attrs fileModificationDate] laterDate:expirationDate] isEqualToDate:expirationDate])
            {
                [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
            }
        }

    } completion:nil];
}

@end