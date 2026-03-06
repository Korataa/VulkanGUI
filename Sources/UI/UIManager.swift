import Core
import Graphics
public class UIManager {
    private let graphics: Graphics
    private var rootElement: Element?
    private var screenBounds: Rectangle
    private var needsRebuild: Bool = false
    private var cachedRenderables: [UIRenderable] = []
    private var hasInitializedUI: Bool = false
    
    public init(graphics: Graphics, screenBounds: Rectangle? = nil) {
        self.graphics = graphics
        self.screenBounds = screenBounds ?? Rectangle(position: Vector2(0, 0), width: 800, height: 600)
    }
    
    /// Set the root UI element - this triggers automatic rendering
    public func setRoot(_ element: Element) {
        rootElement = element
        needsRebuild = true
    }
    
    /// Update screen bounds (when window resizes)
    public func setScreenBounds(_ bounds: Rectangle) {
        screenBounds = bounds
        needsRebuild = true
    }
    
    /// Call this from your main loop - handles automatic updates
    public func update() {
        if needsRebuild {
            print("🚨 UI REBUILDING - this should only happen once!")
            rebuild()
            needsRebuild = false
        }
        // TEMPORARY FIX: Don't call rebuild() every frame - this was causing massive memory leak!
    }
    
    /// Force a UI rebuild (for reactive state changes)
    public func markNeedsRebuild() {
        needsRebuild = true
    }
    
    /// Internal: Rebuild the entire UI with smart caching
    private func rebuild() {
        guard let root = rootElement else { return }
        
        // Step 1: Perform layout (calculate positions and sizes)
        let layoutedRoot = performLayout(root, in: screenBounds)
        
        // Step 2: Convert to UIRenderables
        let newRenderables = generateRenderables(from: layoutedRoot)
        
        // Step 3: Smart caching - only update graphics if renderables changed
        if hasInitializedUI && renderablesEqual(cachedRenderables, newRenderables) {
            print("♻️ UI unchanged - reusing cached renderables (no GPU upload)")
            return
        }
        
        // UI has changed - update graphics system
        print("🔄 UI changed - updating graphics (\(newRenderables.count) elements)")
        graphics.clearUIElements()
        
        if hasInitializedUI {
            // Reuse existing UIRenderable objects if possible to preserve upload state
            let reusedRenderables = reuseCompatibleRenderables(cachedRenderables, newRenderables)
            reusedRenderables.forEach { graphics.addUIElement($0) }
            cachedRenderables = reusedRenderables
        } else {
            // First time - create new renderables
            newRenderables.forEach { graphics.addUIElement($0) }
            cachedRenderables = newRenderables
            hasInitializedUI = true
        }
        
        print("🎨 UI update complete!")
    }
    
    /// Compare two renderable arrays for equality
    private func renderablesEqual(_ a: [UIRenderable], _ b: [UIRenderable]) -> Bool {
        guard a.count == b.count else { return false }
        for (i, renderable) in a.enumerated() {
            let other = b[i]
            if renderable.position != other.position ||
               renderable.size != other.size ||
               !colorsEqual(renderable.color, other.color) ||
               renderable.textureID != other.textureID {
                return false
            }
        }
        return true
    }
    
    /// Reuse existing UIRenderable objects if they match, to preserve GPU upload state
    private func reuseCompatibleRenderables(_ existing: [UIRenderable], _ new: [UIRenderable]) -> [UIRenderable] {
        guard existing.count == new.count else { return new }
        
        var reused: [UIRenderable] = []
        for (i, newRenderable) in new.enumerated() {
            let existingRenderable = existing[i]
            
            // If they're the same, reuse the existing one (preserves upload state)
            if existingRenderable.position == newRenderable.position &&
               existingRenderable.size == newRenderable.size &&
               colorsEqual(existingRenderable.color, newRenderable.color) &&
               existingRenderable.textureID == newRenderable.textureID {
                reused.append(existingRenderable)
            } else {
                // Different - use the new one
                reused.append(newRenderable)
            }
        }
        return reused
    }
    
    private func colorsEqual(_ a: Color, _ b: Color) -> Bool {
        return a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a
    }
    
