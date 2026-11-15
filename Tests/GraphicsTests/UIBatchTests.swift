import XCTest
import Core
@testable import Graphics
@testable import UI

final class UIBatchTests: XCTestCase {
    private func element(texture: UInt32? = nil, sdf: Bool = false) -> Renderable2D {
        Renderable2D(position: .zero, size: SIMD2(10, 10), textureID: texture, usesSDF: sdf)
    }

    func testBatchesPreserveOrderAndOnlyMergeAdjacentMaterials() {
        let solid1 = element()
        let solid2 = element()
        let texture1 = element(texture: 1)
        let texture2 = element(texture: 2)
        let texture1Again = element(texture: 1)
        let text = element(texture: 3, sdf: true)
        let batches = Graphics.makeUIBatches([solid1, solid2, texture1, texture2, texture1Again, text])
        XCTAssertEqual(batches.count, 5)
        XCTAssertEqual(batches.map { $0.elements.count }, [2, 1, 1, 1, 1])
        XCTAssertTrue(batches[2].elements[0] === texture2)
        XCTAssertTrue(batches[3].elements[0] === texture1Again)
        XCTAssertTrue(batches[4].elements[0] === text)
    }

    func testReplacingManagedElementsPreservesUnrelatedDrawOrder() {
        let behind = element()
        let first = element()
        let second = element()
        let front = element()
        let replacement = element()
        let group = UIElementGroup()
        var list = UIElementList()
        list.add(behind)
        list.replace(group, with: [first, second])
        list.add(front)
        list.replace(group, with: [])
        list.replace(group, with: [replacement])
        let result = list.elements
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result[0] === behind)
        XCTAssertTrue(result[1] === replacement)
        XCTAssertTrue(result[2] === front)
    }

    func testDifferentTextEffectsUseDifferentBatches() {
        let first = element(texture: 1, sdf: true)
        let second = element(texture: 1, sdf: true)
        let third = element(texture: 1, sdf: true)
        second.outlineWidth = 0.1
        third.glowWidth = 0.2
        XCTAssertEqual(Graphics.makeUIBatches([first, second, third]).count, 3)
        XCTAssertEqual(Graphics.makeUIBatches([first, first]).count, 1)
    }

    func testChangingColorUpdatesVerticesAndMarksRenderableDirty() {
        let renderable = element()
        renderable.markUploaded(vertexOffset: 0, indexOffset: 0)
        renderable.color = .blue
        XCTAssertTrue(renderable.isDirty)
        XCTAssertTrue(renderable.vertices.allSatisfy { $0.color == .blue })
    }

    func testRebuildDetectsChangedTextureCoordinatesAndEffects() {
        let first = element(texture: 1, sdf: true)
        let second = element(texture: 1, sdf: true)
        XCTAssertTrue(UIManager.renderablesMatch(first, second))
        second.vertices[0].texCoord.x = 0.25
        XCTAssertFalse(UIManager.renderablesMatch(first, second))
        second.vertices[0].texCoord = first.vertices[0].texCoord
        second.shadowOffset = SIMD2(1, 0)
        XCTAssertFalse(UIManager.renderablesMatch(first, second))
    }

    func testMaterialUniformMatchesShaderLayout() {
        XCTAssertEqual(MemoryLayout<UIMaterialConstants>.offset(of: \.tint), 0)
        XCTAssertEqual(MemoryLayout<UIMaterialConstants>.offset(of: \.opacity), 16)
        XCTAssertEqual(MemoryLayout<UIMaterialConstants>.offset(of: \.outlineColor), 48)
        XCTAssertEqual(MemoryLayout<UIMaterialConstants>.offset(of: \.sdfRange), 64)
        XCTAssertEqual(MemoryLayout<UIMaterialConstants>.offset(of: \.glowColor), 80)
        XCTAssertEqual(MemoryLayout<UIMaterialConstants>.offset(of: \.shadowColor), 112)
        XCTAssertEqual(MemoryLayout<UIMaterialConstants>.offset(of: \.shadowOffset), 128)
        XCTAssertEqual(MemoryLayout<UIMaterialConstants>.stride, 144)
    }

    func test2DUniformsMatchShaderLayouts() {
        XCTAssertEqual(MemoryLayout<Transform2DConstants>.offset(of: \.projection), 0)
        XCTAssertEqual(MemoryLayout<Transform2DConstants>.offset(of: \.model), 64)
        XCTAssertEqual(MemoryLayout<Transform2DConstants>.stride, 128)
        XCTAssertEqual(MemoryLayout<MaterialConstants2D>.offset(of: \.color), 0)
        XCTAssertEqual(MemoryLayout<MaterialConstants2D>.offset(of: \.opacity), 16)
        XCTAssertEqual(MemoryLayout<MaterialConstants2D>.offset(of: \.hasTexture), 20)
        XCTAssertEqual(MemoryLayout<MaterialConstants2D>.offset(of: \.padding), 32)
        XCTAssertEqual(MemoryLayout<MaterialConstants2D>.stride, 48)
    }
}
