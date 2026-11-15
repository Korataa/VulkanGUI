import Foundation
import Core
import Graphics
import Math
import Logging

protocol UIRendering: AnyObject {
    func replaceUIElements(in group: UIElementGroup, with elements: [Renderable2D])
    func createUITextureRGBA(width: Int, height: Int, pixels: [UInt8], srgb: Bool) -> UInt32?
    func createUITextureR8(width: Int, height: Int, pixels: [UInt8]) -> UInt32?
    func setUITextSDFParameters(threshold: Float, range: Float)
    func setUITextTrueSDFMode(_ enabled: Bool)
    func setUITextMSDFMode(_ enabled: Bool)
}

extension Graphics: UIRendering {}

public class UIManager {
    private struct HitTestResult {
        let element: Element
        let interactionID: String
    }

    private final class Node {
        var element: Element
        let region: ReactiveRegion?
        let replacesElement: Bool
        var children: [Node]
        var layouted: Element?
        var ownRenderables: [Renderable2D] = []
        var renderables: [Renderable2D] = []
        var needsOwnRender = true
        var needsUpdate = true
        weak var parent: Node?

        init(_ element: Element, parent: Node? = nil) {
            self.element = element
            self.parent = parent
            if let binding = element.reactiveText {
                self.region = ReactiveRegion {
                    var resolved = element
                    resolved.reactiveText = nil
                    let text = binding()
                    if case .text(_, let font) = resolved.elementType {
                        resolved.elementType = .text(content: text, font: font)
                    } else {
                        resolved.elementType = .text(content: text, font: Font.system(size: 14))
                    }
                    return resolved
                }
                self.replacesElement = true
                self.children = []
            } else if let content = element.dynamicContent {
                self.region = ReactiveRegion(content)
                self.replacesElement = false
                self.children = []
            } else {
                self.region = nil
                self.replacesElement = false
                self.children = []
            }
            region?.onInvalidate = { [weak self] in self?.invalidate() }
            if region == nil {
                children = element.children.map { Node($0, parent: self) }
            }
        }

        func invalidate() {
            if !needsUpdate {
                needsUpdate = true
                parent?.invalidate()
            }
        }
    }

    private var graphics: any UIRendering
    private let elementGroup = UIElementGroup()
    private var rootElement: Element?
    private var rootNode: Node?
    private var layoutedRootElement: Element?
    private var needsRebuild: Bool = true
    private var screenBounds: Rectangle = Rectangle(position: Vector2(0, 0), width: 800, height: 600)
    private var uiTimeSeconds: Float = 0.0
    private var hasInitializedUI: Bool = false
    private var cachedRenderables: [Renderable2D] = []
    private var hasAnimatedTextGlow: Bool = false
    private var textRenderer: TextRenderer?
    private var sdfTextureID: UInt32?
    private var textUsesMSDF: Bool = false
    private var useAnimatedTextGlow: Bool = false
    private var useSDFScaleComparisonOverlay: Bool = false
    private var useTrueSDFTextMode: Bool = false

    //INPUT VARIABLES
    private var previousMousePosition = Vector2(0,0)
    private var currentMousePosition = Vector2(0,0)
    private var hoveredElement: Element?
    private var hoveredElementID: String?
    private var isMousePressed: Bool = false
    private var wasMousePressed: Bool = false


    public init(graphics: Graphics) {
        self.graphics = graphics
    }

    init(renderer: any UIRendering) {
        self.graphics = renderer
    }

    public func setRoot(_ element: Element) {
        rootElement = element
        needsRebuild = true
    }

    public func setScreenBounds(_ bounds: Rectangle) {
        screenBounds = bounds
    }