    /// Layout algorithm - calculates final bounds for all elements
    private func performLayout(_ element: Element, in bounds: Rectangle) -> Element {
        var layoutedElement = element
        layoutedElement.bounds = bounds
        
        // Simple layout for now - we'll enhance this
        switch element.layoutType {
        case .flex(let direction, _, _):
            layoutedElement.children = layoutFlexChildren(element.children, 
                                                        direction: direction, 
                                                        in: bounds, 
                                                        spacing: element.spacing)
        case .absolute(let position):
            layoutedElement.bounds = Rectangle(position: position, width: bounds.width, height: bounds.height)
        case .grid:
            // Grid layout - implement later
            layoutedElement.children = element.children
        }
        
        return layoutedElement
    }
    
    /// Simple flex layout implementation
    private func layoutFlexChildren(_ children: [Element], 
                                  direction: FlexDirection, 
                                  in bounds: Rectangle, 
                                  spacing: Float) -> [Element] {
        guard !children.isEmpty else { return [] }
        
        var layoutedChildren: [Element] = []
        
        if direction == .column {
            // Vertical layout
            let childHeight = (bounds.height - spacing * Float(children.count - 1)) / Float(children.count)
            var currentY = bounds.position.y
            
            for child in children {
                var layoutedChild = child
                layoutedChild.bounds = Rectangle(position: Vector2(bounds.position.x, currentY), width: bounds.width, height: childHeight)
                layoutedChild = performLayout(layoutedChild, in: layoutedChild.bounds)
                layoutedChildren.append(layoutedChild)
                currentY += childHeight + spacing
            }
        } else {
            // Horizontal layout  
            let childWidth = (bounds.width - spacing * Float(children.count - 1)) / Float(children.count)
            var currentX = bounds.position.x
            
            for child in children {
                var layoutedChild = child
                layoutedChild.bounds = Rectangle(position: Vector2(currentX, bounds.position.y), width: childWidth, height: bounds.height)
                layoutedChild = performLayout(layoutedChild, in: layoutedChild.bounds)
                layoutedChildren.append(layoutedChild)
                currentX += childWidth + spacing
            }
        }
        
        return layoutedChildren
    }
    
    /// Convert layouted elements to UIRenderables
    private func generateRenderables(from element: Element) -> [UIRenderable] {
        var renderables: [UIRenderable] = []
        
        // Generate renderable for this element
        print("🎨 Generating renderable for element: \(element.elementType), bounds: \(element.bounds), backgroundColor: \(String(describing: element.style.backgroundColor))")
        switch element.elementType {
        case .rect(let color, let textureID):
            let renderable = UIRenderable(
                position: SIMD2(element.bounds.center.x, element.bounds.center.y),
                size: SIMD2(element.bounds.width, element.bounds.height),
                color: color,
                textureID: textureID
            )
            renderables.append(renderable)
            
        case .text(_, _):
            // For now, render text as colored rectangles
            // TODO: Implement proper text rendering
            // Use backgroundColor if set, otherwise fall back to textColor
            let color = element.style.backgroundColor ?? element.style.textColor
            print("🎨 Text element: backgroundColor=\(String(describing: element.style.backgroundColor)), textColor=\(element.style.textColor), final=\(color)")
            let renderable = UIRenderable(
                position: SIMD2(element.bounds.center.x, element.bounds.center.y),
                size: SIMD2(element.bounds.width, element.bounds.height),
                color: color,
                textureID: nil
            )
            renderables.append(renderable)
            
        case .container:
            // Containers don't render themselves, just their children
            break
            
        case .custom(let renderer):
            // Custom renderer - convert Quads to UIRenderables
            let quads = renderer(element)
            for quad in quads {
                let renderable = UIRenderable(
                    position: SIMD2(quad.position.x, quad.position.y),
                    size: SIMD2(quad.size.x, quad.size.y),
                    color: quad.color,
                    textureID: quad.textureID
                )
                renderables.append(renderable)
            }
        }
        
        // Recursively generate renderables for children
        for child in element.children {
            renderables.append(contentsOf: generateRenderables(from: child))
        }
        
        return renderables
    }
}