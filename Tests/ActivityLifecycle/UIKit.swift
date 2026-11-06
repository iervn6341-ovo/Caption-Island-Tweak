public enum UIApplicationState { case active, inactive, background }
public final class UIApplication {
    public static let shared = UIApplication()
    public var applicationState: UIApplicationState = .active
}
