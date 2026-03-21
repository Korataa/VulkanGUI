// Minimal Button component stub (renamed to avoid collisions with declarative API)
public final class ButtonComponent {
    public var text: String
    private var callback: (() -> Void)?

    public init(text: String) {
        self.text = text
    }

    public func onClick(_ cb: @escaping () -> Void) {
        self.callback = cb
    }

    // Lightweight hitTest placeholder; real implementation will depend on CoreAPI types
    public func hitTest(x: Float, y: Float) -> Bool {
        return false
    }

    public func press() {
        callback?()
    }
}
