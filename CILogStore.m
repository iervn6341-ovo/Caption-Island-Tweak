#import "CILogStore.h"
#import "CIConstants.h"
#import <os/log.h>

NSNotificationName const CILogStoreDidChangeNotification = @"CILogStoreDidChangeNotification";

static const NSUInteger CIMaxLogEntries = 500;
// The live viewer stays small; disk history is independent of its 500 rows.
static const unsigned long long CIMaxLogFileBytes = 2 * 1024 * 1024;
static const NSUInteger CILogFileCount = 8;
static const unsigned long long CIEventFileBytes = 512 * 1024;
static const NSUInteger CIEventFileCount = 4;
static const void *CILogQueueSpecificKey = &CILogQueueSpecificKey;

static NSString *CIScrubLogValue(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0) return @"";

    NSString *scrubbed = value;
    NSArray<NSString *> *rawLines = [scrubbed componentsSeparatedByCharactersInSet:
        NSCharacterSet.newlineCharacterSet];
    NSMutableArray<NSString *> *nonemptyLines = [NSMutableArray array];
    for (NSString *line in rawLines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length > 0) [nonemptyLines addObject:trimmed];
    }
    if (nonemptyLines.count > 2) {
        scrubbed = [NSString stringWithFormat:@"%@ <%@>",
            nonemptyLines.firstObject, @"multiline payload redacted"];
    } else {
        scrubbed = [scrubbed stringByReplacingOccurrencesOfString:@"\r\n"
                                                       withString:@" ↩︎ "];
        scrubbed = [scrubbed stringByReplacingOccurrencesOfString:@"\r"
                                                       withString:@" ↩︎ "];
        scrubbed = [scrubbed stringByReplacingOccurrencesOfString:@"\n"
                                                       withString:@" ↩︎ "];
    }

    static NSArray<NSArray *> *rules;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        rules = @[
            @[@"(?i)\\b(?:https?|file)://[^\\s<>]+", @"<URL redacted>"],
            @[@"(?i)\\bwww\\.[^\\s<>]+", @"<URL redacted>"],
            @[@"(?i)\\bBearer\\s+[A-Za-z0-9._~+/=-]+", @"Bearer <redacted>"],
            @[@"(?i)\\b(authorization|cookie|set-cookie)\\b\\s*[:=]\\s*.*",
              @"$1=<redacted>"],
            @[@"(?i)\\b(api[-_ ]?key|(?:access|refresh|push|device|apns|relay)[-_ ]?token)\\b\\s*[:=]\\s*(?:\"[^\"]*\"|'[^']*'|[^\\s,;]+)",
              @"$1=<redacted>"],
            @[@"(?i)\\b(plainLyrics|syncedLyrics|lyricText|captionText|lyrics?)\\b\\s*[:=]\\s*.*",
              @"$1=<text redacted>"],
        ];
        NSMutableArray *compiled = [NSMutableArray array];
        for (NSArray *rule in rules) {
            NSRegularExpression *expression = [NSRegularExpression
                regularExpressionWithPattern:rule[0] options:0 error:nil];
            if (expression) [compiled addObject:@[expression, rule[1]]];
        }
        rules = compiled.copy;
    });
    for (NSArray *rule in rules) {
        NSRegularExpression *expression = rule[0];
        scrubbed = [expression stringByReplacingMatchesInString:scrubbed
            options:0 range:NSMakeRange(0, scrubbed.length) withTemplate:rule[1]];
    }

    if (scrubbed.length > 1000) {
        scrubbed = [[scrubbed substringToIndex:1000] stringByAppendingString:@"…"];
    }
    return scrubbed;
}

@interface CILogStore ()
@property (nonatomic) dispatch_queue_t queue;
@property (nonatomic, strong) NSMutableArray<NSString *> *entries;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, copy) NSString *logPath;
@property (nonatomic, copy) NSString *eventPath;
- (instancetype)initWithDirectory:(NSString *)directory legacyPath:(NSString *)legacyPath;
- (NSString *)pathForBase:(NSString *)base index:(NSUInteger)index;
- (BOOL)appendLine:(NSString *)line base:(NSString *)base limit:(unsigned long long)limit count:(NSUInteger)count;
- (void)loadPreview;
- (NSString *)retainedText;
@end

@implementation CILogStore

+ (instancetype)sharedStore {
    static CILogStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ store = [CILogStore new]; });
    return store;
}

