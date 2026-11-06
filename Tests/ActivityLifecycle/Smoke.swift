private let testDomain = "CaptionIsland.LifecycleSmoke.\(UUID().uuidString)"
private let testDefaults = UserDefaults(suiteName: testDomain)!
private final class LogCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ line: String) { lock.lock(); defer { lock.unlock() }; lines.append(line) }
    func text() -> String { lock.lock(); defer { lock.unlock() }; return lines.joined(separator: "\n") }
}
@main private struct LifecycleSmoke {
    typealias CaptionActivity = Activity<CICaptionActivityAttributes>
    static func check(_ condition: Bool, _ message: String) {
        if !condition { fatalError("FAIL: \(message)") }
    }
    static func fixture(_ state: ActivityState, revision: Int = 13) -> CaptionActivity {
        let activity = CaptionActivity(attributes: .init(sessionID: "caption-island-local-v1"),
            content: ActivityContent(state: .init(line: "old", source: "LRCLIB", videoID: "old-video",
                videoTitle: "Old", isPlaying: true, cueStartMS: 0, cueEndMS: 0, revision: revision), staleDate: nil))
        activity.activityState = state
        return activity
    }
    static func pause() async { try? await Task.sleep(nanoseconds: 30_000_000) }
    static func main() async {
        defer { testDefaults.removePersistentDomain(forName: testDomain) }
        let logs = LogCapture()
        let token = NotificationCenter.default.addObserver(forName: Notification.Name("CIActivityBridgeLogNotification"),
            object: nil, queue: nil) { notification in
                if let line = notification.userInfo?["message"] as? String { logs.add(line) }
            }
        defer { NotificationCenter.default.removeObserver(token) }
        let ended = fixture(.ended), dismissed = fixture(.dismissed)
        CaptionActivity.activities = [ended, dismissed]
        let manager = CIActivityManager()
        await MainActor.run { UIApplication.shared.applicationState = .background }
        await manager.ensure(videoID: "B", title: "New")
        await manager.ensure(videoID: "B", title: "New")
        check(CaptionActivity.requestCount == 0, "background terminal activity waits for foreground")
        await MainActor.run { UIApplication.shared.applicationState = .active }
        await manager.ensure(videoID: "B", title: "New")
        let replacement = CaptionActivity.activities.last!
        check(CaptionActivity.requestCount == 1 && replacement.id != ended.id,
              "foreground requests new activity instead of readopting ended/dismissed entries")
        await manager.ensure(videoID: "B", title: "New")
        check(CaptionActivity.requestCount == 1, "repeated foreground ensure does not duplicate")
        await manager.update(line: "new lyric", source: "LRCLIB", cueStartMS: 1, cueEndMS: 2,
            nextLine: "", nextCueStartMS: 0, nextCueEndMS: 0, position: 1, isPlaying: true)
        check(replacement.content.state.videoID == "B" && replacement.content.state.line == "new lyric",
              "new activity receives current video's lyric")
        replacement.activityState = .ended
        await pause()
        await manager.ensure(videoID: "B", title: "New")
        check(CaptionActivity.requestCount == 2, "same video recovers after terminal state without app restart")
        await manager.end(immediately: true, reason: "test playback stopped")
        await pause()
        let stale = fixture(.stale, revision: 42)
        CaptionActivity.activities = [ended, stale]
        let adoptingManager = CIActivityManager()
        await adoptingManager.ensure(videoID: "C", title: "Third")
        check(stale.content.state.revision == 43 && stale.content.state.videoID == "C",
              "stale is updatable, adoption keeps revision monotonic and selects correct entry")
        stale.activityState = .dismissed
        await pause()
        await adoptingManager.ensure(videoID: "C", title: "Third")
        check(CaptionActivity.requestCount == 2, "same-video dismissal is respected")
        await adoptingManager.ensure(videoID: "D", title: "Fourth")
        check(CaptionActivity.requestCount == 3, "a different video may create after dismissal")
        await adoptingManager.end(immediately: true)
        let racing = fixture(.active)
        racing.endOnNextUpdate = true
        CaptionActivity.activities = [racing, ended]
        let racingManager = CIActivityManager()
        await racingManager.ensure(videoID: "E", title: "Race")
        check(CaptionActivity.requestCount == 4 && CaptionActivity.activities.last!.id != racing.id,
              "activity ending during adoption is replaced, never reported as adopted")
        // A separately constructed manager can recover the persisted date.
        let latest = CaptionActivity.activities.last!
        let lifetime = CIActivityLifetime.description(latest.id)
        check(lifetime.contains("created=") && !lifetime.contains("unknown"), "creation date stored by ID")
        let secondManager = CIActivityManager()
        await secondManager.ensure(videoID: "E", title: "Race")
        check(CaptionActivity.requestCount == 4 && CIActivityLifetime.description(latest.id).contains("created="),
              "adoption across manager lifetime preserves original creation date")
        await secondManager.end(immediately: true, reason: "settings disabled")
        await pause()
        let currentRace = fixture(.active)
        CaptionActivity.activities = [currentRace]
        let currentManager = CIActivityManager()
        await currentManager.ensure(videoID: "F", title: "Current")
        currentRace.endOnNextUpdate = true
        let beforeRace = CaptionActivity.requestCount
        await currentManager.start(videoID: "G", title: "Changed during reuse")
        check(CaptionActivity.requestCount == beforeRace + 1 &&
              CaptionActivity.activities.last!.content.state.videoID == "G",
              "current activity ending during reuse is also replaced")
        await pause()
        let text = logs.text()
        check(text.contains("event=ignored-inactive") && text.contains("event=created") &&
              text.contains("event=observed-ended") && text.contains("initiator unknown"),
              "lifecycle logs distinguish observed terminal state and creation")
        check(text.contains("event=app-end-request") && text.contains("reason=settings disabled") &&
              text.contains("age=") && text.contains("created=unknown age=unknown"),
              "explicit end reason and known/unknown lifetime are logged")
        check(!text.contains("did not accept revision"), "verification does not leak across activities")
        print("PASS: terminal filtering, background deferral, foreground recovery, revision continuity, dismissal, adoption race, and lifecycle diagnostics")
    }
}
