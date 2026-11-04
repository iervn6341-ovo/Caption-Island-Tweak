#import <Foundation/Foundation.h>
#import "../../CILogStore.h"
#import "../../CIConstants.h"

// Isolate the real store from the host user's Documents and preferences.
NSString *const CIDebugLoggingKey = @"test.debug";
BOOL CIPreferenceBool(__unused NSString *key, __unused BOOL fallback) { return NO; }
@interface CILogStore (Testing)
- (instancetype)initWithDirectory:(NSString *)directory legacyPath:(NSString *)path;
@end
static void Check(BOOL okay, NSString *message) {
    if (!okay) { NSLog(@"FAIL: %@", message); exit(1); }
}
static void FillFile(NSString *path, NSUInteger bytes) {
    NSMutableData *data = [[NSData dataWithContentsOfFile:path] mutableCopy] ?: [NSMutableData data];
    NSString *padding = [[@"padding" stringByPaddingToLength:900 withString:@"x" startingAtIndex:0]
        stringByAppendingString:@"\n"];
    NSData *line = [padding dataUsingEncoding:NSUTF8StringEncoding];
    while (data.length + line.length <= bytes) [data appendData:line];
    if (data.length < bytes) {
        [data appendData:[[[@"x" stringByPaddingToLength:bytes - data.length - 1
            withString:@"x" startingAtIndex:0] stringByAppendingString:@"\n"]
            dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [data writeToFile:path atomically:YES];
}
int main(void) {
    @autoreleasepool {
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSFileManager *manager = NSFileManager.defaultManager;
        [manager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *directory = [root stringByAppendingPathComponent:@"Documents/CaptionIsland/Logs"];
        NSString *legacy = [root stringByAppendingPathComponent:@"legacy.log"];
        [@"legacy-switch\n" writeToFile:legacy atomically:YES encoding:NSUTF8StringEncoding error:nil];
        CILogStore *store = [[CILogStore alloc] initWithDirectory:directory legacyPath:legacy];
        Check(![manager fileExistsAtPath:legacy], @"legacy cache migrated");
        [store recordLevel:CILogLevelInfo category:@"Pipeline" message:@"switch-A-to-B"];
        [store recordLevel:CILogLevelInfo category:@"Background"
            message:@"Detected background transition to video B."];
        [store recordLevel:CILogLevelError category:@"Activity" message:@"update-failed api_key=secret"];
        for (NSUInteger index = 0; index < 620; index++) {
            [store recordLevel:CILogLevelInfo category:@"Background"
                format:@"Background clock heartbeat sample-%lu", (unsigned long)index];
        }
        Check(store.snapshot.count == 500, @"viewer bounded to 500 entries");
        Check([store.exportText containsString:@"legacy-switch"] &&
              [store.exportText containsString:@"sample-0"], @"export includes entries outside preview");
        Check(![store.exportText containsString:@"secret"], @"secrets scrubbed");
        NSString *event = [directory stringByAppendingPathComponent:@"CaptionIsland-events.log"];
        NSString *eventText = [NSString stringWithContentsOfFile:event encoding:NSUTF8StringEncoding error:nil];
        Check([eventText containsString:@"switch-A-to-B"] && [eventText containsString:@"update-failed"] &&
              [eventText containsString:@"Detected background transition to video B."] &&
              ![eventText containsString:@"sample-"], @"important events independent of routine samples");
        NSString *active = [directory stringByAppendingPathComponent:@"CaptionIsland.log"];
        // Fill actual production-sized files, then let the real append rotate.
        for (NSUInteger index = 0; index < 10; index++) {
            FillFile(active, 2 * 1024 * 1024);
            [store recordLevel:CILogLevelInfo category:@"Background" format:@"Background clock heartbeat rotation-%lu", (unsigned long)index];
            (void)store.snapshot; // Drain the serialized writer before external fixture writes.
        }
        NSArray *files = [manager contentsOfDirectoryAtPath:directory error:nil];
        NSUInteger fullCount = 0;
        for (NSString *name in files) {
            if ([name hasPrefix:@"CaptionIsland."]) fullCount++;
            unsigned long long size = [[manager attributesOfItemAtPath:
                [directory stringByAppendingPathComponent:name] error:nil][NSFileSize] unsignedLongLongValue];
            Check(size <= 2 * 1024 * 1024, @"full files stay within cap");
        }
        Check(fullCount == 8, @"one current file plus seven archives");
        NSString *before = store.exportText;
        Check([before containsString:@"rotation-9"] && [before containsString:@"switch-A-to-B"] &&
              [before containsString:@"Detected background transition to video B."],
              @"critical events survive full-stream churn");
        Check(![before containsString:@"rotation-0"] && ![before containsString:@"rotation-1"],
              @"oldest full archives are removed");
        NSUInteger previous = 0;
        for (NSUInteger index = 2; index < 10; index++) {
            NSRange range = [before rangeOfString:[NSString stringWithFormat:@"rotation-%lu", (unsigned long)index]];
            Check(range.location != NSNotFound && range.location >= previous, @"archives export oldest to newest");
            previous = range.location;
        }
        CILogStore *reopened = [[CILogStore alloc] initWithDirectory:directory legacyPath:legacy];
        Check([before isEqualToString:reopened.exportText], @"relaunch does not truncate archives");
        // Exercise bounded event rotation and ordering without huge log traffic.
        for (NSUInteger index = 0; index < 5; index++) {
            FillFile(event, 512 * 1024);
            [reopened recordLevel:CILogLevelWarning category:@"Activity" format:@"warning-%lu", (unsigned long)index];
            (void)reopened.snapshot;
        }
        Check([manager fileExistsAtPath:[directory stringByAppendingPathComponent:@"CaptionIsland-events.3.log"]] &&
              ![manager fileExistsAtPath:[directory stringByAppendingPathComponent:@"CaptionIsland-events.4.log"]],
              @"event files bounded to four");
        // Clear uses the same queue as recording/export and removes both streams.
        [reopened clear];
        Check(reopened.snapshot.count == 0 && reopened.exportText.length == 0 &&
              [manager contentsOfDirectoryAtPath:directory error:nil].count == 0, @"clear removes all retained streams");
        [reopened recordLevel:CILogLevelInfo category:@"Pipeline" message:@"after-clear"];
        Check([reopened.exportText containsString:@"after-clear"], @"logging resumes after clear");
        NSURL *exportURL = reopened.exportFileURL;
        Check([exportURL.pathExtension isEqualToString:@"txt"] &&
              [[NSString stringWithContentsOfURL:exportURL encoding:NSUTF8StringEncoding error:nil]
                isEqualToString:reopened.exportText], @"shareable text file contains all retained logs");
        [manager removeItemAtURL:exportURL error:nil];
        NSString *blocked = [root stringByAppendingPathComponent:@"blocked"];
        [@"file" writeToFile:blocked atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [@"unmigrated" writeToFile:legacy atomically:YES encoding:NSUTF8StringEncoding error:nil];
        __unused CILogStore *failed = [[CILogStore alloc]
            initWithDirectory:[blocked stringByAppendingPathComponent:@"Logs"] legacyPath:legacy];
        Check([manager fileExistsAtPath:legacy], @"failed migration preserves legacy source");
        [manager removeItemAtPath:root error:nil];
        NSLog(@"PASS: rotation, event retention, migration, restart, export, clear, and redaction");
    }
    return 0;
}
