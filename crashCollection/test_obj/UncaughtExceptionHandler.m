//
//  UncaughtExceptionHandler.m
//  test_obj
//
//  Created by TQ on 2020/4/15.
//  Copyright © 2020 TQ. All rights reserved.
//
#import <UIKit/UIKit.h>
#import "UncaughtExceptionHandler.h"
#include <libkern/OSAtomic.h>
#include <execinfo.h>
#include <stdatomic.h>

NSString * const UncaughtExceptionHandlerSignalExceptionName = @"UncaughtExceptionHandlerSignalExceptionName";
NSString * const UncaughtExceptionHandlerSignalKey = @"UncaughtExceptionHandlerSignalKey";
NSString * const UncaughtExceptionHandlerAddressesKey = @"UncaughtExceptionHandlerAddressesKey";
NSString * const UncaughtExceptionHandlerFileKey = @"UncaughtExceptionHandlerFileKey";

volatile atomic_int UncaughtExceptionCount = 0;
const int32_t UncaughtExceptionMaximum = 10;
const NSInteger UncaughtExceptionHandlerSkipAddressCount = 4;
const NSInteger UncaughtExceptionHandlerReportAddressCount = 5;

void MySignalHandler(int signal);

@implementation UncaughtExceptionHandler

+ (void)installUncaughtExceptionHandler{
    /***** 系统异常捕获（越界） **/
    NSSetUncaughtExceptionHandler(UncaughtExceptionHandlers);
    
    //信号量截断
    signal(SIGABRT, MySignalHandler);
    signal(SIGILL, MySignalHandler);
    signal(SIGSEGV, MySignalHandler);
    signal(SIGFPE, MySignalHandler);
    signal(SIGBUS, MySignalHandler);
    signal(SIGPIPE, MySignalHandler);
    
}


//获取函数堆栈信息
+ (NSArray *)backtrace {

    void* callstack[128];
    int frames = backtrace(callstack, 128);//用于获取当前线程的函数调用堆栈，返回实际获取的指针个数
    char **strs = backtrace_symbols(callstack, frames);//从backtrace函数获取的信息转化为一个字符串数组
    int i;
    NSMutableArray *backtrace = [NSMutableArray arrayWithCapacity:frames];
    for (i = UncaughtExceptionHandlerSkipAddressCount;
     i < UncaughtExceptionHandlerSkipAddressCount+UncaughtExceptionHandlerReportAddressCount;
     i++)  {
        [backtrace addObject:[NSString stringWithUTF8String:strs[i]]];
    }
    free(strs);
    return backtrace;
}


- (void)saveCreash:(NSException *)exception file:(NSString *)file {
    NSArray *stackArray = [exception callStackSymbols];// 异常的堆栈信息
    NSString *reason = [exception reason];// 出现异常的原因
    NSString *name = [exception name];// 异常名称

    //或者直接用代码，输入这个崩溃信息，以便在console中进一步分析错误原因
    NSLog(@"CRASH: %@", exception);
    NSLog(@"Stack Trace: %@", [exception callStackSymbols]);


    NSString * _libPath  = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:file];

//    NSString *_libPath=[NSHomeDirectory() stringByAppendingPathComponent:file];

    if (![[NSFileManager defaultManager] fileExistsAtPath:_libPath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:_libPath withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSDate* dat = [NSDate dateWithTimeIntervalSinceNow:0];
    NSTimeInterval a=[dat timeIntervalSince1970];
    NSString *timeString = [NSString stringWithFormat:@"%f", a];

    NSString * savePath = [_libPath stringByAppendingFormat:@"/error%@.log",timeString];

    NSString *exceptionInfo = [NSString stringWithFormat:@"Exception reason：%@\nException name：%@\nException stack：%@",name, reason, stackArray];

    BOOL sucess = [exceptionInfo writeToFile:savePath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSLog(@"保存崩溃日志 sucess:%d,%@",sucess,savePath);
}


//异常处理方法
- (void)handleException:(NSException *)exception {
    NSDictionary *userInfo=[exception userInfo];
    [self saveCreash:exception file:[userInfo objectForKey:UncaughtExceptionHandlerFileKey]];

    NSSetUncaughtExceptionHandler(NULL);
    signal(SIGABRT, SIG_DFL);
    signal(SIGILL, SIG_DFL);
    signal(SIGSEGV, SIG_DFL);
    signal(SIGFPE, SIG_DFL);
    signal(SIGBUS, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);
    if ([[exception name] isEqual:UncaughtExceptionHandlerSignalExceptionName]){
        kill(getpid(), [[[exception userInfo] objectForKey:UncaughtExceptionHandlerSignalKey] intValue]);
    } else {
        [exception raise];
    }
}

//获取应用信息
NSString* getAppInfo() {
    NSString *appInfo = [NSString stringWithFormat:@"App : %@ %@(%@)\nDevice : %@\nOS Version : %@ %@\n",
                     [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"],
                     [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                     [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"],
                     [UIDevice currentDevice].model,
                     [UIDevice currentDevice].systemName,
                     [UIDevice currentDevice].systemVersion];
//                         [UIDevice currentDevice].uniqueIdentifier];
    NSLog(@"Crash!!!! %@", appInfo);
    return appInfo;
}




//NSSetUncaughtExceptionHandler捕获异常的调用方法
//利用 NSSetUncaughtExceptionHandler，当程序异常退出的时候，可以先进行处理，然后做一些自定义的动作
void UncaughtExceptionHandlers (NSException *exception) {
            
    atomic_fetch_add_explicit(&UncaughtExceptionCount, 1, memory_order_relaxed); // atomic//自动增加一个32位的值
    if (UncaughtExceptionCount > UncaughtExceptionMaximum)
    {
        return;
    }

    NSArray *callStack = [UncaughtExceptionHandler backtrace];
    NSMutableDictionary *userInfo =
    [NSMutableDictionary dictionaryWithDictionary:[exception userInfo]];
    [userInfo setObject:callStack forKey:UncaughtExceptionHandlerAddressesKey];
    [userInfo setObject:@"OCCrash" forKey:UncaughtExceptionHandlerFileKey];


    [[[UncaughtExceptionHandler alloc] init] performSelectorOnMainThread:@selector(handleException:)
                                                              withObject:[NSException exceptionWithName:[exception name]
                                                                  reason:[exception reason] userInfo:userInfo]
                                                           waitUntilDone:YES];
}


//Signal处理方法
void MySignalHandler(int signal) {
    atomic_fetch_add_explicit(&UncaughtExceptionCount, 1, memory_order_relaxed); // atomic//自动增加一个32位的值//自动增加一个32位的值
    if (UncaughtExceptionCount > UncaughtExceptionMaximum)
    {
        return;
    }

    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:[NSNumber numberWithInt:signal] forKey:UncaughtExceptionHandlerSignalKey];
    NSArray *callStack = [UncaughtExceptionHandler backtrace];
    [userInfo setObject:callStack forKey:UncaughtExceptionHandlerAddressesKey];
    [userInfo setObject:@"SigCrash" forKey:UncaughtExceptionHandlerFileKey];

    [[[UncaughtExceptionHandler alloc] init] performSelectorOnMainThread:@selector(handleException:)
                                                              withObject:[NSException exceptionWithName:UncaughtExceptionHandlerSignalExceptionName
                                                                  reason:[NSString stringWithFormat:NSLocalizedString(@"Signal %d was raised.\n" @"%@", nil), signal, getAppInfo()] userInfo:userInfo]
                                                           waitUntilDone:YES];
}
@end