- (instancetype)init {
    NSString *documents = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *directory = [documents stringByAppendingPathComponent:@"CaptionIsland/Logs"];
    NSString *caches = NSSearchPathForDirectoriesInDomains(
        NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    return [self initWithDirectory:directory
        legacyPath:[caches stringByAppendingPathComponent:@"CaptionIsland/CaptionIsland.log"]];
}

// Also used by the offline smoke test, with an isolated temporary directory.
- (instancetype)initWithDirectory:(NSString *)directory legacyPath:(NSString *)legacyPath {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.captionisland.log", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_queue, CILogQueueSpecificKey,
                                    (void *)CILogQueueSpecificKey, NULL);
        _entries = [NSMutableArray array];
        _dateFormatter = [NSDateFormatter new];
        _dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        _dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        NSFileManager *manager = NSFileManager.defaultManager;
        [manager createDirectoryAtPath:directory withIntermediateDirectories:YES
                           attributes:nil error:nil];
        // Diagnostic archives need to survive relaunches, but not device backups.
        NSURL *directoryURL = [NSURL fileURLWithPath:directory isDirectory:YES];
        [directoryURL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
        _logPath = [directory stringByAppendingPathComponent:@"CaptionIsland.log"];
        _eventPath = [directory stringByAppendingPathComponent:@"CaptionIsland-events.log"];
        // Migrate the legacy cache once, preserving the complete retained file.
        NSString *legacy = [NSString stringWithContentsOfFile:legacyPath
            encoding:NSUTF8StringEncoding error:nil];
        if (legacy.length > 0) {
            BOOL migrated = YES;
            for (NSString *line in [legacy componentsSeparatedByCharactersInSet:
                    NSCharacterSet.newlineCharacterSet]) {
                if (line.length > 0 && ![self appendLine:CIScrubLogValue(line)
                        base:_logPath limit:CIMaxLogFileBytes count:CILogFileCount]) {
                    migrated = NO;
                    break;
                }
            }
            if (migrated) {
                [manager removeItemAtPath:legacyPath error:nil];
            }
        }
        [self loadPreview];
    }
    return self;
}

- (NSString *)labelForLevel:(CILogLevel)level {
    switch (level) {
        case CILogLevelDebug: return @"DEBUG";
        case CILogLevelInfo: return @"INFO";
        case CILogLevelWarning: return @"WARN";
        case CILogLevelError: return @"ERROR";
    }
    return @"INFO";
}

- (void)recordLevel:(CILogLevel)level
           category:(NSString *)category
             format:(NSString *)format, ... {
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    [self recordLevel:level category:category message:message];
}

- (void)recordLevel:(CILogLevel)level
           category:(NSString *)category
            message:(NSString *)message {
    if (level == CILogLevelDebug && !CIPreferenceBool(CIDebugLoggingKey, NO)) return;
    NSString *safeCategory = CIScrubLogValue(category.length > 0 ? category : @"General");
    safeCategory = [safeCategory stringByReplacingOccurrencesOfString:@"]" withString:@")"];
    if (safeCategory.length > 48) safeCategory = [safeCategory substringToIndex:48];
    NSString *safeMessage = CIScrubLogValue(message ?: @"");

    dispatch_async(self.queue, ^{
        NSString *line = [NSString stringWithFormat:@"%@ [%@] [%@] %@",
            [self.dateFormatter stringFromDate:NSDate.date],
            [self labelForLevel:level], safeCategory, safeMessage];
        [self.entries addObject:line];
        if (self.entries.count > CIMaxLogEntries) {
            [self.entries removeObjectsInRange:
                NSMakeRange(0, self.entries.count - CIMaxLogEntries)];
        }
        [self appendLine:line base:self.logPath limit:CIMaxLogFileBytes count:CILogFileCount];
        // Keep important events longer than the high-volume diagnostic stream.
        // Source selection, activation and failures are retained; per-cue
        // acknowledgements and periodic background samples stay in the full log.
        BOOL routine = ([safeCategory isEqualToString:@"Eligibility"] &&
                [safeMessage hasPrefix:@"Background sample at "]) ||
            ([safeCategory isEqualToString:@"Background"] &&
                [safeMessage hasPrefix:@"Background clock heartbeat"]) ||
            [safeMessage hasPrefix:@"Caption reached the Live Activity:"] ||
            [safeMessage hasPrefix:@"Live Activity update pipeline is active"];
        if (level >= CILogLevelWarning || (level == CILogLevelInfo && !routine)) {
            [self appendLine:line base:self.eventPath limit:CIEventFileBytes count:CIEventFileCount];
        }

        if (CIPreferenceBool(CIDebugLoggingKey, NO)) {
            // line is already scrubbed by CIScrubLogValue above, so mark it
            // public: otherwise the unified log redacts it to <private> and
            // this diagnostic toggle stops being useful for field debugging.
            // %{public} is only parsed by the os_log()/os_trace() macro
            // family, not NSLog, so this must go through os_log directly.
            os_log(OS_LOG_DEFAULT, "[CaptionIsland] %{public}@", line);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter
                postNotificationName:CILogStoreDidChangeNotification object:self];
        });
    });
}

- (NSString *)pathForBase:(NSString *)base index:(NSUInteger)index {
    if (index == 0) return base;
    return [[base stringByDeletingPathExtension]
        stringByAppendingFormat:@".%lu.log", (unsigned long)index];
}