    public func update() {
        uiTimeSeconds += (1.0 / 60.0)
        if let root = rootElement {
            logTrace(.ui, source: "UIManager", "update root: \(root.elementType), children: \(root.children.count)")
        }
        if needsRebuild {
            logDebug(.ui, source: "UIManager", "UI rebuilding")
            rootNode = rootElement.map { Node($0) }
            hasAnimatedTextGlow = false
            needsRebuild = false
        }
        guard let rootNode else { return }
        if updateNode(rootNode, in: screenBounds, layout: true) {
            layoutedRootElement = rootNode.layouted
            updateGraphics(rootNode.renderables)
        }
    }

    public func markNeedsRebuild() {
        needsRebuild = true
    }

    private func updateGraphics(_ newRenderables: [Renderable2D]) {
        if hasInitializedUI && renderablesEqual(cachedRenderables, newRenderables) {
            logTrace(.ui, source: "UIManager", "UI unchanged - reusing cached renderables")
            return
        }
        logDebug(.ui, source: "UIManager", "UI changed - updating graphics (\(newRenderables.count) elements)")
        let renderables = hasInitializedUI
            ? reuseCompatibleRenderables(cachedRenderables, newRenderables)
            : newRenderables
        graphics.replaceUIElements(in: elementGroup, with: renderables)
        cachedRenderables = renderables
        hasInitializedUI = true
        logTrace(.ui, source: "UIManager", "UI update complete")
    }

