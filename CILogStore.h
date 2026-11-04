#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CILogLevel) {
    CILogLevelDebug,
    CILogLevelInfo,
    CILogLevelWarning,
    CILogLevelError,
};

FOUNDATION_EXPORT NSNotificationName const CILogStoreDidChangeNotification;

@interface CILogStore : NSObject

+ (instancetype)sharedStore;

- (void)recordLevel:(CILogLevel)level
           category:(NSString *)category
             format:(NSString *)format, ... NS_FORMAT_FUNCTION(3, 4);
- (void)recordLevel:(CILogLevel)level
           category:(NSString *)category
            message:(NSString *)message;
- (NSArray<NSString *> *)snapshot;
/// Includes every retained full-log archive and the longer-lived event stream.
- (NSString *)exportText;
- (nullable NSURL *)exportFileURL;
- (void)clear;

@end

NS_ASSUME_NONNULL_END
