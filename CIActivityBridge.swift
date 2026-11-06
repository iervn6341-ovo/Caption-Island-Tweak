import ActivityKit
import Foundation
import UIKit

private func activityText(
    traditionalChinese: String,
    english: String,
    japanese: String
) -> String {
    let language = Locale.preferredLanguages.first?.lowercased() ?? "en"
    if language.hasPrefix("zh") { return traditionalChinese }
    if language.hasPrefix("ja") { return japanese }
    return english
}

private func clippedUTF8(_ value: String, maximumBytes: Int) -> String {
    guard value.utf8.count > maximumBytes else { return value }
    let ellipsis = "…"
    let budget = max(0, maximumBytes - ellipsis.utf8.count)
    var result = ""
    var usedBytes = 0
    for character in value {
        let fragment = String(character)
        let fragmentBytes = fragment.utf8.count
        guard usedBytes + fragmentBytes <= budget else { break }
        result.append(character)
        usedBytes += fragmentBytes
    }
    return result + ellipsis
}

private func sanitizedActivityText(
    _ value: String,
    maximumBytes: Int
) -> String {
    var sanitized = ""
    var previousWasReplacementSpace = false
    for scalar in value.unicodeScalars {
        if CharacterSet.controlCharacters.contains(scalar) {
            if !previousWasReplacementSpace {
                sanitized.append(" ")
            }
            previousWasReplacementSpace = true
        } else {
            sanitized.unicodeScalars.append(scalar)
            previousWasReplacementSpace = false
        }
    }
    return clippedUTF8(sanitized, maximumBytes: maximumBytes)
}

// ActivityKit does not expose an existing activity's original creation date.
// Persist dates by activity ID; old installs remain explicitly "unknown".
private enum CIActivityLifetime {
    private static let key = "CaptionIsland.ActivityCreationDates.v1"
    private static let lock = NSLock()

    static func created(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        var dates = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        dates[id] = Date().timeIntervalSince1970
        let newest = dates.sorted { $0.value > $1.value }.prefix(32)
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) }), forKey: key)
    }

    static func description(_ id: String) -> String {
        lock.lock()
        let timestamp = (UserDefaults.standard.dictionary(forKey: key)?[id] as? NSNumber)?.doubleValue
        lock.unlock()
        guard let timestamp else { return "created=unknown age=unknown" }
        let date = Date(timeIntervalSince1970: timestamp)
        let age = max(0, Date().timeIntervalSince(date))
        return "created=\(ISO8601DateFormatter().string(from: date)) age=\(String(format: "%.1fs", age))"
    }

    static func log(_ activity: Activity<CICaptionActivityAttributes>, event: String, reason: String) {
        CIActivityBridge.emit(level: "info", message:
            "Live Activity lifecycle event=\(event) id=\(activity.id) "
            + "video=\(activity.content.state.videoID) state=\(activity.activityState) "
            + "\(description(activity.id)) reason=\(reason)")
    }
}

