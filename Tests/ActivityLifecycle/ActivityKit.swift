// Offline ActivityKit double: intentionally keeps ended objects in activities.
import Foundation
public protocol ActivityAttributes: Codable {
    associatedtype ContentState: Codable & Hashable
}
public enum ActivityState { case active, stale, ended, dismissed, pending }
public enum ActivityUIDismissalPolicy { case immediate, `default` }
public enum PushType { case token }
public struct ActivityContent<State> {
    public var state: State
    public init(state: State, staleDate: Date?, relevanceScore: Double = 0) { self.state = state }
}
private var storage: [String: Any] = [:]
private var requests = 0
public final class Activity<A: ActivityAttributes> {
    public typealias ContentState = A.ContentState
    public let id = UUID().uuidString
    public let attributes: A
    public var content: ActivityContent<A.ContentState>
    public var endOnNextUpdate = false
    private var continuations: [AsyncStream<ActivityState>.Continuation] = []
    public var activityState: ActivityState = .active {
        didSet { for continuation in continuations { continuation.yield(activityState) } }
    }
    public var activityStateUpdates: AsyncStream<ActivityState> {
        AsyncStream { continuation in
            continuations.append(continuation)
            continuation.yield(activityState)
        }
    }
    public static var activities: [Activity<A>] {
        get { storage[String(reflecting: A.self)] as? [Activity<A>] ?? [] }
        set { storage[String(reflecting: A.self)] = newValue }
    }
    public static var requestCount: Int { requests }
    public init(attributes: A, content: ActivityContent<A.ContentState>) {
        self.attributes = attributes; self.content = content
    }
    public static func request(attributes: A, content: ActivityContent<A.ContentState>, pushType: PushType?) throws -> Activity<A> {
        requests += 1
        let activity = Activity(attributes: attributes, content: content)
        activities.append(activity)
        return activity
    }
    public func update(_ content: ActivityContent<A.ContentState>) async {
        if endOnNextUpdate { endOnNextUpdate = false; activityState = .ended }
        if activityState == .active || activityState == .stale { self.content = content }
    }
    public func end(_ content: ActivityContent<A.ContentState>?, dismissalPolicy: ActivityUIDismissalPolicy) async {
        if let content { self.content = content }; activityState = .ended
    }
}
public final class ActivityAuthorizationInfo {
    public init() {}
    public var areActivitiesEnabled: Bool { true }
}
