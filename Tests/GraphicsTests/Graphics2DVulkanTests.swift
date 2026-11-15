import XCTest
import Foundation
import Core
import Platform
import Cvulkan
import Cvma
@testable import Graphics

final class Graphics2DVulkanTests: XCTestCase {
    func testGraphics2DPipelineDraws() throws {
        guard ProcessInfo.processInfo.environment["DECKRPGUI_GPU_TESTS"] == "1" else {
            throw XCTSkip("Set DECKRPGUI_GPU_TESTS=1 to run Vulkan integration tests")
        }

        let context = SDLContext()
        context.initialize()
        let window = Window(sdlContext: context)
        window.createWindow(title: "2D pipeline test", width: 320, height: 240)
        let renderer = VulkanRenderer(context: context)
        renderer.initialize()
        let device = try XCTUnwrap(renderer.logicalDevice)
        let allocator = try XCTUnwrap(renderer.vmaAllocator)
        let pool = try XCTUnwrap(renderer.commandPool)
        let queue = try XCTUnwrap(renderer.queueManager?.graphicsQueue)
        let resources = VulkanResourceManager(
            device: device, vmaAllocator: allocator, totalVRAM: renderer.getTotalVRAM(),
            transferCommandPool: pool, transferQueue: queue
        )
        try resources.initialize()
        renderer.setResourceManager(resources)
        let pipeline = PipelineFactory.createPipeline(
            descriptor: PipelineDescriptor(type: .Graphics2D, blendMode: .Alpha, depthTest: false, cullMode: .None),
            backend: .Vulkan, device: device, renderer: renderer
        )
        defer {
            vkDeviceWaitIdle(device)
            pipeline.cleanup()
            resources.cleanup()
            renderer.cleanup()
            window.cleanup()
            context.cleanup()
        }

        let sprite = Renderable2D(position: SIMD2(80, 80), size: SIMD2(40, 40))
        let vertexRegion = try resources.allocate2DVertices(vertices: sprite.vertices)
        let indexRegion = try resources.allocate2DIndices(indices: sprite.indices)
        for _ in 0..<2 {
            let image = try XCTUnwrap(renderer.createFrame())
            let extent = try XCTUnwrap(renderer.swapchainExtent)
            let transformAllocation = try XCTUnwrap(renderer.transform2DUBOMemory)
            var mapped: UnsafeMutableRawPointer?
            XCTAssertEqual(vmaMapMemory(allocator, transformAllocation, &mapped), VK_SUCCESS)
            let transform = try XCTUnwrap(mapped).load(as: Transform2DConstants.self)
            vmaUnmapMemory(allocator, transformAllocation)
            XCTAssertEqual(transform.projection[0].x, 2 / Float(extent.width), accuracy: 0.00001)
            XCTAssertEqual(transform.projection[1].y, 2 / Float(extent.height), accuracy: 0.00001)
            XCTAssertEqual(transform.model[0].x, 1)
            XCTAssertEqual(transform.model[3].w, 1)
            pipeline.bind()
            resources.withVertex2DBuffer { buffer in
                var handle: VkBuffer? = buffer.bufferHandle.asVulkanBuffer()
                var offset = VkDeviceSize(vertexRegion.offset)
                vkCmdBindVertexBuffers(renderer.commandBuffer, 0, 1, &handle, &offset)
            }
            resources.withIndex2DBuffer { buffer in
                vkCmdBindIndexBuffer(renderer.commandBuffer, buffer.bufferHandle.asVulkanBuffer(),
                                     VkDeviceSize(indexRegion.offset), VK_INDEX_TYPE_UINT32)
            }
            vkCmdDrawIndexed(renderer.commandBuffer, UInt32(sprite.indices.count), 1, 0, 0, 0)
            renderer.renderFrame(imageIndex: image)
        }
    }
}
