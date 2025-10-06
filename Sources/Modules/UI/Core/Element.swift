public struct Element {
    public var children: [Element]
    public var bounds: Rectangle
    public var style: Style
}

public extension Element {
    var center: Vector2 { bounds.center }

    mutating func addChild(_ child: Element) { 
        children.append(child) 
    }

    func layout(in size: Vector2) {

    }

    func generateVertices() -> [Vertex2D] {
        
    }
    
}