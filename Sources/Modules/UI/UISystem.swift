public class UISystem {
    private var rootElements: [Element] = []

    public func addElement(_ element: Element) {
        rootElements.append(element)
    }

    public func generateVertices() -> [Vertex2D]
}