@objc(CIActivityBridge)
public final class CIActivityBridge: NSObject {
    private static let commandQueue = DispatchQueue(
        label: "com.captionisland.activity.commands"
    )
    private static var commandTail: Task<Void, Never>?
    private static let metadataLogLock = NSLock()
    private static var didReportMissingSupportKey = false
    private static var didReportBundleIdentifierWarning = false
    private static func installedBundleIdentifier(_ bundle: Bundle) -> String {
        // YouTube compatibility hooks may spoof Bundle.main's in-process ID.
        // Compare the installed plist identities when diagnosing the Widget.
        let url = bundle.bundleURL.appendingPathComponent("Info.plist")
        if let data = try? Data(contentsOf: url),
           let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let identifier = info["CFBundleIdentifier"] as? String {
            return identifier
        }
        return bundle.bundleIdentifier ?? "unknown"
    }
    private static let installedWidgetBundleIdentifierWarning: String? = {
        let appBundle = Bundle.main
        let appBundleID = installedBundleIdentifier(appBundle)
        let widgetURL = (appBundle.builtInPlugInsURL ??
            appBundle.bundleURL.appendingPathComponent(
                "PlugIns",
                isDirectory: true
            )).appendingPathComponent(
                "CaptionIslandWidget.appex",
                isDirectory: true
            )
        guard let widgetBundle = Bundle(url: widgetURL) else { return nil }
        let widgetBundleID = installedBundleIdentifier(widgetBundle)
        let expectedWidgetBundleID = "\(appBundleID).CaptionIslandWidget"
        guard widgetBundleID != expectedWidgetBundleID else { return nil }
        return "widget bundle ID is \(widgetBundleID), expected "
            + "\(expectedWidgetBundleID). The sideload signer may have "
            + "rewritten the extension identifier; ActivityKit will still be attempted."
    }()
    private static let installedTargetMetadataIssue: String? = {
        let appBundle = Bundle.main
        let appBundleID = installedBundleIdentifier(appBundle)
        let appSupportValue = appBundle.object(
            forInfoDictionaryKey: "NSSupportsLiveActivities"
        )
        guard (appSupportValue as? NSNumber)?.boolValue == true else {
            let value = appSupportValue.map { String(describing: $0) } ?? "missing"
            return "main app \(appBundleID) has NSSupportsLiveActivities=\(value)"
        }

        let plugInsURL = appBundle.builtInPlugInsURL ??
            appBundle.bundleURL.appendingPathComponent(
                "PlugIns",
                isDirectory: true
            )
        let widgetURL = plugInsURL.appendingPathComponent(
            "CaptionIslandWidget.appex",
            isDirectory: true
        )
        guard let widgetBundle = Bundle(url: widgetURL) else {
            return "CaptionIslandWidget.appex is missing or has an unreadable Info.plist"
        }

        let widgetBundleID = installedBundleIdentifier(widgetBundle)

        let widgetSupportValue = widgetBundle.object(
            forInfoDictionaryKey: "NSSupportsLiveActivities"
        )
        guard (widgetSupportValue as? NSNumber)?.boolValue == true else {
            let value = widgetSupportValue.map { String(describing: $0) } ?? "missing"
            return "widget \(widgetBundleID) has NSSupportsLiveActivities=\(value)"
        }

        let extensionDictionary = widgetBundle.object(
            forInfoDictionaryKey: "NSExtension"
        ) as? [String: Any]
        let extensionPoint = extensionDictionary?[
            "NSExtensionPointIdentifier"
        ] as? String
        guard extensionPoint == "com.apple.widgetkit-extension" else {
            return "widget extension point is \(extensionPoint ?? "missing")"
        }
        return nil
    }()

    @objc(isAvailable)
    public static func isAvailable() -> Bool {
        targetSupportsLiveActivities(logIfMissing: false) &&
            ActivityAuthorizationInfo().areActivitiesEnabled
    }

    @objc(startWithVideoID:title:)
    public static func start(videoID: String, title: String) {
        guard targetSupportsLiveActivities(logIfMissing: true) else { return }
        let safeVideoID = sanitizedActivityText(videoID, maximumBytes: 96)
        let safeTitle = sanitizedActivityText(title, maximumBytes: 384)
        enqueue {
            await CIActivityManager.shared.start(
                videoID: safeVideoID,
                title: safeTitle
            )
        }
    }

    @objc(ensureWithVideoID:title:)
    public static func ensure(videoID: String, title: String) {
        guard targetSupportsLiveActivities(logIfMissing: true) else { return }
        let safeVideoID = sanitizedActivityText(videoID, maximumBytes: 96)
        let safeTitle = sanitizedActivityText(title, maximumBytes: 384)
        enqueue {
            await CIActivityManager.shared.ensure(
                videoID: safeVideoID,
                title: safeTitle
            )
        }
    }

    @objc(refreshForPresentationWithReason:)
    public static func refreshForPresentation(reason: String) {
        guard targetSupportsLiveActivities(logIfMissing: false) else { return }
        let safeReason = sanitizedActivityText(reason, maximumBytes: 160)
        enqueue {
            await CIActivityManager.shared.refreshPresentation(
                reason: safeReason
            )
        }
    }

    @objc(updateWithText:source:cueStart:cueEnd:position:playing:nextText:nextCueStart:nextCueEnd:)
    public static func update(
        text: String,
        source: String,
        cueStart: Double,
        cueEnd: Double,
        position: Double,
        playing: Bool,
        nextText: String,
        nextCueStart: Double,
        nextCueEnd: Double
    ) {
        guard targetSupportsLiveActivities(logIfMissing: false) else { return }
        let safeText = sanitizedActivityText(text, maximumBytes: 1_024)
        let safeNextText = sanitizedActivityText(
            nextText,
            maximumBytes: 1_024
        )
        let safeSource = sanitizedActivityText(source, maximumBytes: 64)
        let startMilliseconds = milliseconds(cueStart)
        let endMilliseconds = milliseconds(cueEnd)
        let nextStartMilliseconds = milliseconds(nextCueStart)
        let nextEndMilliseconds = milliseconds(nextCueEnd)
        enqueue {
            await CIActivityManager.shared.update(
                line: safeText,
                source: safeSource,
                cueStartMS: startMilliseconds,
                cueEndMS: endMilliseconds,
                nextLine: safeNextText,
                nextCueStartMS: nextStartMilliseconds,
                nextCueEndMS: nextEndMilliseconds,
                position: position,
                isPlaying: playing
            )
        }
    }

