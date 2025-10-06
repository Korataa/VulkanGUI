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

public extension Element {
    var center: Vector2 { bounds.center }

    mutating func addChild(_ child: Element) { 
        children.append(child) 
    }

    func layout(in size: Vector2) {

    }

    //Generate quads for this element and its children recursively
    func generateQuads() -> [Quad] {

    }
    
}