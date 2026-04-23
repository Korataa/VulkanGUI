import Core

// Author-facing component API backed by runtime `Element` nodes.
public final class ButtonComponent: Component {
    public var text: String
    public var key: String?

    private var clickCallback: (() -> Void)?
    private var hoverStartCallback: (() -> Void)?
    private var hoverEndCallback: (() -> Void)?

    public init(text: String, key: String? = nil) {
        self.text = text
        self.key = key
    }

    public func onClick(_ cb: @escaping () -> Void) {
        self.clickCallback = cb
    }

    public func onHoverStart(_ cb: @escaping () -> Void) {
        self.hoverStartCallback = cb
    }

    public func onHoverEnd(_ cb: @escaping () -> Void) {
        self.hoverEndCallback = cb
    }

    public func build() -> Element {
        var element = Element(type: .text(content: text, font: Font.system(size: 14)))
        if let key {
            element = element.id(key)
        }
        if let clickCallback {
            element = element.onTap(clickCallback)
        }
        if let hoverStartCallback {
            element = element.onHoverStart(hoverStartCallback)
        }
        if let hoverEndCallback {
            element = element.onHoverEnd(hoverEndCallback)
        }
        return element
    }
}