    @objc(showGapWithTitle:)
    public static func showGap(title: String) {
        guard targetSupportsLiveActivities(logIfMissing: false) else { return }
        let safeTitle = sanitizedActivityText(title, maximumBytes: 384)
        enqueue {
            await CIActivityManager.shared.showGap(
                title: safeTitle
            )
        }
    }

    @objc(endImmediately:)
    public static func end(immediately: Bool) {
        guard targetSupportsLiveActivities(logIfMissing: false) else { return }
        end(immediately: immediately, reason: "legacy presenter end request")
    }

    @objc(endImmediately:reason:)
    public static func end(immediately: Bool, reason: String) {
        guard targetSupportsLiveActivities(logIfMissing: false) else { return }
        let safeReason = sanitizedActivityText(reason, maximumBytes: 240)
        enqueue {
            await CIActivityManager.shared.end(immediately: immediately, reason: safeReason)
        }
    }

    /// Process termination has a very small execution window. Bypass the
    /// ordinary serialized command tail so queued lyric updates can't delay
    /// the immediate ActivityKit dismissal request.
    @objc(endAllImmediatelyForTermination)
    public static func endAllImmediatelyForTermination() {
        endAllImmediatelyForTermination(reason: "process termination")
    }

    @objc(endAllImmediatelyForTerminationWithReason:)
    public static func endAllImmediatelyForTermination(reason: String) {
        let safeReason = sanitizedActivityText(reason, maximumBytes: 240)
        // Log synchronously before the termination wait blocks the main queue.
        for activity in Activity<CICaptionActivityAttributes>.activities {
            NotificationCenter.default.post(name: Notification.Name("CIActivityBridgeLogNotification"),
                object: nil, userInfo: ["level": "info", "message":
                    "Live Activity termination request id=\(activity.id) state=\(activity.activityState) "
                    + "\(CIActivityLifetime.description(activity.id)) reason=\(safeReason)"])
        }
        let completion = DispatchSemaphore(value: 0)
        Task.detached(priority: .high) {
            let activities =
                Activity<CICaptionActivityAttributes>.activities
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            completion.signal()
        }
        _ = completion.wait(timeout: .now() + 0.8)
    }

    static func emit(level: String, message: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("CIActivityBridgeLogNotification"),
                object: nil,
                userInfo: ["level": level, "message": message]
            )
        }
    }

    private static func enqueue(
        _ operation: @escaping @Sendable () async -> Void
    ) {
        commandQueue.sync {
            let previous = commandTail
            commandTail = Task {
                if let previous {
                    await previous.value
                }
                await operation()
            }
        }
    }

    private static func targetSupportsLiveActivities(
        logIfMissing: Bool
    ) -> Bool {
        if logIfMissing, let warning = installedWidgetBundleIdentifierWarning {
            metadataLogLock.lock()
            let shouldReportWarning = !didReportBundleIdentifierWarning
            didReportBundleIdentifierWarning = true
            metadataLogLock.unlock()
            if shouldReportWarning {
                emit(level: "warning", message: warning)
            }
        }
        guard let issue = installedTargetMetadataIssue else { return true }
        guard logIfMissing else { return false }

        metadataLogLock.lock()
        let shouldReport = !didReportMissingSupportKey
        didReportMissingSupportKey = true
        metadataLogLock.unlock()
        guard shouldReport else { return false }

        emit(
            level: "error",
            message: "Installed target cannot start Live Activities: \(issue). "
                + "Reinstall an IPA that passed the Caption Island metadata check."
        )
        return false
    }

    private static func milliseconds(_ value: Double) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        let converted = value * 1000.0
        guard converted.isFinite, converted < Double(Int.max) else {
            return Int.max
        }
        return Int(converted)
    }
}

