import Core
import Graphics
import Core
//Simple styling system for ui elements
//Start basic, expand as needed
public struct Style {
    //Visual properties
    public var backgroundColor: Color?
    public var borderColor: Color?
    public var textColor: Color = .white

    //Layout properties
    public var padding: Spacing = Spacing()
    public var margin: Spacing = Spacing()

    public var borderWidth: Float = 0
    public var cornerRadius: Float = 0

    public var fontSize: Float = 14
    //public var font: Font? = nil  //add when i have font system

    public init() {}
}

public struct Spacing {
    public var top: Float = 0
    public var bottom: Float = 0
    public var right: Float = 0
    public var left: Float = 0

    public init(top: Float = 0, bottom: Float = 0, right: Float = 0, left: Float = 0) {
        self.top = top
        self.bottom = bottom
        self.right = right
        self.left = left
    }

    public init(all: Float) {
        self.init(top: all, bottom: all, right: all, left: all)
    }

    public init(vertical: Float, horizontal: Float) {
        self.init(top: vertical , bottom: vertical, right: horizontal, left: horizontal)
    }
}

public extension Style {
    static var `default`: Style { Style() }

    static func background(_ color: Color) -> Style {
        var style = Style()
        style.backgroundColor = color
        return style
    }

    static func text(color: Color, size: Float = 14) -> Style {
        var style = Style()
        style.textColor = color
        style.fontSize = size
        return style
    }

    static func bordered(color: Color, width: Float = 1) -> Style {
        var style = Style()
        style.borderColor = color
        style.borderWidth = width
        return style
    }
}