    private func renderablesEqual(_ a: [Renderable2D], _ b: [Renderable2D]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).allSatisfy { Self.renderablesMatch($0, $1) }
    }

    private func reuseCompatibleRenderables(_ existing: [Renderable2D], _ new: [Renderable2D]) -> [Renderable2D] {
        guard existing.count == new.count else { return new }

        var reused: [Renderable2D] = []
        for (i, newRenderable) in new.enumerated() {
            let existingRenderable = existing[i]
            
            // If they're the same, reuse the existing one (preserves upload state)
            if Self.renderablesMatch(existingRenderable, newRenderable) {
                reused.append(existingRenderable)
            } else {
                // Different - use the new one
                reused.append(newRenderable)
            }
        }
        return reused
    }

    static func renderablesMatch(_ a: Renderable2D, _ b: Renderable2D) -> Bool {
        guard a.position == b.position, a.size == b.size, a.color == b.color,
              a.textureID == b.textureID, a.usesSDF == b.usesSDF,
              a.sdfThreshold == b.sdfThreshold, a.sdfRange == b.sdfRange,
              a.outlineWidth == b.outlineWidth, a.outlineColor == b.outlineColor,
              a.glowColor == b.glowColor, a.glowWidth == b.glowWidth,
              a.shadowColor == b.shadowColor, a.shadowOffset == b.shadowOffset,
              a.indices == b.indices, a.vertices.count == b.vertices.count else {
            return false
        }
        return zip(a.vertices, b.vertices).allSatisfy {
            $0.position == $1.position && $0.texCoord == $1.texCoord && $0.color == $1.color
        }
    }

    private func updateNode(_ node: Node, in proposedBounds: Rectangle, layout: Bool) -> Bool {
        var bounds = layout ? proposedBounds : node.element.bounds
        if layout, case .absolute(let position) = node.element.layoutType {
            bounds.position = position
        }
        guard node.needsUpdate || !sameBounds(node.layouted?.bounds, bounds) else { return false }
        node.needsUpdate = false

        if let region = node.region, region.isDirty {
            let content = region.evaluate()
            if node.replacesElement {
                node.element = content
                node.children = content.children.map { Node($0, parent: node) }
                node.needsOwnRender = true
            } else {
                node.children = [Node(content, parent: node)]
            }
        }

        bounds = layout ? proposedBounds : node.element.bounds
        if layout, case .absolute(let position) = node.element.layoutType {
            bounds.position = position
        }
        let ownChanged = node.needsOwnRender || !sameBounds(node.layouted?.bounds, bounds)

        var childrenChanged = false
        let count = node.children.count
        var currentX = bounds.position.x
        var currentY = bounds.position.y
        for child in node.children {
            var childBounds = child.element.bounds
            var layoutChild = false
            if layout, case .flex(let direction, _, _) = node.element.layoutType {
                layoutChild = true
                if direction == .column {
                    let height = (bounds.height - node.element.spacing * Float(count - 1)) / Float(count)
                    childBounds = Rectangle(
                        position: Vector2(bounds.position.x, currentY),
                        width: bounds.width, height: height
                    )
                    currentY += height + node.element.spacing
                } else {
                    let width = (bounds.width - node.element.spacing * Float(count - 1)) / Float(count)
                    childBounds = Rectangle(
                        position: Vector2(currentX, bounds.position.y),
                        width: width, height: bounds.height
                    )
                    currentX += width + node.element.spacing
                }
            }
            if updateNode(child, in: childBounds, layout: layoutChild) {
                childrenChanged = true
            }
        }

        guard ownChanged || childrenChanged else { return false }
        var layouted = node.element
        layouted.bounds = bounds
        layouted.children = node.children.compactMap(\.layouted)
        node.layouted = layouted
        if ownChanged || (childrenChanged && isCustom(node.element)) {
            node.ownRenderables = generateOwnRenderables(from: layouted)
            node.needsOwnRender = false
        }
        node.renderables = node.ownRenderables + node.children.flatMap(\.renderables)
        return true
    }

    private func isCustom(_ element: Element) -> Bool {
        if case .custom = element.elementType { return true }
        return false
    }

    private func sameBounds(_ previous: Rectangle?, _ current: Rectangle) -> Bool {
        guard let previous else { return false }
        return previous.position.x == current.position.x && previous.position.y == current.position.y &&
            previous.width == current.width && previous.height == current.height
    }

    /// Convert one layouted element to its renderables.
    private func generateOwnRenderables(from element: Element) -> [Renderable2D] {
        var renderables: [Renderable2D] = []
        
        // Generate renderable for this element
        logTrace(.ui, source: "UIManager", "Generating renderable for \(element.elementType), bounds: \(element.bounds)")
        switch element.elementType {
        case .rect(let color, let textureID):
            let renderable = Renderable2D(
                position: SIMD2(element.bounds.center.x, element.bounds.center.y),
                size: SIMD2(element.bounds.width, element.bounds.height),
                color: color,
                textureID: textureID
            )
            renderables.append(renderable)

        case .text(let content, let font):

            if let bg = element.style.backgroundColor {
                renderables.append(Renderable2D(
                    position: SIMD2(element.bounds.center.x, element.bounds.center.y),
                    size: SIMD2(element.bounds.width, element.bounds.height),
                    color: bg,
                    textureID: nil
                ))
            }

            if ensureSDFTextResources(), let textRenderer = textRenderer, let textureID = sdfTextureID {
                let textColor = element.style.textColor
                let requestedSize = max(8.0, font?.size ?? element.style.fontSize)
                let scale = requestedSize / max(1.0, textRenderer.atlas.fontSize)
                let measuredWidth = textRenderer.measureTextWidth(content, scale: scale)
                let startX = element.bounds.position.x + max(0.0, (element.bounds.width - measuredWidth) * 0.5)
                let baselineY = element.bounds.position.y + (element.bounds.height * 0.5) + (requestedSize * 0.35)

                let baseThreshold = max(0.1, min(0.9, 0.5 - element.style.textWeight))
                let glowStrength = max(0.0, element.style.textGlowStrength)
                let glowSpeed = max(0.0, element.style.textGlowSpeed)
                if useAnimatedTextGlow && glowStrength > 0.0 {
                    hasAnimatedTextGlow = true
                }

                func applyTextMaterial(_ glyphs: inout [Renderable2D], outlineWidth: Float, outlineColor: Color, threshold: Float, range: Float, glowStrength: Float, glowSpeed: Float) {
                    for index in glyphs.indices {
                        glyphs[index].sdfThreshold = 0.5; // Force for debug
                        glyphs[index].sdfRange = 4.0;      // Force for debug
                        glyphs[index].outlineWidth = max(0.0, outlineWidth);
                        glyphs[index].outlineColor = outlineColor;
                        glyphs[index].baseOutlineWidth = max(0.0, outlineWidth);
                        glyphs[index].glowStrength = glowStrength;
                        glyphs[index].glowSpeed = glowSpeed;
                        glyphs[index].reserved2 = 1.0; // Ensure MSDF path is used
                    }
                }

                    var shadowRenderables: [Renderable2D] = []
                if element.style.textShadowColor.a > 0 {
                    let shadowStart = SIMD2(
                        startX + element.style.textShadowOffset.x,
                        baselineY + element.style.textShadowOffset.y
                    )
                    shadowRenderables = textRenderer.buildGlyphRenderables(
                        text: content,
                        topLeft: shadowStart,
                        color: element.style.textShadowColor,
                        textureID: textureID,
                        scale: scale
                    )
                    for i in shadowRenderables.indices {
                        shadowRenderables[i].shadowColor = element.style.textShadowColor
                        shadowRenderables[i].shadowOffset = SIMD2<Float>(element.style.textShadowOffset.x, element.style.textShadowOffset.y)
                        shadowRenderables[i].glowColor = Color(255,255,255,0)
                        shadowRenderables[i].glowWidth = 0.0
                    }
                    applyTextMaterial(
                        &shadowRenderables,
                        outlineWidth: 0.0,
                        outlineColor: element.style.textOutlineColor,
                        threshold: baseThreshold,
                        range: textRenderer.atlas.distanceRange,
                        glowStrength: 0.0,
                        glowSpeed: 0.0
                    )
                }

                    var glowRenderables: [Renderable2D] = []
                if glowStrength > 0.0 {
                    let animatedGlow = useAnimatedTextGlow
                        ? (sin(uiTimeSeconds * glowSpeed * 6.28318) * 0.5 + 0.5) * glowStrength
                        : glowStrength
                    let glowThreshold = max(0.05, min(0.95, baseThreshold - animatedGlow))
                    glowRenderables = textRenderer.buildGlyphRenderables(
                        text: content,
                        topLeft: SIMD2(startX, baselineY),
                        color: element.style.textGlowColor,
                        textureID: textureID,
                        scale: scale
                    )
                    for i in glowRenderables.indices {
                        glowRenderables[i].glowColor = element.style.textGlowColor
                        glowRenderables[i].glowWidth = element.style.textGlowStrength
                        glowRenderables[i].shadowColor = Color(0,0,0,0)
                        glowRenderables[i].shadowOffset = SIMD2<Float>(0,0)
                    }
                    applyTextMaterial(
                        &glowRenderables,
                        outlineWidth: 0.0,
                        outlineColor: element.style.textOutlineColor,
                        threshold: glowThreshold,
                        range: textRenderer.atlas.distanceRange,
                        glowStrength: 0.0,
                        glowSpeed: 0.0
                    )
                }

                var glyphRenderables = textRenderer.buildGlyphRenderables(
                    text: content,
                    topLeft: SIMD2(startX, baselineY),
                    color: textColor,
                    textureID: textureID,
                    scale: scale
                )
                for i in glyphRenderables.indices {
                    glyphRenderables[i].glowColor = element.style.textGlowColor
                    glyphRenderables[i].glowWidth = element.style.textGlowStrength
                    glyphRenderables[i].shadowColor = element.style.textShadowColor
                    glyphRenderables[i].shadowOffset = SIMD2<Float>(element.style.textShadowOffset.x, element.style.textShadowOffset.y)
                }
                applyTextMaterial(
                    &glyphRenderables,
                    outlineWidth: element.style.textOutlineWidth,
                    outlineColor: element.style.textOutlineColor,
                    threshold: baseThreshold,
                    range: textRenderer.atlas.distanceRange,
                    glowStrength: 0.0,
                    glowSpeed: 0.0
                )

                renderables.append(contentsOf: shadowRenderables)
                renderables.append(contentsOf: glowRenderables)
                renderables.append(contentsOf: glyphRenderables)

                if useSDFScaleComparisonOverlay && content == "HP: 100" {
                    let samples: [(String, Float, SIMD2<Float>)] = [
                        ("MSDF tiny 8px", 8.0 / max(1.0, textRenderer.atlas.fontSize), SIMD2<Float>(20.0, 36.0)),
                        ("MSDF 1x", scale, SIMD2<Float>(20.0, 80.0)),
                        ("MSDF 4x", scale * 4.0, SIMD2<Float>(20.0, 140.0)),
                        ("MSDF 8x", scale * 8.0, SIMD2<Float>(20.0, 300.0)),
                        ("MSDF 20x", scale * 20.0, SIMD2<Float>(20.0, 520.0))
                    ]
                    for sample in samples {
                        let testRenderables = textRenderer.buildGlyphRenderables(
                            text: sample.0,
                            topLeft: sample.2,
                            color: Color.white,
                            textureID: textureID,
                            scale: sample.1
                        )
                        renderables.append(contentsOf: testRenderables)
                    }
                }
            } else {
                // Fallback path while SDF resources are unavailable.
                let color = element.style.textColor
                let renderable = Renderable2D(
                    position: SIMD2(element.bounds.center.x, element.bounds.center.y),
                    size: SIMD2(element.bounds.width, element.bounds.height),
                    color: color,
                    textureID: nil
                )
                renderables.append(renderable)
            }
            
        case .container:
            // Containers don't render themselves, just their children
            break
            
        case .custom(let renderer):
            // Custom renderer - convert Quads to UIRenderables
            let quads = renderer(element)
            for quad in quads {
                let renderable = Renderable2D(
                    position: SIMD2(quad.position.x, quad.position.y),
                    size: SIMD2(quad.size.x, quad.size.y),
                    color: quad.color,
                    textureID: quad.textureID
                )
                renderables.append(renderable)
            }
        }
        
        return renderables
    }

    private func ensureSDFTextResources() -> Bool {
        if textRenderer != nil && sdfTextureID != nil {
            return true
        }

        guard let assetsPath = getAssetsPath() else {
            print("Failed to resolve assets path for SDF font loading")
            return false
        }

        let msdfJSONPath = "\(assetsPath)/Fonts/JetBrainsMono-msdf.json"
        let msdfImagePath = "\(assetsPath)/Fonts/JetBrainsMono-msdf.png"

        var atlas: FontAtlas
        var textureID: UInt32

        if let msdf = MSDFLoader.load(fromJSON: msdfJSONPath, imagePath: msdfImagePath) {
            print("MSDF font assets loaded")
            atlas = msdf.atlas
            textUsesMSDF = true
            guard let uploadedTextureID = graphics.createUITextureRGBA(
                width: msdf.width,
                height: msdf.height,
                pixels: msdf.rgbaPixels,
                srgb: false
            ) else {
                print("Failed to upload MSDF atlas texture to Vulkan")
                return false
            }
            textureID = uploadedTextureID
        } else {
            print("MSDF assets not found. Falling back to runtime SDF generation.")
            let fontPath = "\(assetsPath)/Fonts/JetBrainsMono-Regular.ttf"
            guard let fontData = try? Data(contentsOf: URL(fileURLWithPath: fontPath)) else {
                print("Failed to load font file at \(fontPath)")
                return false
            }
            print("SDF font file: \(fontPath) (\(fontData.count) bytes)")

            guard let generatedAtlas = FontAtlas.generate(from: fontData, fontSize: 48.0, atlasSize: 1024, distanceRange: 6.0) else {
                print("Failed to generate SDF font atlas")
                return false
            }
            atlas = generatedAtlas
            textUsesMSDF = false

            guard let uploadedTextureID = graphics.createUITextureR8(
                width: atlas.textureWidth,
                height: atlas.textureHeight,
                pixels: atlas.textureData
            ) else {
                print("Failed to upload SDF atlas texture to Vulkan")
                return false
            }
            textureID = uploadedTextureID
        }

        if let minValue = atlas.textureData.min(), let maxValue = atlas.textureData.max() {
            print("SDF atlas value range: min=\(minValue), max=\(maxValue)")
        }

        if let adv0 = atlas.glyphs["0"]?.advance,
           let adv1 = atlas.glyphs["1"]?.advance,
           let advI = atlas.glyphs["i"]?.advance,
           let advM = atlas.glyphs["M"]?.advance {
            print("SDF advance check (0,1,i,M): \(adv0), \(adv1), \(advI), \(advM)")
        }

        self.textRenderer = TextRenderer(atlas: atlas)
        self.sdfTextureID = textureID
        graphics.setUITextSDFParameters(threshold: 0.5, range: atlas.distanceRange)
        // True reconstruction is tuned for MSDF atlas assets. Keep fallback SDF in readable mode.
        graphics.setUITextTrueSDFMode(textUsesMSDF && useTrueSDFTextMode)
        graphics.setUITextMSDFMode(textUsesMSDF)
        print("Text resources initialized (texture id: \(textureID), mode: \(textUsesMSDF ? "MSDF" : "SDF"))")
        return true
    }

    //Input stuff
    public func handleInput(input: InputProvider) {
        previousMousePosition = currentMousePosition
        wasMousePressed = isMousePressed

        currentMousePosition = input.mousePosition
        // SDL uses 1 for left mouse button.
        isMousePressed = input.isMouseButtonDown(1)

        let previousHoveredID = hoveredElementID
        let previousHoveredElement = hoveredElement

        //Do hit testing using the stored state
        let hitResult = hitTest(at: currentMousePosition)
        hoveredElement = hitResult?.element
        hoveredElementID = hitResult?.interactionID

        // Detect transitions using stable IDs so state survives element rebuilds.
        if hoveredElementID != previousHoveredID {
            previousHoveredElement?.onHoverEnd?()
            hoveredElement?.onHoverStart?()
        }

        if isMousePressed && !wasMousePressed {
                if let handler = hoveredElement?.tapHandler {
                    print("[UI] tap fired on element id: \(hoveredElementID ?? "nil")")
                    handler()
                } else {
                    print("[UI] click at \(currentMousePosition) — hit: \(hoveredElementID ?? "nothing"), no handler")
                }
        }
    }

    private func hitTest(at point: Vector2) -> HitTestResult? {
        guard let root = layoutedRootElement else { return nil }
        return hitTest(at: point, in: root, path: "root")
    }

    private func hitTest(at point: Vector2, in element: Element, path: String) -> HitTestResult? {
        guard pointInside(point, bounds: element.bounds) else {
            return nil
        }

        for index in element.children.indices.reversed() {
            let child = element.children[index]
            if let childHit = hitTest(at: point, in: child, path: "\(path).\(index)") {
                return childHit
            }
        }

        // Only return this element if it has at least one handler, otherwise let parent handle it
        if element.tapHandler != nil || element.onHoverStart != nil || element.onHoverEnd != nil {
            let interactionID = element.id ?? path
            return HitTestResult(element: element, interactionID: interactionID)
        }
        return nil
    }

    private func pointInside(_ point: Vector2, bounds: Rectangle) -> Bool {
        point.x >= bounds.position.x &&
        point.x <= (bounds.position.x + bounds.width) &&
        point.y >= bounds.position.y &&
        point.y <= (bounds.position.y + bounds.height)
    }

}
