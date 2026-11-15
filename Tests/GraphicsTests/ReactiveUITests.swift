import XCTest
import Core
@testable import Graphics
import Math
@testable import UI

final class ReactiveUITests: XCTestCase {
    private final class Renderer: UIRendering {
        var list = UIElementList()
        var elements: [Renderable2D] { list.elements }
        func replaceUIElements(in group: UIElementGroup, with replacements: [Renderable2D]) {
            list.replace(group, with: replacements)
        }
        func createUITextureRGBA(width: Int, height: Int, pixels: [UInt8], srgb: Bool) -> UInt32? { 1 }
        func createUITextureR8(width: Int, height: Int, pixels: [UInt8]) -> UInt32? { 1 }
        func setUITextSDFParameters(threshold: Float, range: Float) {}
        func setUITextTrueSDFMode(_ enabled: Bool) {}
        func setUITextMSDFMode(_ enabled: Bool) {}
    }

    func testOnlyChangedRegionRegeneratesAndResizeUpdatesLayout() {
        let renderer = Renderer()
        let ui = UIManager(renderer: renderer)
        let count = Reactive(0)
        var regionBuilds = 0
        var staticRenders = 0
        var dynamicRenders = 0
        var staticBounds: [Rectangle] = []
        var dynamicBounds: [Rectangle] = []

        ui.setRoot(Column(spacing: 0) {
            Element(type: .custom(renderer: { element in
                staticRenders += 1
                staticBounds.append(element.bounds)
                return [Quad(position: element.bounds.position, size: element.bounds.size, color: .white)]
            }))
            Dynamic {
                regionBuilds += 1
                let value = count.value
                return Element(type: .custom(renderer: { element in
                    dynamicRenders += 1
                    dynamicBounds.append(element.bounds)
                    return [Quad(position: element.bounds.position, size: element.bounds.size, color: value == 0 ? .white : .blue)]
                }))
            }
        })
        ui.setScreenBounds(Rectangle(position: Vector2(0, 0), width: 200, height: 100))
        ui.update()
        XCTAssertEqual(renderer.elements.count, 2)
        let firstRenderable = renderer.elements[0]
        let unrelated = Renderable2D(position: .zero, size: SIMD2(5, 5))
        renderer.list.add(unrelated)
        XCTAssertEqual([regionBuilds, staticRenders, dynamicRenders], [1, 1, 1])
        XCTAssertEqual(staticBounds.last?.height, 50)
        XCTAssertEqual(dynamicBounds.last?.position.y, 50)

        count.value = 1
        count.value = 2
        ui.update()
        XCTAssertEqual([regionBuilds, staticRenders, dynamicRenders], [2, 1, 2])
        XCTAssertTrue(renderer.elements[0] === firstRenderable)
        XCTAssertTrue(renderer.elements.last === unrelated)
        ui.update()
        XCTAssertEqual([regionBuilds, staticRenders, dynamicRenders], [2, 1, 2])

        ui.setScreenBounds(Rectangle(position: Vector2(0, 0), width: 200, height: 200))
        ui.update()
        XCTAssertEqual([regionBuilds, staticRenders, dynamicRenders], [2, 2, 3])
        XCTAssertEqual(staticBounds.last?.height, 100)
        XCTAssertEqual(dynamicBounds.last?.position.y, 100)
    }

    func testConditionalDependenciesAreReplacedAndRegionsAreReleased() {
        let chooseFirst = Reactive(true)
        let first = Reactive(1)
        let second = Reactive(2)
        var builds = 0
        var region: ReactiveRegion? = ReactiveRegion {
            builds += 1
            let value = chooseFirst.value ? first.value : second.value
            return Element(type: .rect(color: value == 1 ? .white : .blue))
        }
        weak let weakRegion = region
        _ = region?.evaluate()

        second.value = 3
        XCTAssertFalse(region!.isDirty)
        first.value = 4
        XCTAssertTrue(region!.isDirty)
        _ = region?.evaluate()

        chooseFirst.value = false
        _ = region?.evaluate()
        first.value = 5
        XCTAssertFalse(region!.isDirty)
        second.value = 6
        XCTAssertTrue(region!.isDirty)
        _ = region?.evaluate()
        XCTAssertEqual(builds, 4)

        region = nil
        XCTAssertNil(weakRegion)
        second.value = 7
        XCTAssertEqual(builds, 4)
    }

