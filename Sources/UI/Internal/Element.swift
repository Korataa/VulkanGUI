import Core
import Math
import Graphics
// TODO: UI System Integration with Graphics Module
// 
// Current approach: Element generates vertices directly
// Planned approach: Element generates high-level primitives for Graphics
//
// Element should generate UIRenderData containing:
// - quads: [UIQuad] where UIQuad has { position, size, color, textureID }
// - texts: [UIText] where UIText has { text, position, font, color }
//
// Graphics.renderUI(renderData) will convert UIQuads to low-level UIElements:
//   for quad in renderData.quads {
//       let uiElement = UIElement(position: quad.position, size: quad.size, 
//                                color: quad.color, textureID: quad.textureID)
//       addUIElement(uiElement)  // UIElement handles vertices/GPU upload
//   }
//
// This matches the 3D approach: Models -> Graphics (not vertices -> Graphics)
// Benefits: Clean separation, Graphics controls optimization, easier to extend

// Layout system types
public enum LayoutType {
    case flex(direction: FlexDirection, justify: JustifyContent, align: AlignItems)
    case absolute(position: Vector2)
    case grid(columns: Int, rows: Int)
}

public enum FlexDirection {
    case row, column
}

public enum JustifyContent {
    case start, center, end, spaceBetween, spaceAround
}

public enum AlignItems {
    case start, center, end, stretch
}

// Temporary font type (we'll enhance this later)
public struct Font {
    public let name: String
    public let size: Float
    
    public init(name: String, size: Float) {
        self.name = name
        self.size = size
    }
    
    public static func system(size: Float) -> Font {
        return Font(name: "system", size: size)
    }
}

public struct Element {
    public var children: [Element]
    public var bounds: Rectangle
    public var style: Style
    public var elementType: ElementType
    
    // Layout properties
    public var layoutType: LayoutType = .flex(direction: .column, justify: .start, align: .stretch)
    public var spacing: Float = 8.0
    public var padding: Spacing = Spacing()
    
    // Event handlers
    public var tapHandler: (() -> Void)? = nil
    public var hoverHandler: ((Bool) -> Void)? = nil

    public var isDirty: Bool = true

    public init(type: ElementType, bounds: Rectangle = Rectangle.zero, style: Style = Style(), children: [Element] = []) {
        self.elementType = type
        self.bounds = bounds
        self.style = style
        self.children = children
    }
}

public enum ElementType {
    case rect(color: Color, textureID: UInt32? = nil)
    case text(content: String, font: Font? = nil)
    case container
    case custom(renderer: (Element) -> [Quad])
}

public extension Element {
    var center: Vector2 { bounds.center }

    mutating func addChild(_ child: Element) {
        children.append(child)
        markDirty()
    }

    mutating func markDirty() {
        isDirty = true
    }

    //Generate quads for this element and its children recursively
    func generateQuads() -> [Quad] {
        var quads: [Quad] = []

        //Generate quad for this element based on its type
        switch elementType {
            case .rect(let color, let textureID):
                quads.append(Quad(
                    position: bounds.position,
                    size: Vector2(bounds.width, bounds.height),
                    color: color,
                    textureID: textureID
                ))
            case .text(_, _):
                //Text rendering would be more complex -might generate multiple quads
                //for now use a placeholder
                break
            case .container:
                //Container itself doesnt render directly, just its children
                break
            case .custom(let renderer):
                quads.append(contentsOf: renderer(self))
        }

        //recursively collect quads from children
        for child in children {
            quads.append(contentsOf: child.generateQuads())
        }

        return quads
    }

    func layout(in size: Vector2) {
        //layout logic - calculate bounds for children
        //this would be implemnted based on layout type
    }
    
    // Method chaining API for progressive explicitness
    func spacing(_ value: Float) -> Element {
        var copy = self
        copy.spacing = value
        return copy
    }
    
    func padding(_ spacing: Spacing) -> Element {
        var copy = self
        copy.padding = spacing
        return copy
    }
    
    func padding(_ all: Float) -> Element {
        var copy = self
        copy.padding = Spacing(all: all)
        return copy
    }
    
    func background(_ color: Color) -> Element {
        var copy = self
        var styleCopy = copy.style
        styleCopy.backgroundColor = color
        copy.style = styleCopy
        print("[UI DEBUG] .background(_:) called. Set backgroundColor to \(color). Full style: \(copy.style)")
        return copy
    }

    func textColor(_ color: Color) -> Element {
        var copy = self
        var styleCopy = copy.style
        styleCopy.textColor = color
        copy.style = styleCopy
        print("[UI DEBUG] .textColor(_:) called. Set textColor to \(color). Full style: \(copy.style)")
        return copy
    }

    func fontSize(_ size: Float) -> Element {
        var copy = self
        copy.style.fontSize = size
        if case .text(let content, _) = copy.elementType {
            copy.elementType = .text(content: content, font: Font.system(size: size))
        }
        return copy
    }

    // Positive values make text bolder, negative values make text thinner.
    func textWeight(_ value: Float) -> Element {
        var copy = self
        copy.style.textWeight = value
        return copy
    }

    func textOutline(width: Float, color: Color = .black) -> Element {
        var copy = self
        copy.style.textOutlineWidth = max(0.0, width)
        copy.style.textOutlineColor = color
        return copy
    }

    func textShadow(offset: Vector2 = Vector2(1.5, 1.5), color: Color = Color(0, 0, 0, 160)) -> Element {
        var copy = self
        copy.style.textShadowOffset = offset
        copy.style.textShadowColor = color
        return copy
    }

    // Glow is rendered as an animated outline ring around glyph edges.
    func textGlow(strength: Float, color: Color = Color(120, 220, 255, 200), speed: Float = 2.0) -> Element {
        var copy = self
        copy.style.textGlowStrength = max(0.0, strength)
        copy.style.textGlowColor = color
        copy.style.textGlowSpeed = max(0.0, speed)
        return copy
    }
    
    func onTap(_ handler: @escaping () -> Void) -> Element {
        var copy = self
        copy.tapHandler = handler
        return copy
    }
    
    func layoutType(_ type: LayoutType) -> Element {
        var copy = self
        copy.layoutType = type
        return copy
    }
    
}