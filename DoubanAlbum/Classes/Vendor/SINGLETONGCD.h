//
//  SINGLETONGCD.h
//  DoubanAlbum
//
//  Created by Tonny on 11-12-12.
//  Copyright (c) 2012 SlowsLab. All rights reserved.
//

/*!
 * @function Singleton GCD Macro
 */
#ifndef SINGLETON_GCD
#define SINGLETON_GCD(classname)                        \
\
+ (classname *)shared##classname {                      \
\
static dispatch_once_t pred;                        \
__strong static classname * shared##classname = nil;\
dispatch_once( &pred, ^{                            \
shared##classname = [[self alloc] init]; });    \
return shared##classname;                           \
}                                                           
#endif

/* 这里使用宏定义设计了一个+方法模板,参数是一个类名,\是行继续操作符,表示下一行仍然是宏定义;##是符号连接操作符 */