    func testStateMutationDuringBuildIsNotLost() {
        let state = Reactive(0)
        var builds = 0
        let ui = UIManager(renderer: Renderer())
        ui.setRoot(Dynamic {
            builds += 1
            let value = state.value
            if value == 0 { state.value = 1 }
            return Element(type: .rect(color: .white))
        })
        ui.update()
        ui.update()
        ui.update()
        XCTAssertEqual(builds, 2)
    }

    func testNestedRegionsTrackIndependentlyAndUnsubscribeWhenRemoved() {
        let ui = UIManager(renderer: Renderer())
        let show = Reactive(true)
        let value = Reactive(0)
        var outerBuilds = 0
        var innerBuilds = 0
        ui.setRoot(Dynamic {
            outerBuilds += 1
            if show.value {
                return Dynamic {
                    innerBuilds += 1
                    return Element(type: .rect(color: value.value == 0 ? .white : .blue))
                }
            }
            return Element(type: .container)
        })
        ui.update()
        value.value = 1
        ui.update()
        XCTAssertEqual([outerBuilds, innerBuilds], [1, 2])

        show.value = false
        ui.update()
        value.value = 2
        ui.update()
        XCTAssertEqual([outerBuilds, innerBuilds], [2, 2])

        show.value = true
        ui.update()
        XCTAssertEqual([outerBuilds, innerBuilds], [3, 3])
    }

    func testChangedChildCountRelayoutsRegionWithoutRegeneratingSibling() {
        let renderer = Renderer()
        let ui = UIManager(renderer: renderer)
        let expanded = Reactive(false)
        var siblingRenders = 0
        var heights: [Float] = []
        func child() -> Element {
            Element(type: .custom(renderer: { element in
                heights.append(element.bounds.height)
                return [Quad(position: element.bounds.position, size: element.bounds.size, color: .white)]
            }))
        }
        ui.setRoot(Column(spacing: 0) {
            Element(type: .custom(renderer: { element in
                siblingRenders += 1
                return [Quad(position: element.bounds.position, size: element.bounds.size, color: .white)]
            }))
            Dynamic {
                let children = expanded.value ? [child(), child()] : [child()]
                return Column().spacing(0).content(children)
            }
        })
        ui.setScreenBounds(Rectangle(position: Vector2(0, 0), width: 100, height: 100))
        ui.update()
        XCTAssertEqual(heights, [50])
        expanded.value = true
        ui.update()
        XCTAssertEqual(heights, [50, 25, 25])
        XCTAssertEqual(renderer.elements.count, 3)
        XCTAssertEqual(siblingRenders, 1)
    }

    func testUpdatedRegionReceivesInputAndDoesNotRebuildSiblings() {
        final class Input: InputProvider {
            var mousePosition = Vector2(10, 10)
            var pressed = false
            func isMouseButtonDown(_ button: Int) -> Bool { pressed && button == 1 }
            func isKeyDown(_ key: Key) -> Bool { false }
            func update() {}
        }

        let ui = UIManager(renderer: Renderer())
        let state = Reactive(false)
        var tapped = ""
        var siblingBuilds = 0
        var dependentBuilds = 0
        ui.setRoot(Column(spacing: 0) {
            Dynamic {
                dependentBuilds += 1
                let value = state.value
                return Element(type: .rect(color: .white)).onTap {
                    tapped = value ? "new" : "old"
                    state.value = false
                }
            }
            Dynamic {
                siblingBuilds += 1
                return Element(type: .rect(color: .blue))
            }
        })
        ui.setScreenBounds(Rectangle(position: Vector2(0, 0), width: 100, height: 100))
        ui.update()
        state.value = true
        ui.update()
        let input = Input()
        input.pressed = true
        ui.handleInput(input: input)
        ui.update()
        XCTAssertEqual(tapped, "new")
        XCTAssertEqual(dependentBuilds, 3)
        XCTAssertEqual(siblingBuilds, 1)
    }
}
