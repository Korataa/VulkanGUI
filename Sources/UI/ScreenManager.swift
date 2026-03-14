// Simple ScreenManager stub - lightweight and dependency-free for now
public final class ScreenManager {
    private var screens: [Any] = []

    public init() {}

    public func push(_ screen: Any) {
        screens.append(screen)
    }

    public func pop() {
        _ = screens.popLast()
    }

    public func top() -> Any? {
        return screens.last
    }
}