- (BOOL)appendLine:(NSString *)line base:(NSString *)base
             limit:(unsigned long long)limit count:(NSUInteger)count {
    NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length == 0 || base.length == 0) return NO;
    NSFileManager *manager = NSFileManager.defaultManager;
    unsigned long long existingBytes = [[manager attributesOfItemAtPath:base
        error:nil][NSFileSize] unsignedLongLongValue];
    if (existingBytes > 0 && existingBytes + data.length > limit) {
        // .1 is the most recent archive. Never rebuild from the UI preview.
        for (NSUInteger index = count - 1; index > 0; index--) {
            NSString *destination = [self pathForBase:base index:index];
            NSString *source = [self pathForBase:base index:index - 1];
            if (![manager fileExistsAtPath:source]) continue;
            [manager removeItemAtPath:destination error:nil];
            NSError *error = nil;
            if (![manager moveItemAtPath:source toPath:destination error:&error]) {
                os_log_error(OS_LOG_DEFAULT, "[CaptionIsland] Log rotation failed: %{public}@", error);
                return NO;
            }
        }
    }
    if (![manager fileExistsAtPath:base]) {
        return [data writeToFile:base options:NSDataWritingAtomic error:nil];
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:base];
    if (!handle) return NO;
    BOOL appended = YES;
    @try {
        [handle seekToEndOfFile];
        [handle writeData:data];
    } @catch (__unused NSException *exception) {
        appended = NO;
        os_log_error(OS_LOG_DEFAULT, "[CaptionIsland] Could not append diagnostic log");
    } @finally {
        [handle closeFile];
    }
    return appended;
}

- (void)loadPreview {
    // Read newest files first until the preview is full, without altering disk.
    for (NSUInteger index = 0; index < CILogFileCount && self.entries.count < CIMaxLogEntries; index++) {
        NSString *text = [NSString stringWithContentsOfFile:[self pathForBase:self.logPath index:index]
            encoding:NSUTF8StringEncoding error:nil];
        NSArray *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
        for (NSString *line in lines.reverseObjectEnumerator) {
            if (line.length == 0) continue;
            [self.entries insertObject:CIScrubLogValue(line) atIndex:0];
            if (self.entries.count == CIMaxLogEntries) break;
        }
    }
}

- (NSString *)retainedText {
    NSMutableString *result = [NSMutableString string];
    // Full logs are chronological; the separate event section may overlap and
    // can reach further back after verbose debug logs have rolled off disk.
    NSArray *bases = @[self.logPath, self.eventPath];
    NSArray *counts = @[@(CILogFileCount), @(CIEventFileCount)];
    for (NSUInteger stream = 0; stream < bases.count; stream++) {
        for (NSUInteger cursor = [counts[stream] unsignedIntegerValue]; cursor > 0; cursor--) {
            NSString *path = [self pathForBase:bases[stream] index:cursor - 1];
            NSString *contents = [NSString stringWithContentsOfFile:path
                encoding:NSUTF8StringEncoding error:nil];
            if (contents.length == 0) continue;
            [result appendFormat:@"===== %@ =====\n", path.lastPathComponent];
            // Re-scrub imported/externally edited files before sharing them.
            for (NSString *line in [contents componentsSeparatedByCharactersInSet:
                    NSCharacterSet.newlineCharacterSet]) {
                if (line.length > 0) [result appendFormat:@"%@\n", CIScrubLogValue(line)];
            }
        }
    }
    return result;
}

- (NSArray<NSString *> *)snapshot {
    __block NSArray<NSString *> *snapshot;
    void (^readBlock)(void) = ^{ snapshot = self.entries.copy; };
    if (dispatch_get_specific(CILogQueueSpecificKey)) readBlock();
    else dispatch_sync(self.queue, readBlock);
    return snapshot ?: @[];
}

- (NSString *)exportText {
    __block NSString *text;
    void (^readBlock)(void) = ^{ text = [self retainedText]; };
    if (dispatch_get_specific(CILogQueueSpecificKey)) readBlock();
    else dispatch_sync(self.queue, readBlock);
    return text ?: @"";
}

- (NSURL *)exportFileURL {
    NSString *text = self.exportText;
    if (text.length == 0) return nil;
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"CaptionIsland-LogExports"];
    NSFileManager *manager = NSFileManager.defaultManager;
    [manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    // Keep share-sheet copies briefly; do not let repeated exports grow forever.
    for (NSString *name in [manager contentsOfDirectoryAtPath:directory error:nil]) {
        NSString *path = [directory stringByAppendingPathComponent:name];
        NSDate *date = [manager attributesOfItemAtPath:path error:nil][NSFileModificationDate];
        if (date && -date.timeIntervalSinceNow > 24 * 60 * 60) [manager removeItemAtPath:path error:nil];
    }
    NSString *name = [NSString stringWithFormat:@"CaptionIsland-%@.txt", NSUUID.UUID.UUIDString];
    NSURL *url = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:name]];
    return [text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil] ? url : nil;
}

- (void)clear {
    dispatch_async(self.queue, ^{
        [self.entries removeAllObjects];
        for (NSUInteger stream = 0; stream < 2; stream++) {
            NSString *base = stream == 0 ? self.logPath : self.eventPath;
            NSUInteger count = stream == 0 ? CILogFileCount : CIEventFileCount;
            for (NSUInteger index = 0; index < count; index++) {
                [NSFileManager.defaultManager removeItemAtPath:[self pathForBase:base index:index] error:nil];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter
                postNotificationName:CILogStoreDidChangeNotification object:self];
        });
    });
}

@end
