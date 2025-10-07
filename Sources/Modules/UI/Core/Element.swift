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

public struct Element {
    public var children: [Element]
    public var bounds: Rectangle
    public var style: Style
    public var elementType: ElementType

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
            case .text(let content, let font):
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
    
}