private actor CIActivityManager {
    private static let sessionID =
        "caption-island-local-v1"

    private struct PayloadEnvelope: Encodable {
        let attributes: CICaptionActivityAttributes
        let state: CICaptionActivityAttributes.ContentState
    }

    static let shared = CIActivityManager()

    private var activity: Activity<CICaptionActivityAttributes>?
    private var videoID = ""
    private var title = "YouTube"
    private var revision = 0
    private var lastLine = ""
    private var lastSource = ""
    private var lastCueStartMS = 0
    private var lastCueEndMS = 0
    private var lastNextLine = ""
    private var lastNextCueStartMS = 0
    private var lastNextCueEndMS = 0
    private var lastPlaying = true
    private var dismissedVideoID = ""
    private var didLogMissingActivity = false
    private var isStartBlockedByUnsupportedTarget = false
    private var lastUpdateHeartbeatUptime: TimeInterval = 0
    private var activityStateTask: Task<Void, Never>?
    private var activityObservationGeneration = 0
    private var ignoredInactiveIDs = Set<String>()
    private var didLogDeferredStart = false
    private var requestedEndReasons: [String: String] = [:]
    private var pendingVerification: (
        activityID: String,
        revision: Int,
        source: String,
        uptime: TimeInterval
    )?

    func start(videoID: String, title: String) async {
        guard !isStartBlockedByUnsupportedTarget else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            CIActivityBridge.emit(
                level: "warning",
                message: "Live Activities are disabled in iOS Settings"
            )
            return
        }
        if let currentActivity = activity {
            switch currentActivity.activityState {
            case .active, .stale:
                let changedVideo = self.videoID != videoID
                self.videoID = videoID
                self.title = title.isEmpty ? "YouTube" : title
                revision += 1
                lastLine = ""
                lastSource = ""
                lastCueStartMS = 0
                lastCueEndMS = 0
                lastNextLine = ""
                lastNextCueStartMS = 0
                lastNextCueEndMS = 0
                lastPlaying = true
                await updateState(waitingState())
                if isUpdatable(currentActivity), activity?.id == currentActivity.id {
                    didLogMissingActivity = false
                    CIActivityBridge.emit(
                        level: changedVideo ? "info" : "debug",
                        message: changedVideo
                            ? "Reused Live Activity for video \(videoID)"
                            : "Reused existing Live Activity"
                    )
                    return
                }
                if currentActivity.activityState == .dismissed { dismissedVideoID = videoID }
                await releaseInactiveActivity(currentActivity)
            case .dismissed:
                dismissedVideoID = self.videoID
                await releaseInactiveActivity(currentActivity)
            case .ended:
                await releaseInactiveActivity(currentActivity)
            default:
                await releaseInactiveActivity(currentActivity)
            }
        }
        if dismissedVideoID == videoID {
            CIActivityBridge.emit(
                level: "debug",
                message: "Live Activity remains dismissed for the current video"
            )
            return
        }
        if dismissedVideoID != videoID {
            dismissedVideoID = ""
        }
        let systemActivities = Activity<CICaptionActivityAttributes>.activities

        self.videoID = videoID
        self.title = title.isEmpty ? "YouTube" : title
        self.revision = 1
        self.lastLine = ""
        self.lastSource = ""
        self.lastCueStartMS = 0
        self.lastCueEndMS = 0
        self.lastNextLine = ""
        self.lastNextCueStartMS = 0
        self.lastNextCueEndMS = 0
        self.lastPlaying = true
        for candidate in systemActivities where !isUpdatable(candidate) {
            if ignoredInactiveIDs.insert(candidate.id).inserted {
                CIActivityLifetime.log(candidate, event: "ignored-inactive",
                    reason: "terminal or pending activities cannot be adopted")
            }
        }
        if ignoredInactiveIDs.count > 64 { ignoredInactiveIDs.removeAll() }
        let existingActivity = systemActivities.first {
            $0.attributes.sessionID == Self.sessionID && isUpdatable($0)
        }
        if let existingActivity {
            activity = existingActivity
            pendingVerification = nil
            revision = max(0, existingActivity.content.state.revision) + 1
            observeActivityState(for: existingActivity)
            for duplicate in systemActivities
                where duplicate.id != existingActivity.id && isUpdatable(duplicate) {
                await endActivity(duplicate, immediately: true, reason: "duplicate active caption activity")
            }
            if isUpdatable(existingActivity), activity?.id == existingActivity.id {
                await updateState(waitingState())
                if isUpdatable(existingActivity), activity?.id == existingActivity.id {
                    didLogMissingActivity = false
                    didLogDeferredStart = false
                    CIActivityLifetime.log(existingActivity, event: "adopted", reason: "matching active session")
                    return
                }
            }
            await releaseInactiveActivity(existingActivity)
        }
        // UIKit state must be sampled on the main thread. Background audio does
        // not by itself authorize Activity.request; foreground ensure retries.
        guard await MainActor.run(body: { UIApplication.shared.applicationState == .active }) else {
            if !didLogDeferredStart {
                didLogDeferredStart = true
                CIActivityBridge.emit(level: "info", message:
                    "Live Activity recovery deferred until foreground for video \(videoID); no updatable activity")
            }
            return
        }
        for legacyActivity in systemActivities where isUpdatable(legacyActivity) {
            await endActivity(legacyActivity, immediately: true, reason: "replace incompatible caption session")
        }

        revision = 1
        await startActivity(state: boundedState(waitingState()))
    }

    private func startActivity(
        state: CICaptionActivityAttributes.ContentState
    ) async {
        // A revision left over from the previous activity would be checked
        // against the new activity's id and always look rejected.
        pendingVerification = nil
        do {
            activity = try Activity.request(
                attributes: CICaptionActivityAttributes(
                    sessionID: Self.sessionID
                ),
                content: ActivityContent(
                    state: state,
                    staleDate: nil,
                    relevanceScore: 1
                ),
                pushType: nil
            )
            if let activity {
                CIActivityLifetime.created(activity.id)
                CIActivityLifetime.log(activity, event: "created", reason: "foreground start or recovery")
                observeActivityState(for: activity)
            }
            didLogDeferredStart = false
            didLogMissingActivity = false
            CIActivityBridge.emit(
                level: "info",
                message: "Started native Live Activity "
                    + "for video \(videoID)"
            )
        } catch {
            activity = nil
            let description = error.localizedDescription
            let normalizedDescription =
                description.lowercased()
            if normalizedDescription.contains(
                "nssupportsliveactivities"
            ) ||
                normalizedDescription.contains(
                    "unsupportedtarget"
                ) {
                isStartBlockedByUnsupportedTarget = true
            }
            CIActivityBridge.emit(
                level: "error",
                message: "Unable to start Live Activity: "
                    + "\(description)"
            )
        }
    }

    func ensure(videoID: String, title: String) async {
        if let currentActivity = activity {
            switch currentActivity.activityState {
            case .active, .stale:
                if self.videoID == videoID { return }
            case .dismissed:
                dismissedVideoID = self.videoID
                await releaseInactiveActivity(currentActivity)
            case .ended:
                await releaseInactiveActivity(currentActivity)
            default:
                if self.videoID == videoID { return }
            }
        }
        await start(videoID: videoID, title: title)
    }

    func refreshPresentation(reason: String) async {
        guard hasUpdatableActivity(), let activity else {
            CIActivityBridge.emit(
                level: "warning",
                message: "Could not refresh Dynamic Island presentation "
                    + "because no caption Live Activity is active"
            )
            return
        }
        revision += 1
        let state: CICaptionActivityAttributes.ContentState
        if lastLine.isEmpty {
            state = waitingState()
        } else {
            state = CICaptionActivityAttributes.ContentState(
                line: lastLine,
                source: lastSource,
                videoID: videoID,
                videoTitle: title,
                isPlaying: lastPlaying,
                cueStartMS: lastCueStartMS,
                cueEndMS: lastCueEndMS,
                nextLine: lastNextLine.isEmpty ? nil : lastNextLine,
                nextCueStartMS: lastNextLine.isEmpty
                    ? nil : lastNextCueStartMS,
                nextCueEndMS: lastNextLine.isEmpty
                    ? nil : lastNextCueEndMS,
                revision: revision
            )
        }
        await updateState(state)
        let localActivityCount =
            Activity<CICaptionActivityAttributes>.activities.count
        CIActivityBridge.emit(
            level: "info",
            message: "Refreshed caption Live Activity \(activity.id) "
                + "for \(reason.isEmpty ? "presentation transition" : reason) "
                + "(state \(activity.activityState), "
                + "\(localActivityCount) local caption activity)"
        )
    }

    private func observeActivityState(
        for observedActivity:
            Activity<CICaptionActivityAttributes>
    ) {
        stopActivityObservation()
        let observedActivityID = observedActivity.id
        let observationGeneration = activityObservationGeneration
        activityStateTask = Task {
            for await state in observedActivity.activityStateUpdates {
                guard !Task.isCancelled,
                      self.isCurrentActivityObservation(
                        activityID: observedActivityID,
                        generation: observationGeneration
                      ) else {
                    return
                }
                switch state {
                case .dismissed:
                    await self.observedActivityBecameInactive(
                        activityID: observedActivityID,
                        dismissed: true
                    )
                    return
                case .ended:
                    await self.observedActivityBecameInactive(
                        activityID: observedActivityID,
                        dismissed: false
                    )
                    return
                default:
                    continue
                }
            }
        }
    }

    private func stopActivityObservation(
        cancelActivityStateTask: Bool = true
    ) {
        activityObservationGeneration &+= 1
        if cancelActivityStateTask {
            activityStateTask?.cancel()
        }
        activityStateTask = nil
    }

    private func isCurrentActivityObservation(
        activityID: String,
        generation: Int
    ) -> Bool {
        activityObservationGeneration == generation &&
            activity?.id == activityID
    }

    private func releaseInactiveActivity(
        _ inactiveActivity:
            Activity<CICaptionActivityAttributes>
    ) async {
        let activityID = inactiveActivity.id
        if activity?.id == activityID {
            CIActivityLifetime.log(inactiveActivity, event: "released-inactive",
                reason: requestedEndReasons.removeValue(forKey: activityID)
                    ?? "not updatable during recovery; initiator unknown")
            stopActivityObservation()
            activity = nil
            pendingVerification = nil
        }
    }

    private func observedActivityBecameInactive(
        activityID: String,
        dismissed: Bool
    ) async {
        guard activity?.id == activityID else { return }
        if dismissed {
            dismissedVideoID = videoID
        }
        stopActivityObservation(cancelActivityStateTask: false)
        guard activity?.id == activityID else { return }
        if let current = activity {
            CIActivityLifetime.log(current, event: dismissed ? "observed-dismissed" : "observed-ended",
                reason: requestedEndReasons.removeValue(forKey: activityID)
                    ?? "ActivityKit state change; initiator unknown; observation time may be delayed")
        }
        activity = nil
        pendingVerification = nil
        let lifecycleDescription = dismissed
            ? "Live Activity was dismissed"
            : "Live Activity ended"
        CIActivityBridge.emit(
            level: "info",
            message: "\(lifecycleDescription)."
        )
    }

    func update(
        line: String,
        source: String,
        cueStartMS: Int,
        cueEndMS: Int,
        nextLine: String,
        nextCueStartMS: Int,
        nextCueEndMS: Int,
        position: Double,
        isPlaying: Bool
    ) async {
        guard hasUpdatableActivity() else {
            if !didLogMissingActivity {
                didLogMissingActivity = true
                CIActivityBridge.emit(
                    level: "warning",
                    message: "Skipped lyric update because no Live Activity is active"
                )
            }
            return
        }
        guard line != lastLine ||
              source != lastSource ||
              cueStartMS != lastCueStartMS ||
              cueEndMS != lastCueEndMS ||
              nextLine != lastNextLine ||
              nextCueStartMS != lastNextCueStartMS ||
              nextCueEndMS != lastNextCueEndMS ||
              isPlaying != lastPlaying else { return }
        let shouldReportSource = lastLine.isEmpty || source != lastSource
        revision += 1
        lastLine = line
        lastSource = source
        lastCueStartMS = cueStartMS
        lastCueEndMS = cueEndMS
        lastNextLine = nextLine
        lastNextCueStartMS = nextCueStartMS
        lastNextCueEndMS = nextCueEndMS
        lastPlaying = isPlaying
        let state = CICaptionActivityAttributes.ContentState(
            line: line,
            source: source,
            videoID: videoID,
            videoTitle: title,
            isPlaying: isPlaying,
            cueStartMS: cueStartMS,
            cueEndMS: cueEndMS,
            nextLine: nextLine.isEmpty ? nil : nextLine,
            nextCueStartMS: nextLine.isEmpty ? nil : nextCueStartMS,
            nextCueEndMS: nextLine.isEmpty ? nil : nextCueEndMS,
            revision: revision
        )
        // Cue transitions are submitted by the host's background-audio clock.
        // staleDate only marks content as out of date; it is not a WidgetKit
        // render scheduler and must not be used to promote the next line.
        _ = position
        await updateState(state)
        if shouldReportSource {
            CIActivityBridge.emit(
                level: "info",
                message: "Live Activity is displaying source "
                    + (source.isEmpty ? "unlabeled captions" : source)
            )
        }
    }

    func showGap(title: String) async {
        if !title.isEmpty { self.title = title }
        guard hasUpdatableActivity(), lastLine != "♪" else { return }
        lastLine = "♪"
        lastSource = ""
        lastCueStartMS = 0
        lastCueEndMS = 0
        lastNextLine = ""
        lastNextCueStartMS = 0
        lastNextCueEndMS = 0
        lastPlaying = true
        revision += 1
        await updateState(
            CICaptionActivityAttributes.ContentState(
                line: "♪",
                source: "",
                videoID: videoID,
                videoTitle: self.title,
                isPlaying: true,
                cueStartMS: 0,
                cueEndMS: 0,
                revision: revision
            )
        )
    }

    func end(immediately: Bool, reason: String = "presenter end request") async {
        let endingActivity = activity
        if let endingActivity {
            await endActivity(endingActivity, immediately: immediately, reason: reason)
        }
        stopActivityObservation()
        self.activity = nil
        self.videoID = ""
        self.lastLine = ""
        self.lastSource = ""
        self.lastCueStartMS = 0
        self.lastCueEndMS = 0
        self.lastNextLine = ""
        self.lastNextCueStartMS = 0
        self.lastNextCueEndMS = 0
        self.lastPlaying = true
        self.dismissedVideoID = ""
        self.didLogMissingActivity = false
        self.lastUpdateHeartbeatUptime = 0
        self.pendingVerification = nil
        if endingActivity != nil {
            CIActivityBridge.emit(level: "info", message: "Ended native Live Activity")
        }
    }

    private func waitingState() -> CICaptionActivityAttributes.ContentState {
        CICaptionActivityAttributes.ContentState(
            line: activityText(
                traditionalChinese: "正在取得字幕…",
                english: "Loading captions…",
                japanese: "字幕を取得中…"
            ),
            source: "",
            videoID: videoID,
            videoTitle: title,
            isPlaying: true,
            cueStartMS: 0,
            cueEndMS: 0,
            revision: revision
        )
    }

    private func updateState(
        _ state: CICaptionActivityAttributes.ContentState
    ) async {
        guard let activity, isUpdatable(activity) else { return }
        let safeState = boundedState(state, attributes: activity.attributes)
        let content = ActivityContent(
            state: safeState,
            staleDate: nil,
            relevanceScore: 1
        )
        // Use the baseline ActivityKit update API because some standalone
        // Theos iOS 17.5 SDK distributions don't expose the newer timestamp
        // overload in their Swift interface. Revision remains part of every
        // state, so rapid cue changes are still distinct and ordered.
        verifyPreviousSubmission(activity: activity)
        await activity.update(content)
        guard self.activity?.id == activity.id, isUpdatable(activity) else {
            pendingVerification = nil
            return
        }
        pendingVerification = (
            activityID: activity.id,
            revision: safeState.revision,
            source: safeState.source.isEmpty ? "gap" : safeState.source,
            uptime: ProcessInfo.processInfo.systemUptime
        )
        let uptime = ProcessInfo.processInfo.systemUptime
        if uptime - lastUpdateHeartbeatUptime >= 30 {
            lastUpdateHeartbeatUptime = uptime
            CIActivityBridge.emit(
                level: "info",
                message: "Live Activity update pipeline is active at revision "
                    + "\(safeState.revision) (\(activity.activityState))"
            )
        }
    }

    /// Reports whether the previously submitted revision actually landed.
    ///
    /// `Activity.update(_:)` never throws and stays completely silent when
    /// liveactivitiesd refuses the write, which is exactly what happens once
    /// the process is classified as background-media-only. Reading the stored
    /// revision back is the only way to tell — but reading it immediately
    /// after `update(_:)` races the daemon round-trip and reports rejections
    /// that never happened, so the check is deferred until the next cue.
    private func verifyPreviousSubmission(
        activity: Activity<CICaptionActivityAttributes>
    ) {
        guard let pending = pendingVerification else { return }
        guard pending.activityID == activity.id else {
            pendingVerification = nil
            return
        }
        // Back-to-back revisions land within milliseconds of each other and
        // would hit the same propagation race. Drop those rather than log a
        // verdict that cannot be trusted.
        guard ProcessInfo.processInfo.systemUptime - pending.uptime >= 0.4
        else {
            pendingVerification = nil
            return
        }
        pendingVerification = nil
        let storedRevision = Activity<CICaptionActivityAttributes>.activities
            .first { $0.id == activity.id }?
            .content.state.revision
        if storedRevision == pending.revision {
            CIActivityBridge.emit(
                level: "info",
                message: "Caption reached the Live Activity: revision "
                    + "\(pending.revision) (\(pending.source))"
            )
        } else {
            CIActivityBridge.emit(
                level: "warning",
                message: "Live Activity did not accept revision "
                    + "\(pending.revision) (\(pending.source)); the system "
                    + "still reports "
                    + (storedRevision.map { "revision \($0)" }
                        ?? "no matching activity")
            )
        }
    }

    private func boundedState(
        _ initialState: CICaptionActivityAttributes.ContentState,
        attributes explicitAttributes: CICaptionActivityAttributes? = nil
    ) -> CICaptionActivityAttributes.ContentState {
        let attributes = explicitAttributes ??
            activity?.attributes ??
            CICaptionActivityAttributes(
                sessionID: Self.sessionID
            )
        var state = initialState
        let originalState = initialState

        func encodedSize(
            _ candidate: CICaptionActivityAttributes.ContentState
        ) -> Int {
            let envelope = PayloadEnvelope(
                attributes: attributes,
                state: candidate
            )
            return (try? JSONEncoder().encode(envelope).count) ?? Int.max
        }

        for _ in 0..<16 {
            if encodedSize(state) <= 3_200 { break }
            let lineBytes = state.line.utf8.count
            let nextLineBytes = state.nextLine?.utf8.count ?? 0
            let titleBytes = state.videoTitle.utf8.count
            let videoIDBytes = state.videoID.utf8.count
            let sourceBytes = state.source.utf8.count
            if lineBytes > 128 {
                state.line = clippedUTF8(
                    state.line,
                    maximumBytes: max(128, lineBytes * 3 / 4)
                )
            } else if nextLineBytes > 96, let nextLine = state.nextLine {
                state.nextLine = clippedUTF8(
                    nextLine,
                    maximumBytes: max(96, nextLineBytes * 3 / 4)
                )
            } else if titleBytes > 64 {
                state.videoTitle = clippedUTF8(
                    state.videoTitle,
                    maximumBytes: max(64, titleBytes * 3 / 4)
                )
            } else if videoIDBytes > 32 {
                state.videoID = clippedUTF8(
                    state.videoID,
                    maximumBytes: max(32, videoIDBytes * 3 / 4)
                )
            } else if sourceBytes > 16 {
                state.source = clippedUTF8(
                    state.source,
                    maximumBytes: max(16, sourceBytes * 3 / 4)
                )
            } else {
                break
            }
        }

        if encodedSize(state) > 3_200 {
            state.line = "…"
            state.nextLine = nil
            state.nextCueStartMS = nil
            state.nextCueEndMS = nil
            state.source = ""
            state.videoID = clippedUTF8(state.videoID, maximumBytes: 32)
            state.videoTitle = clippedUTF8(state.videoTitle, maximumBytes: 48)
        }
        if state != originalState {
            CIActivityBridge.emit(
                level: "warning",
                message: "Live Activity payload was shortened to stay below 4 KB"
            )
        }
        return state
    }

    private func isUpdatable(_ candidate: Activity<CICaptionActivityAttributes>) -> Bool {
        switch candidate.activityState {
        case .active, .stale: return true
        default: return false
        }
    }

    private func hasUpdatableActivity() -> Bool {
        guard let activity else { return false }
        switch activity.activityState {
        case .active, .stale:
            return true
        case .dismissed:
            CIActivityLifetime.log(activity, event: "detected-dismissed",
                reason: requestedEndReasons.removeValue(forKey: activity.id)
                    ?? "detected before next update; initiator unknown")
            dismissedVideoID = videoID
            self.activity = nil
            pendingVerification = nil
            stopActivityObservation()
            CIActivityBridge.emit(
                level: "info",
                message: "Live Activity was dismissed by the user or system"
            )
            return false
        case .ended:
            CIActivityLifetime.log(activity, event: "detected-ended",
                reason: requestedEndReasons.removeValue(forKey: activity.id)
                    ?? "detected before next update; initiator unknown")
            self.activity = nil
            pendingVerification = nil
            stopActivityObservation()
            return false
        default:
            return false
        }
    }

    private func endActivity(
        _ activity: Activity<CICaptionActivityAttributes>,
        immediately: Bool,
        reason: String
    ) async {
        requestedEndReasons[activity.id] = reason
        if requestedEndReasons.count > 32 { requestedEndReasons = [activity.id: reason] }
        CIActivityLifetime.log(activity, event: "app-end-request", reason: reason)
        let finalState = CICaptionActivityAttributes.ContentState(
            line: lastLine.isEmpty
                ? activityText(
                    traditionalChinese: "播放結束",
                    english: "Playback ended",
                    japanese: "再生終了"
                )
                : lastLine,
            source: lastSource,
            videoID: videoID,
            videoTitle: title,
            isPlaying: false,
            cueStartMS: 0,
            cueEndMS: 0,
            revision: revision + 1
        )
        let state = boundedState(
            finalState,
            attributes: activity.attributes
        )
        let policy: ActivityUIDismissalPolicy = immediately ? .immediate : .default
        await activity.end(
            ActivityContent(state: state, staleDate: nil),
            dismissalPolicy: policy
        )
    }
}
