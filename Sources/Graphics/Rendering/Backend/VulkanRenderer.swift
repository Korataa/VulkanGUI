import Platform
import Core
import Math

    // Helper to atomically take and nil out a noncopyable property
    private func take<T>(_ value: inout T?) -> T? {
        let temp = value
        value = nil
        return temp
    }
/* 
This file implements platform-specific rendering logic. Each renderer handles how to set up the 
graphics API (Vulkan, DirectX, etc.), create command buffers, issue draw calls, etc.

LowLevelRenderer (e.g., VulkanRenderer):

    The LowLevelRenderer handles API-specific tasks like:
        Creating Vulkan command buffers.
        Managing Vulkan pipelines, shaders, and textures.
    It provides an interface that the RenderPipeline can call, such as beginFrame, draw, and endFrame.
*/

import Cvulkan
import Cvma

import Foundation

#if DEBUG
    let enableValidationLayers = true
#else
    let enableValidationLayers = false
#endif

func makeVulkanVersion(major: UInt32, minor: UInt32, patch: UInt32) -> UInt32 {
    return (major << 22) | (minor << 12) | patch
}

class VulkanRenderer {
    var sdlContext: SDLContext
    var windowHandle: OpaquePointer? = nil

    private var resourceManager: VulkanResourceManager? = nil
    var camera: Camera! // Add camera
    
    // Store materials for rendering
    private var materials: [Material] = []

    var instance: VkInstance? = nil
    var surface: VkSurfaceKHR? = nil
    var debugMessenger: VkDebugUtilsMessengerEXT? = nil

    var physicalDevice: VkPhysicalDevice? = nil
    var logicalDevice: VkDevice? = nil

    //Queue shit
    var queueManager: QueueManager? = nil
    var uniqueQueueFamilyIndices: DynamicArray<UInt32>? = nil

    //swapchain shit
    var swapchain: VkSwapchainKHR? = nil
    var swapchainImages: DynamicArray<VkImage?>? = nil
    var swapchainImageFormat: VkFormat? = nil
    var swapchainExtent: VkExtent2D? = nil

    var swapchainImageViews: DynamicArray<VkImageView?>? = nil

    // Depth buffer
    var depthImage: VkImage? = nil
    var depthImageMemory: VmaAllocation? = nil
    var depthImageView: VkImageView? = nil
    var depthFormat: VkFormat = VK_FORMAT_D32_SFLOAT

    //RenderPass
    var renderPass: VkRenderPass? = nil

    // Pipeline
    var pipelines: [VkPipeline] = []
    var pipelineLayouts: [VkPipelineLayout] = []

    var swapchainFrameBuffers: DynamicArray<VkFramebuffer?>? = nil

    //Command Pools
    var commandPool: VkCommandPool? = nil
    var transferCommandPool: VkCommandPool? = nil
    var commandBuffer: VkCommandBuffer? = nil

    //Synchronization objects
    var imageAvailableSemaphores: DynamicArray<VkSemaphore?>? = nil
    var renderFinishedSemaphores: DynamicArray<VkSemaphore?>? = nil
    var inFlightFences: DynamicArray<VkFence?>? = nil
    let MAX_FRAMES_IN_FLIGHT = 1
    var currentFrame: Int = 0   //we dont mutate this ever yet BUT maybe in the future that will change

    //Buffers and memory shit
    var vmaAllocator: VmaAllocator? = nil
    var vertexBuffer: VkBuffer? = nil
    var vertexBufferAllocation: VmaAllocation? = nil
    var indexBuffer: VkBuffer? = nil
    var indexBufferAllocation: VmaAllocation? = nil
    
    // Dedicated 2D/UI buffers (smaller, optimized for UI elements)
    var buffer2D_Vertex: VkBuffer? = nil
    var buffer2D_VertexAllocation: VmaAllocation? = nil
    var buffer2D_Index: VkBuffer? = nil
    var buffer2D_IndexAllocation: VmaAllocation? = nil

    //uniform buffer shit
    var frameUBO: VkBuffer? = nil
    var frameUBOMemory: VmaAllocation? = nil
    
    // New separate UBOs
    var transformUBO: VkBuffer? = nil
    var transformUBOMemory: VmaAllocation? = nil
    var materialUBO3D: VkBuffer? = nil
    var materialUBOMemory3D: VmaAllocation? = nil
    var materialUBO2D: VkBuffer? = nil
    var materialUBOMemory2D: VmaAllocation? = nil
    
    // UI projection uniform buffer
    var uiProjectionUBO: VkBuffer? = nil
    var uiProjectionUBOMemory: VmaAllocation? = nil
    var uiMaterialUBO: VkBuffer? = nil
    var uiMaterialUBOMemory: VmaAllocation? = nil

    private var currentUIMaterial = UIMaterialConstants(
        tint: Color.white,
        opacity: 1.0,
        textureMode: 0,
        roundedCorners: 0,
        cornerRadius: 0.0,
        sdfThreshold: 0.5,
        outlineWidth: 0.0,
        pad0: 0.0,
        outlineColor: Color.black,
        sdfRange: 4.0,
        reserved1: 0.0,
        reserved2: 0.0,
        pad1: 0.0,
        glowColor: Color(255,255,255,0),
        glowWidth: 0.0,
        pad2: 0.0,
        shadowColor: Color(0,0,0,0),
        shadowOffset: Vector2(0,0),
        pad3: 0.0,
        pad4: 0.0
    )
    private var currentUITextureIndex: Int? = nil
    private var uiTextUsesMSDF: Bool = false
    
    // Texture management
    var textureManager: VulkanTextureManager? = nil
    
    // Legacy UBO - keep for compatibility
    var objectUBO: VkBuffer? = nil
    var objectUBOMemory: VmaAllocation? = nil
    var lightUBO: VkBuffer? = nil
    var lightUBOMemory: VmaAllocation? = nil
    
    //alignment stuff for ubo
    var dynamicAlignment: VkDeviceSize = 0
    var transformAlignment: VkDeviceSize = 0
    var materialAlignment: VkDeviceSize = 0
    var transformAlignment2D: VkDeviceSize = 0
    var transformAlignment3D: VkDeviceSize = 0
    var materialAlignment2D: VkDeviceSize = 0
    var materialAlignment3D: VkDeviceSize = 0

    // Material uploader for proper material system
    private var materialUploader: VulkanMaterialUploader?
    
    // Main shader instance
    private var mainShader: VulkanShader?
    
    // UI batching arrays for performance optimization
    private var batchedUIVertices: [Vertex2D] = []
    private var batchedUIIndices: [UInt32] = []
    private var uiBatchCount: Int = 0


    //Descriptor sets
    var descriptorPool: VkDescriptorPool? = nil
    var frameDescriptorSet: VkDescriptorSet? = nil
    
    // New separate descriptor sets
    var transformDescriptorSet: VkDescriptorSet? = nil
    var materialDescriptorSet: VkDescriptorSet? = nil
    
    // UI descriptor sets
    var uiProjectionDescriptorSet: VkDescriptorSet? = nil
    var uiMaterialDescriptorSet: VkDescriptorSet? = nil
    
    var frameSetLayout: VkDescriptorSetLayout? = nil
    
    // New separate layouts
    var transformSetLayout: VkDescriptorSetLayout? = nil

    //Material set layouts
    var materialSetLayout3D: VkDescriptorSetLayout? = nil
    var materialSetLayout2D: VkDescriptorSetLayout? = nil
    var postProcessingSetLayout: VkDescriptorSetLayout? = nil
    
    // 2D and UI specific layouts
    var transform2DSetLayout: VkDescriptorSetLayout? = nil    // For 2D projection + model matrix
    var material2DSetLayout: VkDescriptorSetLayout? = nil     // For 2D material + texture
    var uiProjectionSetLayout: VkDescriptorSetLayout? = nil   // For UI projection + screen size
    var uiMaterialSetLayout: VkDescriptorSetLayout? = nil     // For UI material + texture

    private var portabilityCString = createUnsafeString("VK_KHR_portability_enumeration")
    private var debugUtilCString = createUnsafeString("VK_EXT_debug_utils")
    private var validationLayerCString = createUnsafeString("VK_LAYER_KHRONOS_validation")
    private var swapchainExtensionNameCString = createUnsafeString("VK_KHR_swapchain")
    private var shaderEntryPointName = createUnsafeString("main")

    private var requiredExtensions: DynamicArray<UnsafePointer<CChar>?>
    private var requiredDeviceExtensions: DynamicArray<UnsafePointer<CChar>?>

    //perhaps if i could do something like this repeating thing in my dynamicArray I could make it work
    //with vulkan non pointer elements, i could make it work for getData()
    private var validationLayerNames: DynamicArray<UnsafePointer<CChar>?>

    //USER CONFIGURED SETTINGS
    var vSyncEnabled: Bool = false

    let vertices: DynamicArray<Vertex2D>
    let indices: DynamicArray<UInt32>

    init(context: SDLContext) {
        self.sdlContext = context

        //we will set up the extensions here
        requiredExtensions = sdlContext.getRequiredVulkanExtensionsFromSDL()    //seg fault here

        if enableValidationLayers {
            requiredExtensions.append(UnsafePointer(debugUtilCString!))
        }

        validationLayerNames = DynamicArray<UnsafePointer<CChar>?>(
            UnsafePointer(validationLayerCString!)
        )

        requiredDeviceExtensions = DynamicArray<UnsafePointer<CChar>?>(
            UnsafePointer(swapchainExtensionNameCString!)
        )

        /*
        r = pow(85 / 255.0, 2.2)
        g = pow(92 / 255.0, 2.2)
        b = pow(70 / 255.0, 2.2)

        vertices = DynamicArray<Vertex2D>(
        //first triangle
        Vertex2D(pos: Vector2(-0.5, -0.5), color: Vector3(1.0, 0.6, 0.0)),
        Vertex2D(pos: Vector2(0.5, -0.5), color: Vector3(0.0, 1.0, 0.0)),
        Vertex2D(pos: Vector2(0.5, 0.5), color: Vector3(0.0, 0.0, 1.0)),
        Vertex2D(pos: Vector2(-0.5, 0.5), color: Vector3(r, g, b))
        )

        indices = DynamicArray<UInt32>(
            0, 1, 2, 2, 3, 0
        )

same here 0       1
          3       2 (need to specify 2 twice here to make more than one triangle because everything is triangles)
        */

        vertices = DynamicArray<Vertex2D>()
        indices = DynamicArray<UInt32>()
    }

    func cleanup() {
        print("Waiting for GPU to finish before cleanup...")
        vkDeviceWaitIdle(logicalDevice)
        
        // CRITICAL: Reset ALL command buffers to clear pipeline references
        if let cmdBuf = commandBuffer {
            print("🔄 Resetting command buffer to clear pipeline references")
            vkResetCommandBuffer(cmdBuf, 0)
        }
        
        // Wait for device again after resetting command buffers
        vkDeviceWaitIdle(logicalDevice)
        print("Destroying Vulkan resources...")

        // THEN free command buffers
        withUnsafePointer(to: &commandBuffer) { ptr in
            vkFreeCommandBuffers(logicalDevice, commandPool, 1, ptr)
        }

        if queueManager!.graphicsQueueFamilyIndex != queueManager!.transferQueueFamilyIndex {
            vkDestroyCommandPool(logicalDevice, transferCommandPool, nil)
        }
        vkDestroyCommandPool(logicalDevice, commandPool, nil)

        // Now safe to destroy pipelines and other resources
        cleanupSwapchain()

        //Cleanup vma resources
        materialUploader?.cleanup()
        mainShader?.cleanup()
        textureManager?.cleanup()
        
        // TODO: Move all these VMA buffer allocations into VulkanResourceManager
        // This would centralize buffer management and eliminate the need for manual cleanup here
        // Affected buffers: frameUBO, objectUBO, vertexBuffer, indexBuffer, 2D buffers, UBOs
        vmaDestroyBuffer(vmaAllocator!, frameUBO, frameUBOMemory)
        vmaDestroyBuffer(vmaAllocator!, objectUBO, objectUBOMemory)
        vmaDestroyBuffer(vmaAllocator!, vertexBuffer, vertexBufferAllocation)
        vmaDestroyBuffer(vmaAllocator!, indexBuffer, indexBufferAllocation)
        
        // Cleanup 2D buffers
        if let buffer2D_Vertex = buffer2D_Vertex, let buffer2D_VertexAllocation = buffer2D_VertexAllocation {
            vmaDestroyBuffer(vmaAllocator!, buffer2D_Vertex, buffer2D_VertexAllocation)
        }
        if let buffer2D_Index = buffer2D_Index, let buffer2D_IndexAllocation = buffer2D_IndexAllocation {
            vmaDestroyBuffer(vmaAllocator!, buffer2D_Index, buffer2D_IndexAllocation)
        }
        
        // Cleanup transform and material UBOs
        if let transformUBO = transformUBO, let transformUBOMemory = transformUBOMemory {
            vmaDestroyBuffer(vmaAllocator!, transformUBO, transformUBOMemory)
        }
        if let materialUBO3D = materialUBO3D, let materialUBOMemory3D = materialUBOMemory3D {
            vmaDestroyBuffer(vmaAllocator!, materialUBO3D, materialUBOMemory3D)
        }
        if let materialUBO2D = materialUBO2D, let materialUBOMemory2D = materialUBOMemory2D {
            vmaDestroyBuffer(vmaAllocator!, materialUBO2D, materialUBOMemory2D)
        }
        
        // Cleanup UI projection buffer
        if let uiProjectionUBO = uiProjectionUBO, let uiProjectionUBOMemory = uiProjectionUBOMemory {
            vmaDestroyBuffer(vmaAllocator!, uiProjectionUBO, uiProjectionUBOMemory)
        }
        if let uiMaterialUBO = uiMaterialUBO, let uiMaterialUBOMemory = uiMaterialUBOMemory {
            vmaDestroyBuffer(vmaAllocator!, uiMaterialUBO, uiMaterialUBOMemory)
        }
        
        // Cleanup depth resources
        if let depthImageView = depthImageView {
            vkDestroyImageView(logicalDevice, depthImageView, nil)
        }
        if let depthImage = depthImage, let depthImageMemory = depthImageMemory {
            vmaDestroyImage(vmaAllocator!, depthImage, depthImageMemory)
        }
        
        vmaDestroyAllocator(vmaAllocator)

        // Destroy all descriptor set layouts (including 2D and UI)
        if let frameSetLayout = frameSetLayout {
            vkLog("🔶 VkDescriptorSetLayout DESTROYING: \(frameSetLayout) in VulkanRenderer")
            vkDestroyDescriptorSetLayout(logicalDevice, frameSetLayout, nil)
            vkLog("✅ VkDescriptorSetLayout DESTROYED: \(frameSetLayout) in VulkanRenderer")
            self.frameSetLayout = nil
        }
        if let transformSetLayout = transformSetLayout {
            vkLog("🔶 VkDescriptorSetLayout DESTROYING: \(transformSetLayout) in VulkanRenderer")
            vkDestroyDescriptorSetLayout(logicalDevice, transformSetLayout, nil)
            vkLog("✅ VkDescriptorSetLayout DESTROYED: \(transformSetLayout) in VulkanRenderer")
            self.transformSetLayout = nil
        }
        if let materialSetLayout3D = materialSetLayout3D {
            vkLog("🔶 VkDescriptorSetLayout DESTROYING: \(materialSetLayout3D) in VulkanRenderer")
            vkDestroyDescriptorSetLayout(logicalDevice, materialSetLayout3D, nil)
            vkLog("✅ VkDescriptorSetLayout DESTROYED: \(materialSetLayout3D) in VulkanRenderer")
            self.materialSetLayout3D = nil
        }
        if let materialSetLayout2D = materialSetLayout2D {
            vkLog("🔶 VkDescriptorSetLayout DESTROYING: \(materialSetLayout2D) in VulkanRenderer")
            vkDestroyDescriptorSetLayout(logicalDevice, materialSetLayout2D, nil)
            vkLog("✅ VkDescriptorSetLayout DESTROYED: \(materialSetLayout2D) in VulkanRenderer")
            self.materialSetLayout2D = nil
        }
        if let postProcessingSetLayout = postProcessingSetLayout {
            vkLog("🔶 VkDescriptorSetLayout DESTROYING: \(postProcessingSetLayout) in VulkanRenderer")
            vkDestroyDescriptorSetLayout(logicalDevice, postProcessingSetLayout, nil)
            vkLog("✅ VkDescriptorSetLayout DESTROYED: \(postProcessingSetLayout) in VulkanRenderer")
            self.postProcessingSetLayout = nil
        }
        if let transform2DSetLayout = transform2DSetLayout {
            vkLog("🔶 VkDescriptorSetLayout DESTROYING: \(transform2DSetLayout) in VulkanRenderer")
            vkDestroyDescriptorSetLayout(logicalDevice, transform2DSetLayout, nil)
            vkLog("✅ VkDescriptorSetLayout DESTROYED: \(transform2DSetLayout) in VulkanRenderer")
            self.transform2DSetLayout = nil
        }
        if let material2DSetLayout = material2DSetLayout {
            vkLog("🔶 VkDescriptorSetLayout DESTROYING: \(material2DSetLayout) in VulkanRenderer")
            vkDestroyDescriptorSetLayout(logicalDevice, material2DSetLayout, nil)
            vkLog("✅ VkDescriptorSetLayout DESTROYED: \(material2DSetLayout) in VulkanRenderer")
            self.material2DSetLayout = nil
        }
        if let uiProjectionSetLayout = uiProjectionSetLayout {
            vkLog("🔶 VkDescriptorSetLayout DESTROYING: \(uiProjectionSetLayout) in VulkanRenderer")
            vkDestroyDescriptorSetLayout(logicalDevice, uiProjectionSetLayout, nil)
            vkLog("✅ VkDescriptorSetLayout DESTROYED: \(uiProjectionSetLayout) in VulkanRenderer")
            self.uiProjectionSetLayout = nil
        }
        if let uiMaterialSetLayout = uiMaterialSetLayout {
            vkLog("🔶 VkDescriptorSetLayout DESTROYING: \(uiMaterialSetLayout) in VulkanRenderer")
            vkDestroyDescriptorSetLayout(logicalDevice, uiMaterialSetLayout, nil)
            vkLog("✅ VkDescriptorSetLayout DESTROYED: \(uiMaterialSetLayout) in VulkanRenderer")
            self.uiMaterialSetLayout = nil
        }

        //this also cleans up descriptorSet
        vkDestroyDescriptorPool(logicalDevice, descriptorPool, nil)

        // NOTE: Pipelines are already destroyed by pipelineManager?.cleanupAllPipelines()
        // before this cleanup function is called. Don't destroy them again!
        print("ℹ️  Pipelines already cleaned up by PipelineManager - skipping duplicate cleanup")
        pipelines.removeAll()
        pipelineLayouts.removeAll()

        vkDestroyRenderPass(logicalDevice, renderPass, nil)

        while !imageAvailableSemaphores!.isEmpty() && !renderFinishedSemaphores!.isEmpty() && !inFlightFences!.isEmpty() {
            let imageAvailableSemaphore = imageAvailableSemaphores!.consumeElement(at: imageAvailableSemaphores!.getLength() - 1)
            let renderFinishedSemaphore = renderFinishedSemaphores!.consumeElement(at: renderFinishedSemaphores!.getLength() - 1)
            let inFlightFence = inFlightFences!.consumeElement(at: inFlightFences!.getLength() - 1)
            
            vkDestroySemaphore(logicalDevice, imageAvailableSemaphore, nil)
            vkDestroySemaphore(logicalDevice, renderFinishedSemaphore, nil)
            vkDestroyFence(logicalDevice, inFlightFence, nil)
        }

        print("Do we get here?")
        if let logicalDevice = logicalDevice {
            vkDestroyDevice(logicalDevice, nil)
        } else {
            print("logicalDevice is nil!")
        }
        print("Do we get here? 34")

        if enableValidationLayers {
            destroyDebugUtilsMessengerEXT(instance: instance!, debugMessenger: debugMessenger!, pAllocator: nil)
        }

        if let surface = surface {
            vkDestroySurfaceKHR(instance, surface, nil)
        }
        if let instance = instance {
            vkDestroyInstance(instance, nil)
        }

        portabilityCString?.deallocate()
        debugUtilCString?.deallocate()
        validationLayerCString?.deallocate()
        swapchainExtensionNameCString?.deallocate()
        shaderEntryPointName?.deallocate()
    }

    func initialize() {
        //Basic vulkan setup
        createContext()
        setupDebugMessenger()
        createSurface()
        pickPhysicalDevice()
        calculateAlignment()  // Calculate buffer alignments after physical device is selected
        createLogicalDevice()
        //Maybe create allocator here?
        setupVmaAllocator()
        
        // Initialize material uploader after VMA allocator is ready
        materialUploader = VulkanMaterialUploader(vmaAllocator: vmaAllocator!)
        
        // Initialize texture manager after VMA allocator and command pool are ready
        // Note: We'll initialize this after command pool is created

        //Swapchain and rendering infrastructure
        createSwapchain()
        createImageViews()
        createDepthResources()
        createRenderPass()

        //pipeline creation stuff
        createUniformBuffer()
        //createVertexBuffer()
        //createIndexBuffer()
        //pipelines are now created on-demand via PipelineFactory

        //Framebuffers and commands
        createFrameBuffers()
        createCommandPool()
        
        // Initialize texture manager after command pool is created
        textureManager = VulkanTextureManager(
            device: logicalDevice!,
            physicalDevice: physicalDevice!,
            allocator: vmaAllocator!,
            commandPool: commandPool!,
            graphicsQueue: queueManager!.graphicsQueue!
        )
        _ = textureManager!.initialize()
        
        // Initialize main shader after texture manager and uniform buffers
        mainShader = VulkanShader(
            device: logicalDevice!,
            vmaAllocator: vmaAllocator!,
            textureManager: textureManager
        )
        
        // Set up the shader with vertex and fragment shaders
        try! setupMainShader()
        
        // Create descriptor set layouts for pipelines
        createFrameLayout()
        createTransformLayout()
        createMaterialLayout3D()
        createMaterialLayout2D()
        
        // Create 2D and UI specific layouts
        createTransform2DLayout()
        createMaterial2DLayout()
        createUIProjectionLayout()
        createUIMaterialLayout()
        
        // Create descriptor pool and allocate descriptor sets
        createDescriptorPool()
        allocateDescriptorSets()
        
        // Update descriptor sets with buffer data
        updateFrameDescriptorSet()
        updateTransformDescriptorSet()
        updateMaterialDescriptorSet()  // Update material descriptor set with buffer and texture data
        
        createCommandBuffers()
        createSyncObjects()
    }
    
    private func setupMainShader() throws {
        guard let shader = mainShader else { 
            fatalError("Main shader not initialized")
        }
        
        // Load shader data
        guard let assetsPath = getAssetsPath() else {
            fatalError("Can't get assets path!")
        }
        
        let vertShaderPath: String = "\(assetsPath)/Shaders/vert.spv"
        let fragShaderPath: String = "\(assetsPath)/Shaders/frag.spv"
        
        print("Loading shaders from: \(vertShaderPath), \(fragShaderPath)")
        
        // Initialize shader with vertex and fragment data
        try shader.load(vertexPath: vertShaderPath, fragmentPath: fragShaderPath)
        
        // Setup material binding with our material UBO
        shader.setupMaterialBinding(materialBuffer: materialUBO3D!)
        
        // Setup transform descriptor sets if we have transform buffer
        // (This will be done when transform buffer is ready)
    }

    func setResourceManager(_ resourceManager: VulkanResourceManager) {
        self.resourceManager = resourceManager
        
        // Create textures from resource manager now that we have one
        if textureManager != nil {
            createTexturesFromResourceManager()
        }
    }

    internal func createContext() {
        if enableValidationLayers && !checkValidationLayerSupport() {
            fatalError("validation layers requested, but not available!")
        }

        var appInfo = VkApplicationInfo()
        appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO
        appInfo.pNext = nil
        appInfo.pApplicationName = "Vulkan app".withCString { $0 }
        appInfo.applicationVersion = makeVulkanVersion(major: 1, minor: 0, patch: 0)
        appInfo.pEngineName = "No engine".withCString { $0 }
        appInfo.engineVersion = makeVulkanVersion(major: 1, minor: 0, patch: 0)
        appInfo.apiVersion = makeVulkanVersion(major: 1, minor: 1, patch: 0)

        var createInfo = VkInstanceCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
        createInfo.pNext = nil
        createInfo.flags = 0
        createInfo.pApplicationInfo = nil   //temporary
        createInfo.enabledLayerCount = 0
        createInfo.ppEnabledLayerNames = nil
        createInfo.enabledExtensionCount = 0
        createInfo.ppEnabledExtensionNames = nil

        //Unsafe swift shit here

        withUnsafePointer(to: appInfo) { appInfoPtr in 
            createInfo.pApplicationInfo = appInfoPtr
        }

        #if os(macOS)
            print("we running on macOS")
            self.requiredExtensions?.append(UnsafePointer(portabilityCString))
            //also we have to set the flag
            createInfo.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR
        #endif

        createInfo.enabledExtensionCount = UInt32(requiredExtensions.getLength())
        createInfo.ppEnabledExtensionNames = requiredExtensions.getDataAsConstPointer()

        //DEBUG CREATE INFO STUFF
        var debugCreateInfo: VkDebugUtilsMessengerCreateInfoEXT = VkDebugUtilsMessengerCreateInfoEXT()
        if enableValidationLayers {
            createInfo.enabledLayerCount = UInt32(validationLayerNames.getLength())
            createInfo.ppEnabledLayerNames = validationLayerNames.getDataAsConstPointer()

            populateDebugMessengerCreateInfo(createInfo: &debugCreateInfo)
            withUnsafeMutableBytes(of: &debugCreateInfo) { rawBuffer in
                createInfo.pNext = UnsafeRawPointer(rawBuffer.baseAddress)
            }
        }

        if !checkAvailableExtensions() {
            fatalError("Available extensions and required extensions from sdl dont match!!")
        } else {
            print("The extensions match!")
        }

        //print("Pointer to extensions data: \(requiredExtensions.getDataAsConstPointer()!)")

        var vulkanInstance: VkInstance?
        let result = vkCreateInstance(&createInfo, nil, &vulkanInstance)
        if result != VK_SUCCESS {
            fatalError("Failed to create vulkan instance! \(result)")
        }

        self.instance = vulkanInstance
        print("Vulkan instance created successfully!")
    }

    func checkValidationLayerSupport() -> Bool {
        var layerCount: UInt32 = 0
        vkEnumerateInstanceLayerProperties(&layerCount, nil)
        let availableLayers: DynamicArray<VkLayerProperties> = DynamicArray<VkLayerProperties>(repeating: VkLayerProperties(), count: layerCount)
        vkEnumerateInstanceLayerProperties(&layerCount, availableLayers.getData())
        
        print("Available layers count: \(availableLayers.getLength())")

        for i in 0..<availableLayers.getLength() {
            // this converts a fixed-length (256) c-style array to UnsafePointer<CChar> 
            // and uses that pointer to create a swift string
            let layerName = withUnsafeBytes(of: availableLayers[i].layerName) { rawBuffer in
                return String(cString: rawBuffer.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            print("Layer \(i): \(layerName)")
        }

        for i in 0..<validationLayerNames.getLength() {
            var layerFound: Bool = false

            for j in 0..<availableLayers.getLength() {
                // this converts a fixed-length (256) c-style array to UnsafePointer<CChar> 
                // and uses that pointer to create a swift string
                let availableLayerName = withUnsafeBytes(of: availableLayers[j].layerName) { rawBuffer in 
                    return String(cString: rawBuffer.baseAddress!.assumingMemoryBound(to: CChar.self))
                }

                let validationLayer = String(cString: validationLayerNames[i]!)

                print("Checking: \(validationLayer) vs \(availableLayerName)")

                if validationLayer == availableLayerName {
                    layerFound = true
                    break
                }
            }

            if !layerFound {
                return false
            }
        }

        return true
    }

    func checkAvailableExtensions() -> Bool {
        var extensionCount: UInt32 = 0
        vkEnumerateInstanceExtensionProperties(nil, &extensionCount, nil)

        let extensions = DynamicArray<VkExtensionProperties>(repeating: VkExtensionProperties(), count: extensionCount)
        vkEnumerateInstanceExtensionProperties(nil, &extensionCount, extensions.getData())

        print("required extensions count: \(requiredExtensions.getLength())")

        for i in 0..<requiredExtensions.getLength() {
            var extensionFound = false
            let requiredExtensionName = String(cString: requiredExtensions[i]!)

            for j in 0..<extensions.getLength() {
                let extensionName = withUnsafeBytes(of: extensions[j].extensionName) { rawBuffer in 
                    return String(cString: rawBuffer.baseAddress!.assumingMemoryBound(to: CChar.self))
                }
                //print("available extension name: \(extensionName)")

                print("Checking: \(requiredExtensionName) vs \(extensionName)")

                if requiredExtensionName == extensionName {
                    print("They match!!")
                    extensionFound = true
                    break
                }
            }

            if !extensionFound {
                return false
            }
        }

        return true
    }

    //SURFACE FUNCTIONS
    func createSurface() {
        //then finally we can pass stuff to the platform
        let result = sdlContext.createSurface(instance: instance!, surface: &surface)
        if !result {
            fatalError("The vk surface is not valid!")
        } else {
            print("surface created successfully!")
        }

        print("Surface handle: \(surface!)")
    }

    //DEBUG FUNCTIONS

    private let debugCallback: @convention(c)(
        VkDebugUtilsMessageSeverityFlagBitsEXT,
        VkDebugUtilsMessageTypeFlagsEXT,
        UnsafePointer<VkDebugUtilsMessengerCallbackDataEXT>?,
        UnsafeMutableRawPointer?
    ) -> VkBool32 = { severity, type, callbackData, userData in
        if let message = callbackData?.pointee.pMessage {
            print("Validation layer: \(String(cString: message))")
        }

        return VkBool32(VK_FALSE)
    }

    private func createDebugUtilsMessengerEXT(
        instance: VkInstance,
        pCreateInfo: UnsafePointer<VkDebugUtilsMessengerCreateInfoEXT>,
        pAllocator: UnsafePointer<VkAllocationCallbacks>?,
        pDebugMessenger: UnsafeMutablePointer<VkDebugUtilsMessengerEXT?>?
    ) -> VkResult {
        //get function pointer from vulkan
        guard let rawPointer = vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT") else {
            print("Failed to load vkCreateDebugUtilsMessengerEXT")
            return VK_ERROR_EXTENSION_NOT_PRESENT
        }

        //Cast function popinter to the correct function type
        let createFunc = unsafeBitCast(rawPointer, to: (@convention(c)(
            VkInstance,
            UnsafePointer<VkDebugUtilsMessengerCreateInfoEXT>,
            UnsafePointer<VkAllocationCallbacks>?,
            UnsafeMutablePointer<VkDebugUtilsMessengerEXT?>?
        ) -> VkResult).self)

        //call the vulkan function
        return createFunc(instance, pCreateInfo, pAllocator, pDebugMessenger)
    }

    func destroyDebugUtilsMessengerEXT(
        instance: VkInstance,
        debugMessenger: VkDebugUtilsMessengerEXT,
        pAllocator: UnsafePointer<VkAllocationCallbacks>?
    ) {
        guard let rawPointer = vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT") else {
            print("failed to load vkDestroyDebugUtilsMessengerEXT")
            return
        }

        let deleteFunc = unsafeBitCast(rawPointer, to: (@convention(c)(
            VkInstance,
            VkDebugUtilsMessengerEXT,
            UnsafePointer<VkAllocationCallbacks>?
        ) -> Void ).self)

        //call
        deleteFunc(instance, debugMessenger, pAllocator)
    }

    func populateDebugMessengerCreateInfo(createInfo: inout VkDebugUtilsMessengerCreateInfoEXT) {
        createInfo = VkDebugUtilsMessengerCreateInfoEXT()
        createInfo.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
        createInfo.messageSeverity = VkDebugUtilsMessageSeverityFlagsEXT(
            VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT.rawValue
            | VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT.rawValue
            | VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT.rawValue
        )
        createInfo.messageType = VkDebugUtilsMessageTypeFlagsEXT(
            VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT.rawValue
            | VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT.rawValue
            | VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT.rawValue
        )
        createInfo.pfnUserCallback = debugCallback
        createInfo.pUserData = nil
    }
    

    func setupDebugMessenger() {
        if !enableValidationLayers { return }

        var createInfo: VkDebugUtilsMessengerCreateInfoEXT = VkDebugUtilsMessengerCreateInfoEXT()
        populateDebugMessengerCreateInfo(createInfo: &createInfo)

        if createDebugUtilsMessengerEXT(instance: instance!, pCreateInfo: &createInfo, 
            pAllocator: nil, pDebugMessenger: &debugMessenger) != VK_SUCCESS {
                fatalError("Failed to set up a debug messenger!")
        }

    }

    //VULKAN PHYSICAL DEVICE FUNCTIONS
    func pickPhysicalDevice() {
        var deviceCount: UInt32 = 0
        vkEnumeratePhysicalDevices(instance, &deviceCount, nil)

        if deviceCount == 0 {
            fatalError("Failed to find GPUs with vulkan support!")
        }

        let devices = DynamicArray<VkPhysicalDevice?>(capacity: deviceCount, count: Int(deviceCount))
        vkEnumeratePhysicalDevices(instance, &deviceCount, devices.getData())

        var candidates: [(Int, VkPhysicalDevice)] = []
        print("devices.getLength: \(devices.getLength())")
        for i in 0..<devices.getLength() {
            guard var device: VkPhysicalDevice = devices[i] else { fatalError("PhysicalDevice is nil!") }
            
            let score = rateDeviceSuitability(physDevice: &device)
            candidates.append((score, device))
        }

        //sort candidates by score (descending order, best gpu first)
        candidates.sort { (device1, device2) in
            return device1.0 > device2.0
        }

        //select the best device
        if let bestCandidate = candidates.first, bestCandidate.0 > 0 {
            physicalDevice = bestCandidate.1
        } else {
            fatalError("Failed to find a suitable GPU!")
        }
    }

    func rateDeviceSuitability(physDevice: inout VkPhysicalDevice) -> Int {
        var deviceProperties: VkPhysicalDeviceProperties = VkPhysicalDeviceProperties()
        vkGetPhysicalDeviceProperties(physDevice, &deviceProperties)

        var deviceFeatures: VkPhysicalDeviceFeatures = VkPhysicalDeviceFeatures()
        vkGetPhysicalDeviceFeatures(physDevice, &deviceFeatures)

        var score = 0

        let extensionsSupported = checkDeviceExtensionSupport(device: &physDevice)

        print("extensionsSupported is: \(extensionsSupported)")

        //swapchain shit
        var swapchainAdequate = false
        if extensionsSupported {
            print("Do we get here?")
            let swapchainSupport = querySwapchainSupport(physDevice: &physDevice)
            if let formats = swapchainSupport.formats, let presentModes = swapchainSupport.presentModes {
                swapchainAdequate = !formats.isEmpty() && !presentModes.isEmpty()
            } else {

            }
        }

        //create a temporary queueManager because the main one isnt initialized yet
        //maybe we can optimize this in the future but i doubt its a problem because this occurs during
        //the setup of the vulkan renderer, its not in a loop or anything
        let tempQueueManager = QueueManager(physicalDevice: physDevice, vulkanSurface: surface!, preferSeperateGraphicsQueue: false)

        if tempQueueManager.graphicsQueueFamilyIndex != nil {
            score += 500
        } else {
            print("the device has no graphics queue family!")
            return 0        //if no graphics queue family, return 0, not suitable
        }

        if deviceProperties.deviceType.rawValue == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU.rawValue {
            score += 1000
        }

        //maximum possible size of textures affects graphics quality
        score += Int(deviceProperties.limits.maxImageDimension2D)

        //application cant function without geometry shaders
        if deviceFeatures.geometryShader == 0 {
            return 0
        }

        //add more features to consider in the score
        if deviceFeatures.tessellationShader == 0 {
            score -= 500    //penalize devices witohut tessellation support
        }

        if extensionsSupported && swapchainAdequate {
            score += 1000
        } else {
            fatalError("Extensions are not supported or the swapchain is not adequate!")
        }

        print("Device score is: \(score)")

        return score
    }

    private func checkDeviceExtensionSupport(device: inout VkPhysicalDevice) -> Bool {
        var extensionCount: UInt32 = 0
        print("Device handle: \(device)")
        var deviceProps = VkPhysicalDeviceProperties()
        vkGetPhysicalDeviceProperties(device, &deviceProps)

        let result = vkEnumerateDeviceExtensionProperties(device, nil, &extensionCount, nil)
        print("vkEnumerateDeviceExtensionProperties result: \(result), extension count is: \(extensionCount)")

        var availableExtensions = [VkExtensionProperties](repeating: VkExtensionProperties(), count: Int(extensionCount))
        vkEnumerateDeviceExtensionProperties(device, nil, &extensionCount, &availableExtensions)

        print("availableExtensions.count is: \(availableExtensions.count)")

        for i in 0..<availableExtensions.count {

            let availableExtension = availableExtensions[i].extensionName
            
            for j in 0..<requiredDeviceExtensions.getLength() {
                let requiredExtension = requiredDeviceExtensions[j]
                
                guard let availableExtensionName = cCharTupleToString(cChars: availableExtension) else { return false }

                if availableExtensionName == String(cString: requiredExtension!) {
                    return true
                }

            }

        }

        return false
    }

    struct QueueFamilyIndices {
        public var graphicsFamily: UInt32?
        public var presentFamily: UInt32?
        public var transferFamily: UInt32?
    }

    //LOGICAL DEVICE FUNCTIONS
    func createLogicalDevice() {
        //set up everything in the queue manager
        queueManager = QueueManager(physicalDevice: physicalDevice!, vulkanSurface: surface!, preferSeperateGraphicsQueue: false)

        print("Indices.transferFamily is: \(String(describing: queueManager?.transferQueue))")

        var queueCreateInfos: DynamicArray<VkDeviceQueueCreateInfo> = 
            DynamicArray<VkDeviceQueueCreateInfo>()

        let uniqueQueueFamilyIndices = queueManager!.getUniqueQueueFamilyIndices()
        self.uniqueQueueFamilyIndices = DynamicArray<UInt32>()

        let queuePriority: Float = 1.0
        for queueFamilyIndex in uniqueQueueFamilyIndices {
            print("How many times does this get ran??")
            var queueCreateInfo = VkDeviceQueueCreateInfo()
            queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO
            queueCreateInfo.queueFamilyIndex = queueFamilyIndex
            queueCreateInfo.queueCount = 1
            withUnsafePointer(to: queuePriority) { queuePriority in
                queueCreateInfo.pQueuePriorities = queuePriority
            }
            queueCreateInfos.append(queueCreateInfo)

            //also add to the class member uniqueQueueFamilyIndices so that we dont have to 
            // retrieve it from the queuemanager again, we will need again later
            self.uniqueQueueFamilyIndices?.append(queueFamilyIndex)
        }

        var deviceFeatures = VkPhysicalDeviceFeatures()

        var createInfo = VkDeviceCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO
        
        createInfo.queueCreateInfoCount = UInt32(queueCreateInfos.getLength())
        createInfo.pQueueCreateInfos = queueCreateInfos.getDataAsConstPointer()

        withUnsafePointer(to: &deviceFeatures) { deviceFeatures in
            createInfo.pEnabledFeatures = deviceFeatures
        }

        createInfo.enabledExtensionCount = UInt32(requiredDeviceExtensions.getLength())
        createInfo.ppEnabledExtensionNames = requiredDeviceExtensions.getDataAsConstPointer()

        if enableValidationLayers {
            createInfo.enabledLayerCount = UInt32(validationLayerNames.getLength())
            createInfo.ppEnabledLayerNames = validationLayerNames.getDataAsConstPointer()
        } else {
            createInfo.enabledLayerCount = 0
        }

        var properties: VkPhysicalDeviceProperties = VkPhysicalDeviceProperties()
        vkGetPhysicalDeviceProperties(physicalDevice, &properties)
        guard let name = cCharTupleToString(cChars: properties.deviceName) else { fatalError("Device name is nil somehow ") }
        print("Physical device name: \(name)")

        let result = vkCreateDevice(physicalDevice, &createInfo, nil, &logicalDevice)
        if result != VK_SUCCESS {
            fatalError("Couldnt create logical device!")
        } else {
            print("logical device created successfully!")
        }

        //finally create/get the actual VkQueues
        queueManager?.setupQueues(logDevice: logicalDevice!)
    }

    public func getTotalVRAM() -> UInt64 {
        var memProperties = VkPhysicalDeviceProperties()
        vkGetPhysicalDeviceProperties(physicalDevice!, &memProperties)

        var memoryProps = VkPhysicalDeviceMemoryProperties()
        vkGetPhysicalDeviceMemoryProperties(physicalDevice!, &memoryProps)

        //sum up memory from device local heaps
        var totalVRAM: UInt64 = 0
        for i in 0..<memoryProps.memoryHeapCount {
            let heap = withUnsafeBytes(of: memoryProps.memoryHeaps) { rawBuffer in
                rawBuffer.baseAddress!.assumingMemoryBound(to: VkMemoryHeap.self)[Int(i)]
            }
            if heap.flags & UInt32(VK_MEMORY_HEAP_DEVICE_LOCAL_BIT.rawValue) != 0 {
                totalVRAM += heap.size
            }
        }

        return totalVRAM
    }

    //VMA SHIT
    func setupVmaAllocator() {
        var allocatorCreateInfo = 
            VmaAllocatorCreateInfo(
                flags: 0, // Remove VMA_ALLOCATOR_CREATE_EXT_MEMORY_BUDGET_BIT to reduce overhead
                physicalDevice: physicalDevice!, device: logicalDevice!, 
                preferredLargeHeapBlockSize: 16 * 1024 * 1024, // 16MB blocks instead of default
                pAllocationCallbacks: nil, 
                pDeviceMemoryCallbacks: nil, pHeapSizeLimit: nil, pVulkanFunctions: nil, 
                instance: instance!, vulkanApiVersion: makeVulkanVersion(major: 1, minor: 1, patch: 0), 
                pTypeExternalMemoryHandleTypes: nil
        )

        let result = vmaCreateAllocator(&allocatorCreateInfo, &vmaAllocator)
        if result != VK_SUCCESS {
            fatalError("Failed to create VMA allocator!")
        }

        print("\n Successfully created VMA Alocator!\n")
    }

    //SWAPCHAIN SHIT
    struct SwapchainSupportDetails: ~Copyable {
        var capabilities: VkSurfaceCapabilitiesKHR
        var formats: DynamicArray<VkSurfaceFormatKHR>?
        var presentModes: DynamicArray<VkPresentModeKHR>?
    }

    func querySwapchainSupport(physDevice: inout VkPhysicalDevice) -> SwapchainSupportDetails {
        var details: SwapchainSupportDetails = SwapchainSupportDetails(capabilities: VkSurfaceCapabilitiesKHR(), formats: nil, presentModes: nil)

        print("Using device: \(physDevice)")
        print("Surface Pointer: \(surface!)")
        let result = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physDevice, surface, &details.capabilities)
        if result != VK_SUCCESS {
            fatalError("Failed to get surface capabilities: \(result)")
        } else {
            print("Surface capabilities: \(details.capabilities)")
        }

        //now we get the array info
        var formatCount: UInt32 = 0
        vkGetPhysicalDeviceSurfaceFormatsKHR(physDevice, surface, &formatCount, nil)

        if formatCount != 0 {
            let formats = DynamicArray<VkSurfaceFormatKHR>(repeating: VkSurfaceFormatKHR(), count: formatCount)
            vkGetPhysicalDeviceSurfaceFormatsKHR(physDevice, surface, &formatCount, formats.getData())
            details.formats = consume formats
        }

        var presentModeCount: UInt32 = 0
        vkGetPhysicalDeviceSurfacePresentModesKHR(physDevice, surface, &presentModeCount, nil)

        if presentModeCount != 0 {
            let presentModes = DynamicArray<VkPresentModeKHR>(repeating: VkPresentModeKHR(0), count: presentModeCount)
            vkGetPhysicalDeviceSurfacePresentModesKHR(physDevice, surface, &presentModeCount, presentModes.getData())
            details.presentModes = consume presentModes
        }

        return details
    }

    func chooseSwapSurfaceFormat(availableFormats: inout DynamicArray<VkSurfaceFormatKHR>) -> VkSurfaceFormatKHR {
        print("Available surface formats:")
        for i in 0..<availableFormats.getLength() {
            print("  Format \(i): \(availableFormats[i].format), Color Space: \(availableFormats[i].colorSpace)")
        }
        
        // Look for the preferred format
        for i in 0..<availableFormats.getLength() {
            let availableFormat: VkSurfaceFormatKHR = availableFormats[i]
            if availableFormat.format == VK_FORMAT_B8G8R8A8_SRGB && availableFormat.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR {
                print("  Selected preferred format: VK_FORMAT_B8G8R8A8_SRGB")
                return availableFormat
            }
        }

        // If preferred format not found, look for any SRGB format
        for i in 0..<availableFormats.getLength() {
            let availableFormat: VkSurfaceFormatKHR = availableFormats[i]
            if availableFormat.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR {
                print("  Selected SRGB format: \(availableFormat.format)")
                return availableFormat
            }
        }

        print("  Using fallback format: \(availableFormats[0].format)")
        return availableFormats[0]
    }

    func setVSync(enable: Bool) {
        self.vSyncEnabled = enable
    }

    /// Chooses the appropriate swap present mode based on the current v-sync setting and the available present modes
    /// 
    /// This function selects the most suitable present mode for the swapchain:
    /// - If V-sync is enabled, it prefers "VK_PRESENT_MODE_FIFO_LATEST_READY_EXT" if its available, which provides a more modern, improved v-sync behavior
    /// - If "VK_PRESENT_MODE_FIFO_LATEST_READY_EXT" is not available, it falls back to "VK_PRESENT_MODE_FIFO_KHR", which is the traditional v-sync option
    /// - If v-sync is disabled (it is by default), it selects "VK_PRESENT_MODE_IMMEDIATE_KHR" for no buffering, allows tearing
    /// 
    /// - Parameter availablePresentModes: A list of available present modes supported by the device
    /// - Returns: The chosen present mode for the swapchain based on the V-sync setting
    func chooseSwapPresentMode(availablePresentModes: inout DynamicArray<VkPresentModeKHR>) -> VkPresentModeKHR {
        for i in 0..<availablePresentModes.getLength() {
            let availablePresentMode = availablePresentModes[i]
            // Note: VK_PRESENT_MODE_FIFO_LATEST_READY_EXT might not be available in all Vulkan versions
            // if vSyncEnabled && availablePresentMode == VK_PRESENT_MODE_FIFO_LATEST_READY_EXT {
            //     return availablePresentMode
            // }
            if vSyncEnabled && availablePresentMode == VK_PRESENT_MODE_FIFO_KHR {
                return availablePresentMode
            }
            if availablePresentMode == VK_PRESENT_MODE_IMMEDIATE_KHR {
                return availablePresentMode
            }
        }

        return VK_PRESENT_MODE_FIFO_KHR
    }

    //TODO:
    //not really sure i like the name chooseSwapExtent for the function because its not really for
    //choosing anything, yes the choice can be different but the user of the function isnt actually 
    //picking anything, maybe it should be named getSwapExtent? This goes for the function above as well honestly

    
    func chooseSwapExtent(capabilities: inout VkSurfaceCapabilitiesKHR) -> VkExtent2D {
        //if the currentExtent does not equal UInt32.max that means that the extent is a set value
        //can be the case if the vulkan app is in fullscreen mode. Otherwise the swapchain extent must
        //be set dynamically 

        //Actually afaik, this isnt actually true on windows, on windows the currentExtent is actually
        //the window size instead of UInt32.max, i think because of some win32 limitation or quirk
        //technically the logic here is still correct then but we need to be careful about any
        //assumptions we make here. This is important however when the window becomes minimized
        //because then it will return (0, 0) instead of the window size (before it was minimized)
        print("Surface capabilities current extent: \(capabilities.currentExtent.width)x\(capabilities.currentExtent.height)")
        
        if capabilities.currentExtent.width != UInt32.max {
            print("Using surface current extent: \(capabilities.currentExtent.width)x\(capabilities.currentExtent.height)")
            return capabilities.currentExtent
        } else {    //THIS IS NEVER GETTING EXECUTED????
            var width: Int32 = 0
            var height: Int32 = 0
            sdlContext.getWindowSizeInPixels(width: &width, height: &height)
            print("SDL window size: \(width)x\(height)")

            var actualExtent = VkExtent2D(width: UInt32(width), height: UInt32(height))
            // this clamps the values of the swap chain's extent
            // to the minimum and maximum specs of the swap chain
            actualExtent.width = max(capabilities.minImageExtent.width, min(capabilities.maxImageExtent.width, actualExtent.width))
            actualExtent.height = max(capabilities.minImageExtent.height, min(capabilities.maxImageExtent.height, actualExtent.height))

            print("Calculated extent (after clamping): \(actualExtent.width)x\(actualExtent.height)")
            return actualExtent
        }
    }

    func cleanupSwapchain() {
        if swapchainFrameBuffers != nil {
            while !swapchainFrameBuffers!.isEmpty() {
                let fb = swapchainFrameBuffers!.consumeElement(at: swapchainFrameBuffers!.getLength() - 1)
                if fb != nil {
                    vkDestroyFramebuffer(logicalDevice, fb, nil)
                }
            }
            swapchainFrameBuffers = nil
        }

        if swapchainImageViews != nil {
            while !swapchainImageViews!.isEmpty() {
                let iv = swapchainImageViews!.consumeElement(at: swapchainImageViews!.getLength() - 1)
                if iv != nil {
                    vkDestroyImageView(logicalDevice, iv, nil)
                }
            }
            swapchainImageViews = nil
        }

        if swapchain != nil {
            vkDestroySwapchainKHR(logicalDevice, swapchain, nil)
            swapchain = nil
        }
    }

    func recreateSwapchain() {
        print("recreating swapchain")

        vkDeviceWaitIdle(logicalDevice)

        cleanupSwapchain()

        createSwapchain()
        createImageViews()
        createFrameBuffers()
    }

    func createSwapchain() {
        print("\nInside createSwapchain!\n")
        // Ensure device is idle and previous swapchain is cleaned up before creating a new one
        vkDeviceWaitIdle(logicalDevice)
        cleanupSwapchain()

        // Check available memory before swapchain creation
        print("Checking system memory before swapchain creation...")
        let totalVRAM = getTotalVRAM()
        print("Total VRAM available: \(totalVRAM / (1024 * 1024)) MB")

        var swapchainSupport = querySwapchainSupport(physDevice: &physicalDevice!)
        let surfaceFormat = chooseSwapSurfaceFormat(availableFormats: &swapchainSupport.formats!)
        let presentMode = chooseSwapPresentMode(availablePresentModes: &swapchainSupport.presentModes!)
        let extent = chooseSwapExtent(capabilities: &swapchainSupport.capabilities)

        //add + 1 at the end for triple buffering (probably, it does depend on hardware)
        var imageCount = swapchainSupport.capabilities.minImageCount
        print("Minimum image count: \(swapchainSupport.capabilities.minImageCount)")
        print("Maximum image count: \(swapchainSupport.capabilities.maxImageCount)")
        // Use minimum image count to reduce memory usage
        // imageCount += 1  // Comment out triple buffering for now
        //this check is just in case we decide we want triple buffering or not
        if swapchainSupport.capabilities.maxImageCount > 0 && imageCount > swapchainSupport.capabilities.maxImageCount {
            imageCount = swapchainSupport.capabilities.maxImageCount
        }
        print("Using image count: \(imageCount)")

        //time for BS again
        var createInfo = VkSwapchainCreateInfoKHR()
        createInfo.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR
        createInfo.surface = surface
        createInfo.minImageCount = imageCount
        createInfo.imageFormat = surfaceFormat.format
        createInfo.imageColorSpace = surfaceFormat.colorSpace
        createInfo.imageExtent = extent
        createInfo.imageArrayLayers = 1
        // Restrict imageUsage to only VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT for compatibility
        createInfo.imageUsage = UInt32(VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue)

        if queueManager!.graphicsQueueFamilyIndex != queueManager!.presentQueueFamilyIndex {
            // VK_SHARING_MODE_CONCURRENT for graphics/present queues only
            print("Using VK_SHARING_MODE_CONCURRENT for graphics/present queues: [\(queueManager!.graphicsQueueFamilyIndex!), \(queueManager!.presentQueueFamilyIndex!)]")
            createInfo.imageSharingMode = VK_SHARING_MODE_CONCURRENT
            createInfo.queueFamilyIndexCount = 2
            let indices: [UInt32] = [queueManager!.graphicsQueueFamilyIndex!, queueManager!.presentQueueFamilyIndex!]
            createInfo.pQueueFamilyIndices = indices.withUnsafeBufferPointer { $0.baseAddress }
        } else {
            // VK_SHARING_MODE_EXCLUSIVE
            print("Using VK_SHARING_MODE_EXCLUSIVE for graphics/present queue: \(queueManager!.graphicsQueueFamilyIndex!)")
            createInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE
            createInfo.queueFamilyIndexCount = 0
            createInfo.pQueueFamilyIndices = nil
        }

        createInfo.preTransform = swapchainSupport.capabilities.currentTransform
        createInfo.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR
        createInfo.presentMode = presentMode
        createInfo.clipped = VK_TRUE
        createInfo.oldSwapchain = nil

        var result = vkCreateSwapchainKHR(logicalDevice, &createInfo, nil, &swapchain)
        print("vkCreateSwapchainKHR initial result: \(result)")
        print("result.rawValue: \(result.rawValue), VK_ERROR_SURFACE_LOST_KHR.rawValue: \(VK_ERROR_SURFACE_LOST_KHR.rawValue)")
        if Int32(result.rawValue) == Int32(VK_ERROR_SURFACE_LOST_KHR.rawValue) {
            print("VK_ERROR_SURFACE_LOST_KHR detected! Destroying and recreating surface, then retrying swapchain creation...")
            print("Surface pointer before destroy: \(String(describing: surface))")
            // Destroy old surface
            if let instance = instance, let surface = surface {
                vkDestroySurfaceKHR(instance, surface, nil)
            }
            surface = nil
            // Recreate surface
            createSurface()
            print("Surface pointer after recreate: \(String(describing: surface))")
            // Re-query swapchain support and update createInfo
            swapchainSupport = querySwapchainSupport(physDevice: &physicalDevice!)
            let surfaceFormat = chooseSwapSurfaceFormat(availableFormats: &swapchainSupport.formats!)
            _ = chooseSwapPresentMode(availablePresentModes: &swapchainSupport.presentModes!)
            let extent = chooseSwapExtent(capabilities: &swapchainSupport.capabilities)
            imageCount = swapchainSupport.capabilities.minImageCount
            createInfo.surface = surface
            createInfo.imageFormat = surfaceFormat.format
            createInfo.imageColorSpace = surfaceFormat.colorSpace
            createInfo.imageExtent = extent
            createInfo.minImageCount = imageCount
            print("Attempting swapchain creation after surface recreation...")
            result = vkCreateSwapchainKHR(logicalDevice, &createInfo, nil, &swapchain)
            print("vkCreateSwapchainKHR retry result: \(result)")
        }
        if result != VK_SUCCESS {
            print("Swapchain creation failed with error code: \(result)")
            print("Surface format: \(surfaceFormat.format), color space: \(surfaceFormat.colorSpace)")
            print("Present mode: \(presentMode)")
            print("Extent: \(extent.width)x\(extent.height)")
            print("Image count: \(imageCount)")
            print("Surface capabilities:")
            print("  Min extent: \(swapchainSupport.capabilities.minImageExtent.width)x\(swapchainSupport.capabilities.minImageExtent.height)")
            print("  Max extent: \(swapchainSupport.capabilities.maxImageExtent.width)x\(swapchainSupport.capabilities.maxImageExtent.height)")
            print("  Current extent: \(swapchainSupport.capabilities.currentExtent.width)x\(swapchainSupport.capabilities.currentExtent.height)")
            fatalError("Couldnt create swapchain!")
        } else {
            print("swapchain created!")
        }

        vkGetSwapchainImagesKHR(logicalDevice, swapchain, &imageCount, nil)
        swapchainImages = DynamicArray<VkImage?>(capacity: imageCount, count: Int(imageCount))
        vkGetSwapchainImagesKHR(logicalDevice, swapchain, &imageCount, swapchainImages?.getData())

        swapchainImageFormat = surfaceFormat.format
        swapchainExtent = extent
    }

    func setResolution(width: Int, height: Int) {
        
    }

    func resizeSwapchain() {
        recreateSwapchain()
    }

    //IMAGE VIEW SHIT
    func createImageViews() {
        guard let swapchainImageCount = swapchainImages?.getLength() else {
            fatalError("swapchainImages is nil, we crash now")
        }

        swapchainImageViews = DynamicArray<VkImageView?>(capacity: UInt32(swapchainImageCount))

        print("swapchainImageCount is: \(swapchainImageCount)")

        for i in 0..<swapchainImageCount {
            guard let swapchainImage: VkImage = swapchainImages?[i] else { return }
            var createInfo = VkImageViewCreateInfo()
            createInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
            createInfo.image = swapchainImage
            createInfo.viewType = VK_IMAGE_VIEW_TYPE_2D
            createInfo.format = swapchainImageFormat!

            createInfo.components.r = VK_COMPONENT_SWIZZLE_IDENTITY
            createInfo.components.g = VK_COMPONENT_SWIZZLE_IDENTITY
            createInfo.components.b = VK_COMPONENT_SWIZZLE_IDENTITY
            createInfo.components.a = VK_COMPONENT_SWIZZLE_IDENTITY

            createInfo.subresourceRange.aspectMask = UInt32(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
            createInfo.subresourceRange.baseMipLevel = 0
            createInfo.subresourceRange.levelCount = 1
            createInfo.subresourceRange.baseArrayLayer = 0
            createInfo.subresourceRange.layerCount = 1

            var imageView: VkImageView?

            let result = vkCreateImageView(logicalDevice, &createInfo, nil, &imageView)
            if result != VK_SUCCESS {
                fatalError("Failed to create image views!")
            }

            print("vkCreateImageView worked just fine!")
            print("imageView is: \(imageView!)")

            if let imageView = imageView {
                swapchainImageViews?.append(imageView)
            } else {
                fatalError("after vkCreateImageView, imageView is nil!")
            }
        }

        print("swapchainImageViews.getLength(): \(swapchainImageViews!.getLength())")
    }

    // Depth buffer creation
    func createDepthResources() {
        // Create depth image
        var imageInfo = VkImageCreateInfo()
        imageInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO
        imageInfo.imageType = VK_IMAGE_TYPE_2D
        imageInfo.extent.width = swapchainExtent!.width
        imageInfo.extent.height = swapchainExtent!.height
        imageInfo.extent.depth = 1
        imageInfo.mipLevels = 1
        imageInfo.arrayLayers = 1
        imageInfo.format = depthFormat
        imageInfo.tiling = VK_IMAGE_TILING_OPTIMAL
        imageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        imageInfo.usage = UInt32(VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT.rawValue)
        imageInfo.samples = VK_SAMPLE_COUNT_1_BIT
        imageInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE
        
        var allocInfo = VmaAllocationCreateInfo()
        allocInfo.usage = VMA_MEMORY_USAGE_GPU_ONLY
        
        let result = vmaCreateImage(vmaAllocator!, &imageInfo, &allocInfo, &depthImage, &depthImageMemory, nil)
        if result != VK_SUCCESS {
            fatalError("Failed to create depth image!")
        }
        
        // Create depth image view
        var viewInfo = VkImageViewCreateInfo()
        viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
        viewInfo.image = depthImage
        viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D
        viewInfo.format = depthFormat
        viewInfo.subresourceRange.aspectMask = UInt32(VK_IMAGE_ASPECT_DEPTH_BIT.rawValue)
        viewInfo.subresourceRange.baseMipLevel = 0
        viewInfo.subresourceRange.levelCount = 1
        viewInfo.subresourceRange.baseArrayLayer = 0
        viewInfo.subresourceRange.layerCount = 1
        
        let viewResult = vkCreateImageView(logicalDevice, &viewInfo, nil, &depthImageView)
        if viewResult != VK_SUCCESS {
            fatalError("Failed to create depth image view!")
        }
        
        print("Created depth buffer successfully!")
    }

    //Render passes
    func createRenderPass() {
        var colorAttachment = VkAttachmentDescription()
        colorAttachment.format = swapchainImageFormat!
        colorAttachment.samples = VK_SAMPLE_COUNT_1_BIT
        colorAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR
        colorAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE
        colorAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
        colorAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
        colorAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        colorAttachment.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR

        var depthAttachment = VkAttachmentDescription()
        depthAttachment.format = depthFormat
        depthAttachment.samples = VK_SAMPLE_COUNT_1_BIT
        depthAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR
        depthAttachment.storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
        depthAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
        depthAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
        depthAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        depthAttachment.finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL

        var colorAttachmentRef = VkAttachmentReference()
        colorAttachmentRef.attachment = 0
        colorAttachmentRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL

        var depthAttachmentRef = VkAttachmentReference()
        depthAttachmentRef.attachment = 1
        depthAttachmentRef.layout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL

        var subpass = VkSubpassDescription()
        subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS
        subpass.colorAttachmentCount = 1
        withUnsafePointer(to: &colorAttachmentRef) { pointer in
            subpass.pColorAttachments = pointer
        }
        withUnsafePointer(to: &depthAttachmentRef) { pointer in
            subpass.pDepthStencilAttachment = pointer
        }
        
        let attachments = [colorAttachment, depthAttachment]
        var renderPassInfo = VkRenderPassCreateInfo()
        renderPassInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO
        renderPassInfo.attachmentCount = 2
        attachments.withUnsafeBufferPointer { pointer in
            renderPassInfo.pAttachments = pointer.baseAddress
        }
        renderPassInfo.subpassCount = 1
        withUnsafePointer(to: &subpass) { pointer in
            renderPassInfo.pSubpasses = pointer
        }

        var dependency = VkSubpassDependency()
        dependency.srcSubpass = VK_SUBPASS_EXTERNAL
        dependency.dstSubpass = 0

        dependency.srcStageMask = UInt32(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue | VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT.rawValue)
        dependency.srcAccessMask = 0

        dependency.dstStageMask = UInt32(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue | VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT.rawValue)
        dependency.dstAccessMask = UInt32(VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT.rawValue)

        renderPassInfo.dependencyCount = 1
        withUnsafePointer(to: &dependency) { ptr in
            renderPassInfo.pDependencies = ptr
        }
        
        let result = vkCreateRenderPass(logicalDevice, &renderPassInfo, nil, &renderPass)
        if result != VK_SUCCESS {
            fatalError("failed to create render pass!")
        }

        print("Created render pass successfully!")

    }

    //Graphics pipeline
    func setAntiAliasing(enable: Bool) {

    }

    //TODO:
    ///NOT SURE IF I WILL USE THIS, PROBABLY DONT NEED RAYTRACING IN MY GAME
    func setRayTracing(enable: Bool) {
    
    }

    func loadShader(fromFile: String) {
    
    }

    func setClearColor() {

    }

    func enablePostProcessing() {

    }

    func setTargetFPS(fps: Int) {

    }

    func createFrameLayout() {
        var frameBindings = VkDescriptorSetLayoutBinding()
        frameBindings.binding = 0
        frameBindings.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
        frameBindings.descriptorCount = 1
        frameBindings.stageFlags = UInt32(VK_SHADER_STAGE_VERTEX_BIT.rawValue | VK_SHADER_STAGE_FRAGMENT_BIT.rawValue)
        frameBindings.pImmutableSamplers = nil

        var layoutInfo = VkDescriptorSetLayoutCreateInfo()
        layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
        layoutInfo.bindingCount = 1
        withUnsafePointer(to: &frameBindings) { ptr in
            layoutInfo.pBindings = ptr
        }

        let result = vkCreateDescriptorSetLayout(logicalDevice, &layoutInfo, nil, &frameSetLayout)
        if result != VK_SUCCESS {
            fatalError("Failed to create frame descriptor set layout!")
        }
        vkLog("🔷 VkDescriptorSetLayout CREATED: \(frameSetLayout!) in VulkanRenderer.createFrameLayout()")
    }

    func createTransformLayout() {
        var transformBindings = VkDescriptorSetLayoutBinding()
        transformBindings.binding = 0  // Changed from 1 to 0 to match shader expectation
        transformBindings.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC
        transformBindings.descriptorCount = 1
        transformBindings.stageFlags = UInt32(VK_SHADER_STAGE_VERTEX_BIT.rawValue)
        transformBindings.pImmutableSamplers = nil

        var transformLayoutInfo = VkDescriptorSetLayoutCreateInfo()
        transformLayoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
        transformLayoutInfo.bindingCount = 1
        withUnsafePointer(to: &transformBindings) { ptr in
            transformLayoutInfo.pBindings = ptr
        }

        let transformLayoutResult = vkCreateDescriptorSetLayout(logicalDevice, &transformLayoutInfo, nil, &transformSetLayout)
        if transformLayoutResult != VK_SUCCESS {
            fatalError("Failed to create transform descriptor set layout!")
        }
        vkLog("🔷 VkDescriptorSetLayout CREATED: \(transformSetLayout!) in VulkanRenderer.createTransformLayout()")
    }

    func createMaterialLayout3D() {
        let materialBindings = [
            VkDescriptorSetLayoutBinding(
                binding: 0,
                descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,  // Changed from DYNAMIC to static
                descriptorCount: 1,
                stageFlags: UInt32(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue),
                pImmutableSamplers: nil
            ),
            VkDescriptorSetLayoutBinding(
                binding: 1,
                descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                descriptorCount: 1,
                stageFlags: UInt32(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue),
                pImmutableSamplers: nil
            )
        ]

        var materialLayoutInfo = VkDescriptorSetLayoutCreateInfo()
        materialLayoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
        materialLayoutInfo.bindingCount = UInt32(materialBindings.count)
        materialBindings.withUnsafeBufferPointer { ptr in
            materialLayoutInfo.pBindings = ptr.baseAddress
        }

        let materialLayoutResult = vkCreateDescriptorSetLayout(logicalDevice, &materialLayoutInfo, nil, &materialSetLayout3D)
        if materialLayoutResult != VK_SUCCESS {
            fatalError("Failed to create material descriptor set layout!")
        }
        vkLog("🔷 VkDescriptorSetLayout CREATED: \(materialSetLayout3D!) in VulkanRenderer.createMaterialLayout3D()")
    }

    func createMaterialLayout2D() {
        let materialBindings2D = [
            VkDescriptorSetLayoutBinding(
                binding: 0,
                descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
                descriptorCount: 1,
                stageFlags: UInt32(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue),
                pImmutableSamplers: nil
            ),
            VkDescriptorSetLayoutBinding(
                binding: 1,
                descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                descriptorCount: 1,
                stageFlags: UInt32(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue),
                pImmutableSamplers: nil
            )
        ]

        var layoutInfo2D = VkDescriptorSetLayoutCreateInfo()
        layoutInfo2D.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
        layoutInfo2D.bindingCount = 2
        materialBindings2D.withUnsafeBufferPointer { ptr in
            layoutInfo2D.pBindings = ptr.baseAddress
        }

        let result = vkCreateDescriptorSetLayout(logicalDevice, &layoutInfo2D, nil, &materialSetLayout2D)
        if result != VK_SUCCESS {
            fatalError("Failed to create material descriptor set layout!")
        }
        vkLog("🔷 VkDescriptorSetLayout CREATED: \(materialSetLayout2D!) in VulkanRenderer.createMaterialLayout2D()")
    }
    
    // 2D Transform Layout (Set 0 for 2D shaders: projection + model matrix)
    func createTransform2DLayout() {
        let transform2DBindings = [
            VkDescriptorSetLayoutBinding(
                binding: 0,
                descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                descriptorCount: 1,
                stageFlags: UInt32(VK_SHADER_STAGE_VERTEX_BIT.rawValue),
                pImmutableSamplers: nil
            )
        ]
        
        var layoutInfo = VkDescriptorSetLayoutCreateInfo()
        layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
        layoutInfo.bindingCount = 1
        transform2DBindings.withUnsafeBufferPointer { ptr in
            layoutInfo.pBindings = ptr.baseAddress
        }
        
        let result = vkCreateDescriptorSetLayout(logicalDevice, &layoutInfo, nil, &transform2DSetLayout)
        if result != VK_SUCCESS {
            fatalError("Failed to create 2D transform descriptor set layout!")
        }
        vkLog("🔷 VkDescriptorSetLayout CREATED: \(transform2DSetLayout!) in VulkanRenderer.createTransform2DLayout()")
    }
    
    // 2D Material Layout (Set 1 for 2D shaders: material data + texture)
    func createMaterial2DLayout() {
        let material2DBindings = [
            VkDescriptorSetLayoutBinding(
                binding: 0,
                descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                descriptorCount: 1,
                stageFlags: UInt32(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue),
                pImmutableSamplers: nil
            ),
            VkDescriptorSetLayoutBinding(
                binding: 1,
                descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                descriptorCount: 1,
                stageFlags: UInt32(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue),
                pImmutableSamplers: nil
            )
        ]
        
        var layoutInfo = VkDescriptorSetLayoutCreateInfo()
        layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
        layoutInfo.bindingCount = 2
        material2DBindings.withUnsafeBufferPointer { ptr in
            layoutInfo.pBindings = ptr.baseAddress
        }
        
        let result = vkCreateDescriptorSetLayout(logicalDevice, &layoutInfo, nil, &material2DSetLayout)
        if result != VK_SUCCESS {
            fatalError("Failed to create 2D material descriptor set layout!")
        }
        vkLog("🔷 VkDescriptorSetLayout CREATED: \(material2DSetLayout!) in VulkanRenderer.createMaterial2DLayout()")
    }
    
    // UI Projection Layout (Set 0 for UI shaders: projection + screen size)
    func createUIProjectionLayout() {
        let uiProjectionBindings = [
            VkDescriptorSetLayoutBinding(
                binding: 0,
                descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                descriptorCount: 1,
                stageFlags: UInt32(VK_SHADER_STAGE_VERTEX_BIT.rawValue),
                pImmutableSamplers: nil
            )
        ]
        
        var layoutInfo = VkDescriptorSetLayoutCreateInfo()
        layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
        layoutInfo.bindingCount = 1
        uiProjectionBindings.withUnsafeBufferPointer { ptr in
            layoutInfo.pBindings = ptr.baseAddress
        }
        
        let result = vkCreateDescriptorSetLayout(logicalDevice, &layoutInfo, nil, &uiProjectionSetLayout)
        if result != VK_SUCCESS {
            fatalError("Failed to create UI projection descriptor set layout!")
        }
        vkLog("🔷 VkDescriptorSetLayout CREATED: \(uiProjectionSetLayout!) in VulkanRenderer.createUIProjectionLayout()")
    }
    
    // UI Material Layout (Set 1 for UI shaders: material data + texture)
    func createUIMaterialLayout() {
        let uiMaterialBindings = [
            VkDescriptorSetLayoutBinding(
                binding: 0,
                descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                descriptorCount: 1,
                stageFlags: UInt32(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue),
                pImmutableSamplers: nil
            ),
            VkDescriptorSetLayoutBinding(
                binding: 1,
                descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                descriptorCount: 1,
                stageFlags: UInt32(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue),
                pImmutableSamplers: nil
            )
        ]
        
        var layoutInfo = VkDescriptorSetLayoutCreateInfo()
        layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
        layoutInfo.bindingCount = 2
        uiMaterialBindings.withUnsafeBufferPointer { ptr in
            layoutInfo.pBindings = ptr.baseAddress
        }
        
        let result = vkCreateDescriptorSetLayout(logicalDevice, &layoutInfo, nil, &uiMaterialSetLayout)
        if result != VK_SUCCESS {
            fatalError("Failed to create UI material descriptor set layout!")
        }
        vkLog("🔷 VkDescriptorSetLayout CREATED: \(uiMaterialSetLayout!) in VulkanRenderer.createUIMaterialLayout()")
    }

    func createPostProcessingLayout() {
        //Post processing needs multiple texture samplers for different effects
        let postProcessingBindings = [
            VkDescriptorSetLayoutBinding(
                binding: 0,
                descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                descriptorCount: 1,
                stageFlags: UInt32(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue),
                pImmutableSamplers: nil
            ),
            VkDescriptorSetLayoutBinding(
                binding: 1,
                descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                descriptorCount: 1,
                stageFlags: UInt32(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue),
                pImmutableSamplers: nil
            ),
            VkDescriptorSetLayoutBinding(
                binding: 2,
                descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                descriptorCount: 1,
                stageFlags: UInt32(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue),
                pImmutableSamplers: nil
            )
        ]

        var layoutInfo = VkDescriptorSetLayoutCreateInfo()
        layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
        layoutInfo.bindingCount = UInt32(postProcessingBindings.count)
        postProcessingBindings.withUnsafeBufferPointer { ptr in
            layoutInfo.pBindings = ptr.baseAddress
        }

        let result = vkCreateDescriptorSetLayout(logicalDevice, &layoutInfo, nil, &postProcessingSetLayout)
        if result != VK_SUCCESS {
            fatalError("Failed to create post-processing descriptor set layout!")
        }
        vkLog("🔷 VkDescriptorSetLayout CREATED: \(postProcessingSetLayout!) in VulkanRenderer.createPostProcessingLayout()")
    }

    func createDescriptorPool() {
        let poolSizes = [
            VkDescriptorPoolSize(type: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, descriptorCount: 10),
            VkDescriptorPoolSize(type: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC, descriptorCount: 10),
            VkDescriptorPoolSize(type: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, descriptorCount: 10)
        ]
        
        var poolInfo = VkDescriptorPoolCreateInfo()
        poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO
        poolInfo.poolSizeCount = UInt32(poolSizes.count)
        poolInfo.maxSets = 10  // Maximum number of descriptor sets that can be allocated
        
        poolSizes.withUnsafeBufferPointer { poolSizesPtr in
            poolInfo.pPoolSizes = poolSizesPtr.baseAddress
        }
        
        let result = vkCreateDescriptorPool(logicalDevice, &poolInfo, nil, &descriptorPool)
        if result != VK_SUCCESS {
            fatalError("Failed to create descriptor pool!")
        }
    }
    
    func allocateDescriptorSets() {
        guard let descriptorPool = descriptorPool else {
            fatalError("Descriptor pool not created")
        }
        
        // Allocate frame descriptor set
        if let frameLayout = frameSetLayout {
            var frameAllocInfo = VkDescriptorSetAllocateInfo()
            frameAllocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
            frameAllocInfo.descriptorPool = descriptorPool
            frameAllocInfo.descriptorSetCount = 1
            withUnsafePointer(to: frameLayout) { layoutPtr in
                frameAllocInfo.pSetLayouts = layoutPtr
            }
            
            vkAllocateDescriptorSets(logicalDevice, &frameAllocInfo, &frameDescriptorSet)
        }
        
        // Allocate transform descriptor set  
        if let transformLayout = transformSetLayout {
            var transformAllocInfo = VkDescriptorSetAllocateInfo()
            transformAllocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
            transformAllocInfo.descriptorPool = descriptorPool
            transformAllocInfo.descriptorSetCount = 1
            withUnsafePointer(to: transformLayout) { layoutPtr in
                transformAllocInfo.pSetLayouts = layoutPtr
            }
            
            vkAllocateDescriptorSets(logicalDevice, &transformAllocInfo, &transformDescriptorSet)
        }
        
        // Allocate material descriptor set (3D)
        if let materialLayout = materialSetLayout3D {
            var materialAllocInfo = VkDescriptorSetAllocateInfo()
            materialAllocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
            materialAllocInfo.descriptorPool = descriptorPool
            materialAllocInfo.descriptorSetCount = 1
            withUnsafePointer(to: materialLayout) { layoutPtr in
                materialAllocInfo.pSetLayouts = layoutPtr
            }
            
            vkAllocateDescriptorSets(logicalDevice, &materialAllocInfo, &materialDescriptorSet)
        }
        
        // Allocate UI projection descriptor set
        if let uiProjectionLayout = uiProjectionSetLayout {
            var uiProjectionAllocInfo = VkDescriptorSetAllocateInfo()
            uiProjectionAllocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
            uiProjectionAllocInfo.descriptorPool = descriptorPool
            uiProjectionAllocInfo.descriptorSetCount = 1
            withUnsafePointer(to: uiProjectionLayout) { layoutPtr in
                uiProjectionAllocInfo.pSetLayouts = layoutPtr
            }
            
            vkAllocateDescriptorSets(logicalDevice, &uiProjectionAllocInfo, &uiProjectionDescriptorSet)
        }
        
        // Allocate UI material descriptor set
        if let uiMaterialLayout = uiMaterialSetLayout {
            var uiMaterialAllocInfo = VkDescriptorSetAllocateInfo()
            uiMaterialAllocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
            uiMaterialAllocInfo.descriptorPool = descriptorPool
            uiMaterialAllocInfo.descriptorSetCount = 1
            withUnsafePointer(to: uiMaterialLayout) { layoutPtr in
                uiMaterialAllocInfo.pSetLayouts = layoutPtr
            }
            
            vkAllocateDescriptorSets(logicalDevice, &uiMaterialAllocInfo, &uiMaterialDescriptorSet)
        }
    }

    // REMOVED: Old high-level pipeline methods
    // - createDescriptorSet(for pipelineType: PipelineType)  
    // - updateDescriptorSets(for pipelineType: PipelineType)
    // - updateMaterialDescriptorSet(for pipelineType: PipelineType)
    // These have been replaced with low-level methods that VulkanPipelineImpl calls directly

    private func updateFrameDescriptorSet() {
        guard let frameDescriptorSet = frameDescriptorSet else {
            fatalError("Frame descriptor set not allocated!")
        }

        var frameDescriptorWrite = VkWriteDescriptorSet()
        frameDescriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
        frameDescriptorWrite.dstSet = frameDescriptorSet
        frameDescriptorWrite.dstBinding = 0
        frameDescriptorWrite.dstArrayElement = 0
        frameDescriptorWrite.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
        frameDescriptorWrite.descriptorCount = 1

        var frameBufferInfo = VkDescriptorBufferInfo()
        frameBufferInfo.buffer = frameUBO
        frameBufferInfo.offset = 0
        frameBufferInfo.range = VkDeviceSize(MemoryLayout<FrameConstants>.size)

        withUnsafePointer(to: &frameBufferInfo) { ptr in
            frameDescriptorWrite.pBufferInfo = ptr
        }

        vkUpdateDescriptorSets(logicalDevice, 1, &frameDescriptorWrite, 0, nil)
        print("Updated frame descriptor set")
    }

    private func updateTransformDescriptorSet() {
        guard let transformDescriptorSet = transformDescriptorSet else {
            fatalError("Transform descriptor set not allocated!")
        }

        var transformDescriptorWrite = VkWriteDescriptorSet()
        transformDescriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
        transformDescriptorWrite.dstSet = transformDescriptorSet
        transformDescriptorWrite.dstBinding = 0 // Binding 0 for transform UBO
        transformDescriptorWrite.dstArrayElement = 0
        transformDescriptorWrite.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC
        transformDescriptorWrite.descriptorCount = 1

        var transformBufferInfo = VkDescriptorBufferInfo()
        transformBufferInfo.buffer = transformUBO
        transformBufferInfo.offset = 0
        transformBufferInfo.range = VkDeviceSize(MemoryLayout<TransformConstants>.size)

        withUnsafePointer(to: &transformBufferInfo) { ptr in
            transformDescriptorWrite.pBufferInfo = ptr
        }

        vkUpdateDescriptorSets(logicalDevice, 1, &transformDescriptorWrite, 0, nil)
        print("Updated transform descriptor set!")
    }

    private func updateMaterialDescriptorSet() {
        guard let materialDescriptorSet = materialDescriptorSet else {
            fatalError("Material descriptor set not allocated!")
        }

        // Material buffer info (binding 0)
        var materialBufferInfo = VkDescriptorBufferInfo()
        materialBufferInfo.buffer = materialUBO3D!  // Use the 3D material UBO
        materialBufferInfo.offset = 0
        materialBufferInfo.range = VkDeviceSize(MemoryLayout<MaterialConstants3D>.size)

        var materialBufferWrite = VkWriteDescriptorSet()
        materialBufferWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
        materialBufferWrite.dstSet = materialDescriptorSet
        materialBufferWrite.dstBinding = 0 // Binding 0 for material UBO
        materialBufferWrite.dstArrayElement = 0
        materialBufferWrite.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
        materialBufferWrite.descriptorCount = 1
        withUnsafePointer(to: &materialBufferInfo) { ptr in
            materialBufferWrite.pBufferInfo = ptr
        }

        // Texture/sampler info (binding 1) - use default or first available texture
        var writes: [VkWriteDescriptorSet] = [materialBufferWrite]
        
        if let textureManager = textureManager {
            // Try to get default texture (first available, or will be nil if none exist)
            if let vulkanTexture = textureManager.getDefaultTexture() {
                var imageInfo = VkDescriptorImageInfo()
                imageInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
                imageInfo.imageView = vulkanTexture.imageView
                imageInfo.sampler = vulkanTexture.sampler
                
                var textureWrite = VkWriteDescriptorSet()
                textureWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
                textureWrite.dstSet = materialDescriptorSet
                textureWrite.dstBinding = 1 // Binding 1 for diffuse texture
                textureWrite.dstArrayElement = 0
                textureWrite.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
                textureWrite.descriptorCount = 1
                withUnsafePointer(to: &imageInfo) { ptr in
                    textureWrite.pImageInfo = ptr
                }
                
                writes.append(textureWrite)
                print("Material descriptor set: Using texture with imageView: \(String(describing: vulkanTexture.imageView))")
            } else {
                print("Material descriptor set: No textures available yet - will update later when textures are loaded")
            }
        }

        // Update all descriptor writes at once
        writes.withUnsafeBufferPointer { writesPtr in
            vkUpdateDescriptorSets(logicalDevice, UInt32(writes.count), writesPtr.baseAddress, 0, nil)
        }
        
        print("Updated material descriptor set!")
    }

    private func updateUIProjectionDescriptorSet() {
        guard let uiProjectionDescriptorSet = uiProjectionDescriptorSet else {
            fatalError("UI projection descriptor set not allocated!")
        }

        var uiProjectionDescriptorWrite = VkWriteDescriptorSet()
        uiProjectionDescriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
        uiProjectionDescriptorWrite.dstSet = uiProjectionDescriptorSet
        uiProjectionDescriptorWrite.dstBinding = 0
        uiProjectionDescriptorWrite.dstArrayElement = 0
        uiProjectionDescriptorWrite.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
        uiProjectionDescriptorWrite.descriptorCount = 1

        var uiProjectionBufferInfo = VkDescriptorBufferInfo()
        uiProjectionBufferInfo.buffer = uiProjectionUBO
        uiProjectionBufferInfo.offset = 0
        uiProjectionBufferInfo.range = VkDeviceSize(MemoryLayout<UIProjectionConstants>.size)

        withUnsafePointer(to: &uiProjectionBufferInfo) { ptr in
            uiProjectionDescriptorWrite.pBufferInfo = ptr
        }

        vkUpdateDescriptorSets(logicalDevice, 1, &uiProjectionDescriptorWrite, 0, nil)
        print("Updated UI projection descriptor set")
    }

    private func updateUIMaterialDescriptorSet() {
        guard let uiMaterialDescriptorSet = uiMaterialDescriptorSet else {
            print("Warning: UI material descriptor set not allocated - skipping update")
            return
        }

        guard let uiMaterialUBO = uiMaterialUBO, let uiMaterialUBOMemory = uiMaterialUBOMemory else {
            print("Warning: UI material UBO not available - skipping update")
            return
        }

        var material = currentUIMaterial
        var mappedMemory: UnsafeMutableRawPointer?
        let mapResult = vmaMapMemory(vmaAllocator!, uiMaterialUBOMemory, &mappedMemory)
        if mapResult == VK_SUCCESS {
            withUnsafeBytes(of: &material) { bytes in
                mappedMemory!.copyMemory(from: bytes.baseAddress!, byteCount: MemoryLayout<UIMaterialConstants>.stride)
            }
            vmaUnmapMemory(vmaAllocator!, uiMaterialUBOMemory)
        } else {
            print("Warning: Failed to map UI material UBO")
            return
        }

        var writes: [VkWriteDescriptorSet] = []
        var bufferInfos: [VkDescriptorBufferInfo] = []
        var imageInfos: [VkDescriptorImageInfo] = []

        bufferInfos.append(VkDescriptorBufferInfo(
            buffer: uiMaterialUBO,
            offset: 0,
            range: VkDeviceSize(MemoryLayout<UIMaterialConstants>.stride)
        ))

        var materialWrite = VkWriteDescriptorSet()
        materialWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
        materialWrite.dstSet = uiMaterialDescriptorSet
        materialWrite.dstBinding = 0
        materialWrite.dstArrayElement = 0
        materialWrite.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
        materialWrite.descriptorCount = 1
        writes.append(materialWrite)

        if let textureManager = textureManager {
            var selectedTexture: VulkanTexture?
            if let textureIndex = currentUITextureIndex {
                selectedTexture = textureManager.getVulkanTexture(at: textureIndex)
                if selectedTexture == nil {
                    print("Warning: UI texture index \(textureIndex) is invalid (texture count: \(textureManager.getTextureCount())). Falling back to default texture.")
                }
            }

            if selectedTexture == nil {
                selectedTexture = textureManager.getDefaultTexture()
            }

            if let selectedTexture = selectedTexture {
                imageInfos.append(VkDescriptorImageInfo(
                    sampler: selectedTexture.sampler,
                    imageView: selectedTexture.imageView,
                    imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
                ))

                var textureWrite = VkWriteDescriptorSet()
                textureWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
                textureWrite.dstSet = uiMaterialDescriptorSet
                textureWrite.dstBinding = 1
                textureWrite.dstArrayElement = 0
                textureWrite.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
                textureWrite.descriptorCount = 1
                writes.append(textureWrite)
            } else {
                print("Warning: No UI texture available to bind for UI material descriptor set.")
            }
        }

        bufferInfos.withUnsafeBufferPointer { bufferPtr in
            imageInfos.withUnsafeBufferPointer { imagePtr in
                if !writes.isEmpty {
                    writes[0].pBufferInfo = bufferPtr.baseAddress
                }
                if writes.count > 1 {
                    writes[1].pImageInfo = imagePtr.baseAddress
                }

                writes.withUnsafeBufferPointer { writesPtr in
                    vkUpdateDescriptorSets(logicalDevice, UInt32(writes.count), writesPtr.baseAddress, 0, nil)
                }
            }
        }
    }

    func setUIMaterial(
        textureMode: Int32,
        textureIndex: Int?,
        tint: Color = .white,
        opacity: Float = 1.0,
        sdfThreshold: Float? = nil,
        sdfRange: Float? = nil,
        outlineWidth: Float? = nil,
        outlineColor: Color? = nil
    ) {
        currentUIMaterial.textureMode = textureMode
        currentUIMaterial.tint = tint
        currentUIMaterial.opacity = opacity
        if let sdfThreshold {
            currentUIMaterial.sdfThreshold = sdfThreshold
        }
        if let sdfRange {
            currentUIMaterial.sdfRange = max(0.001, sdfRange)
        }
        if let outlineWidth {
            currentUIMaterial.outlineWidth = max(0.0, outlineWidth)
        }
        if let outlineColor {
            currentUIMaterial.outlineColor = outlineColor
        }
        currentUITextureIndex = textureIndex
        if textureMode == 3 {
            currentUIMaterial.reserved1 = 1.0
            currentUIMaterial.reserved2 = uiTextUsesMSDF ? 1.0 : 0.0
        }
        updateUIMaterialDescriptorSet()
    }

    // Toggle between readable fallback mode (false) and true SDF reconstruction mode (true).
    func setUITextTrueSDFMode(_ enabled: Bool) {
        currentUIMaterial.reserved1 = enabled ? 1.0 : 0.0
        print("UI text mode: \(enabled ? "TrueSDF" : "FallbackReadable")")
        updateUIMaterialDescriptorSet()
    }

    func setUITextSDFStepDebugMode(_ enabled: Bool) {
        currentUIMaterial.reserved2 = enabled ? 1.0 : 0.0
        print("UI text SDF step-debug: \(enabled ? "ON" : "OFF")")
        updateUIMaterialDescriptorSet()
    }

    func setUITextMSDFMode(_ enabled: Bool) {
        uiTextUsesMSDF = enabled
        print("UI text sampling mode: \(enabled ? "MSDF" : "SDF")")
        updateUIMaterialDescriptorSet()
    }

    func setUITextSDFParameters(threshold: Float, range: Float) {
        currentUIMaterial.sdfThreshold = threshold
        currentUIMaterial.sdfRange = max(0.001, range)
        print("UI text SDF params: threshold=\(threshold), range=\(currentUIMaterial.sdfRange)")
        updateUIMaterialDescriptorSet()
    }

    // REMOVED: Old updateMaterialDescriptorSet(for pipelineType: PipelineType)
    // High-level method removed - VulkanPipelineImpl handles descriptor set creation directly

    func createShaderModule(code: inout DynamicArray<UInt8>) -> VkShaderModule? {
        var createInfo: VkShaderModuleCreateInfo = VkShaderModuleCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
        createInfo.codeSize = code.getLength()
        createInfo.pCode = code.getDataAsUInt32Pointer()

        var shaderModule: VkShaderModule? = nil
        let result = withUnsafeMutablePointer(to: &shaderModule) { ptr in
            vkCreateShaderModule(logicalDevice, &createInfo, nil, ptr)
        }

        if result != VK_SUCCESS {
            fatalError("Couldnt create shader module!")
        }

        print("Shader module created successfully!")

        return shaderModule
    }

    //Frame Buffer stuff
    func createFrameBuffers() {
        guard let imageViewCount = swapchainImageViews?.getLength() else { fatalError("swapchainImageViews.getLength() is not valid") }
        swapchainFrameBuffers = DynamicArray<VkFramebuffer?>(repeating: VkFramebuffer(bitPattern: 0), count: UInt32(imageViewCount))

        for i in 0..<imageViewCount {
            let attachments = [swapchainImageViews?[i], depthImageView]

            var frameBufferInfo = VkFramebufferCreateInfo()
            frameBufferInfo.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO
            frameBufferInfo.renderPass = renderPass
            frameBufferInfo.attachmentCount = 2
            attachments.withUnsafeBufferPointer { pointer in
                frameBufferInfo.pAttachments = pointer.baseAddress
            }
            frameBufferInfo.width = swapchainExtent!.width
            frameBufferInfo.height = swapchainExtent!.height
            frameBufferInfo.layers = 1

            if swapchainFrameBuffers == nil {
                fatalError()
            }
            let result = vkCreateFramebuffer(logicalDevice, &frameBufferInfo, nil, &swapchainFrameBuffers![i] )
            if result != VK_SUCCESS {
                fatalError("Failed to create frame buffer")
            }
        }

        print("Created frame buffers successfully!")
    }

    //Command Pool shit here
    func createCommandPool() {
        guard let queueManager = self.queueManager else { fatalError("queueManager is nil!") }

        var poolInfo = VkCommandPoolCreateInfo()
        poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
        poolInfo.flags = UInt32(VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT.rawValue)
        poolInfo.queueFamilyIndex = queueManager.graphicsQueueFamilyIndex!

        var result = vkCreateCommandPool(logicalDevice, &poolInfo, nil, &commandPool)
        if result != VK_SUCCESS {
            fatalError("Could not create command pool!")
        }

        if queueManager.graphicsQueueFamilyIndex != queueManager.transferQueueFamilyIndex {
            var transferPoolInfo = VkCommandPoolCreateInfo()
            transferPoolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
            transferPoolInfo.flags = UInt32(VK_COMMAND_POOL_CREATE_TRANSIENT_BIT.rawValue)
            transferPoolInfo.queueFamilyIndex = queueManager.transferQueueFamilyIndex!

            result = vkCreateCommandPool(logicalDevice, &transferPoolInfo, nil, &transferCommandPool)
            if result != VK_SUCCESS {
                fatalError("Could not create transfer command pool!")
            }
        } else {
            print("Transfer queue family is the same as graphics, using the same command pool!")
            transferCommandPool = commandPool
        }

        print("Created command pool(s) successfully!")
    }

    //Buffer AND Vertex buffer SHIT
    func createBuffer(size: VkDeviceSize, usage: VkBufferUsageFlags, properties: VkMemoryPropertyFlags,
        isDynamic: Bool = false, buffer: inout VkBuffer?, bufferAllocation: inout VmaAllocation?) {

        //VMA allocation info
        var allocInfo = VmaAllocationCreateInfo()
        allocInfo.flags = 0
        allocInfo.requiredFlags = properties
        allocInfo.usage = VMA_MEMORY_USAGE_AUTO
        allocInfo.pUserData = nil

        //Just in case the buffer is supposed to be host visible (also make sure to check if its a dynamic UBO)
        let isHostVisible = (properties & UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue)) != 0

        if isHostVisible {
            allocInfo.flags |= isDynamic
                ? ( UInt32(VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT.rawValue) |
                    UInt32(VMA_ALLOCATION_CREATE_MAPPED_BIT.rawValue))

                :   UInt32(VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT.rawValue)
        }

        //Create buffer with VMA (this will handle memory allocation automatically)
        var bufferInfo = VkBufferCreateInfo()
        bufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
        bufferInfo.size = size
        bufferInfo.usage = usage
        bufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE

        var allocation: VmaAllocation? = nil
        let result = vmaCreateBuffer(vmaAllocator!, &bufferInfo, &allocInfo, &buffer, &allocation, nil)
        if result != VK_SUCCESS {
            fatalError("Failed to create buffer with VMA!")
        }

        print("\n Successfully created buffer with VMA!")

        //retrieve allocation information
        var allocInfoStruct = VmaAllocationInfo()
        vmaGetAllocationInfo(vmaAllocator!, allocation!, &allocInfoStruct)

        bufferAllocation = allocation
    }

    func copyBuffer(srcBuffer: VkBuffer?, dstBuffer: VkBuffer?, size: VkDeviceSize) {
        var allocInfo = VkCommandBufferAllocateInfo()
        allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
        allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY
        allocInfo.commandPool = transferCommandPool
        allocInfo.commandBufferCount = 1

        var commandBuffer: VkCommandBuffer? = nil
        vkAllocateCommandBuffers(logicalDevice, &allocInfo, &commandBuffer)
        defer {
            vkFreeCommandBuffers(logicalDevice, transferCommandPool, 1, &commandBuffer)
        }

        var beginInfo = VkCommandBufferBeginInfo()
        beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
        beginInfo.flags = UInt32(VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT.rawValue)

        vkBeginCommandBuffer(commandBuffer, &beginInfo)

        var copyRegion = VkBufferCopy()
        copyRegion.srcOffset = 0
        copyRegion.dstOffset = 0
        copyRegion.size = size
        vkCmdCopyBuffer(commandBuffer, srcBuffer, dstBuffer, 1, &copyRegion)

        vkEndCommandBuffer(commandBuffer)

        var submitInfo = VkSubmitInfo()
        submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO
        submitInfo.commandBufferCount = 1
        withUnsafePointer(to: &commandBuffer) { ptr in
            submitInfo.pCommandBuffers = ptr
        }
        
        //MAYBE USE A FENCE LATER FOR THIS?
        vkQueueSubmit(queueManager?.transferQueue, 1, &submitInfo, nil)
        vkQueueWaitIdle(queueManager?.transferQueue)
    }

    //for sending read-only data (like for lighting) to the gpu
    func createUniformBuffer() {
        // Frame constants (camera, lighting)
        let frameUBOSize = VkDeviceSize(MemoryLayout<FrameConstants>.stride)
        createBuffer(
            size: frameUBOSize,
            usage: UInt32(VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT.rawValue),
            properties: UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue) |
                        UInt32(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue),
            buffer: &frameUBO,
            bufferAllocation: &frameUBOMemory
        )

        // Transform constants (per model)
        let transformUBOSize = VkDeviceSize(MemoryLayout<TransformConstants>.stride * MAX_OBJECTS)
        createBuffer(
            size: transformUBOSize,
            usage: UInt32(VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT.rawValue),
            properties: UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue) |
                        UInt32(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue),
            isDynamic: true,
            buffer: &transformUBO,
            bufferAllocation: &transformUBOMemory
        )

        // Material constants for 3D rendering (per mesh)
        let materialUBOSize3D = VkDeviceSize(MemoryLayout<MaterialConstants3D>.stride * MAX_MATERIALS)
        createBuffer(
            size: materialUBOSize3D,
            usage: UInt32(VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT.rawValue),
            properties: UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue) |
                        UInt32(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue),
            isDynamic: true,
            buffer: &materialUBO3D,
            bufferAllocation: &materialUBOMemory3D
        )

        // Material constants for 2D rendering (per sprite)  
        let materialUBOSize2D = VkDeviceSize(MemoryLayout<MaterialConstants2D>.stride * MAX_MATERIALS)
        createBuffer(
            size: materialUBOSize2D,
            usage: UInt32(VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT.rawValue),
            properties: UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue) |
                        UInt32(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue),
            isDynamic: true,
            buffer: &materialUBO2D,
            bufferAllocation: &materialUBOMemory2D
        )

        // UI projection constants (orthographic projection + screen size)
        let uiProjectionUBOSize = VkDeviceSize(MemoryLayout<UIProjectionConstants>.stride)
        createBuffer(
            size: uiProjectionUBOSize,
            usage: UInt32(VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT.rawValue),
            properties: UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue) |
                        UInt32(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue),
            buffer: &uiProjectionUBO,
            bufferAllocation: &uiProjectionUBOMemory
        )

        let uiMaterialUBOSize = VkDeviceSize(MemoryLayout<UIMaterialConstants>.stride)
        createBuffer(
            size: uiMaterialUBOSize,
            usage: UInt32(VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT.rawValue),
            properties: UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue) |
                        UInt32(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue),
            buffer: &uiMaterialUBO,
            bufferAllocation: &uiMaterialUBOMemory
        )
    }

    //helper function for loading model data
    func uploadModelData(vertices: inout DynamicArray<Vertex3D>, indices: inout DynamicArray<UInt32>) {
        
    }

    private func findMemoryType(typeFilter: UInt32, properties: VkMemoryPropertyFlags) -> UInt32 {
        var memProperties = VkPhysicalDeviceMemoryProperties()
        vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memProperties)

        // TODO: Replace this massive tuple conversion with InlineArray when Swift 6.2+ features are stable
        // memProperties.memoryTypes is a huge tuple that should be replaced with a proper array-like structure
        let memoryTypesArray = tupleToArray(memProperties.memoryTypes) as! [VkMemoryType]

        for i in 0..<memProperties.memoryTypeCount {
            let index = Int(i)
            if (typeFilter & (1 << i) != 0) && (memoryTypesArray[index].propertyFlags & properties) == properties {
                return i
            }
        }

        fatalError("Failed to find suitable memory type!")
    }

    func createCommandBuffers() {
        var allocInfo = VkCommandBufferAllocateInfo()
        allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO

        allocInfo.commandPool = commandPool
        allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY
        allocInfo.commandBufferCount = 1

        let result = vkAllocateCommandBuffers(logicalDevice, &allocInfo, &commandBuffer)
        if result != VK_SUCCESS {
            fatalError("failed to allocate command buffers!")
        }

        print("Created command buffer successfully!")
    }

    func calculateAlignment() {
        var properties = VkPhysicalDeviceProperties()
        vkGetPhysicalDeviceProperties(physicalDevice, &properties)

        let minAlignment = properties.limits.minUniformBufferOffsetAlignment

        // Calculate alignment for transform UBO
        let transformRawSize: VkDeviceSize = VkDeviceSize(MemoryLayout<TransformConstants>.size)
        transformAlignment = (transformRawSize + minAlignment - 1) & ~(minAlignment - 1)

        // Calculate alignment for material UBO  
        let materialRawSize: VkDeviceSize = VkDeviceSize(MemoryLayout<MaterialConstants3D>.size)
        materialAlignment = (materialRawSize + minAlignment - 1) & ~(minAlignment - 1)

        print("Transform UBO entry uses \(transformAlignment) bytes")
        print("Material UBO entry uses \(materialAlignment) bytes")
    }

    func calculateAlignment2D() {
        var properties = VkPhysicalDeviceProperties()
        vkGetPhysicalDeviceProperties(physicalDevice, &properties)

        let minAlignment = properties.limits.minUniformBufferOffsetAlignment

        //Calculate alignment for 2D transform UBO
        let transformRawSize: VkDeviceSize = VkDeviceSize(MemoryLayout<TransformConstants>.size)
        transformAlignment2D = (transformRawSize + minAlignment - 1) & ~(minAlignment - 1)

        //Calculate alignment for 2D material UBO
        let materialRawSize: VkDeviceSize = VkDeviceSize(MemoryLayout<MaterialConstants2D>.size)
        materialAlignment2D = (materialRawSize + minAlignment - 1) & ~(minAlignment - 1)

        print("2D Transform UBO entry uses \(transformAlignment2D) bytes")
        print("2D Material UBO entry uses \(materialAlignment2D) bytes")
    }

    func calculateAlignment3D() {
        var properties = VkPhysicalDeviceProperties()
        vkGetPhysicalDeviceProperties(physicalDevice, &properties)

        let minAlignment = properties.limits.minUniformBufferOffsetAlignment

        //Calculate alignment for 3D transform UBO
        let transformRawSize: VkDeviceSize = VkDeviceSize(MemoryLayout<TransformConstants>.size)
        transformAlignment3D = (transformRawSize + minAlignment - 1) & ~(minAlignment - 1)

        //Calculate alignment for 3D material UBO
        let materialRawSize: VkDeviceSize = VkDeviceSize(MemoryLayout<MaterialConstants3D>.size)
        materialAlignment3D = (materialRawSize + minAlignment - 1) & ~(minAlignment - 1)

        print("3D Transform UBO entry uses \(transformAlignment3D) bytes")
        print("3D Material UBO entry uses \(materialAlignment3D) bytes")
    }

    private var transformDebugCounter = 0
    
    func updateTransformUBO(at offset: Int, transform: Transform) {
        var constants = TransformConstants(
            modelMatrix: transform.modelMatrix,
            normalMatrix: transform.normalMatrix
        )
        
        // Transform matrices updated at offset \(offset)

        var dataPtr: UnsafeMutableRawPointer?
        let result = vmaMapMemory(vmaAllocator!, transformUBOMemory!, &dataPtr)
        if result != VK_SUCCESS {
            fatalError("Failed to map transform UBO memory!")
        }

        let destPtr = dataPtr!.advanced(by: offset)
        memcpy(destPtr, &constants, MemoryLayout<TransformConstants>.size)

        vmaUnmapMemory(vmaAllocator!, transformUBOMemory!)
    }

    func updateMaterialUBO3D(at offset: Int, material: Material) {
        guard let materialUploader = materialUploader else {
            fatalError("Material uploader not initialized!")
        }
        
        // Use VulkanMaterialUploader to convert Material to MaterialData
        materialUploader.update(from: material)
        
        // Create 3D material constants
        var constants = MaterialConstants3D(
            materialID: 0  // We don't need this anymore since we have real material data
        )
        constants.baseColor = Vector4(
            material.baseColor.linearR,
            material.baseColor.linearG,
            material.baseColor.linearB,
            material.isOpaque ? 1.0 : material.alphaCutoff
        )
        constants.metallicFactor = material.metallicFactor
        constants.roughnessFactor = material.roughnessFactor
        


        var dataPtr: UnsafeMutableRawPointer?
        let result = vmaMapMemory(vmaAllocator!, materialUBOMemory3D!, &dataPtr)
        if result != VK_SUCCESS {
            fatalError("Failed to map 3D material UBO memory!")
        }

        let destPtr = dataPtr!.advanced(by: offset)
        memcpy(destPtr, &constants, MemoryLayout<MaterialConstants3D>.size)

        vmaUnmapMemory(vmaAllocator!, materialUBOMemory3D!)
    }

    func updateMaterialUBO2D(at offset: Int, tintColor: Vector4 = Vector4(1,1,1,1), uvScale: Vector2 = Vector2(1,1), uvOffset: Vector2 = Vector2(0,0), alpha: Float = 1.0) {
        var constants = MaterialConstants2D(
            tintColor: tintColor,
            uvScale: uvScale,
            uvOffset: uvOffset,
            alpha: alpha,
            effectParams: Vector3(0,0,0)  // No special effects by default
        )
        


        var dataPtr: UnsafeMutableRawPointer?
        let result = vmaMapMemory(vmaAllocator!, materialUBOMemory2D!, &dataPtr)
        if result != VK_SUCCESS {
            fatalError("Failed to map 2D material UBO memory!")
        }

        let destPtr = dataPtr!.advanced(by: offset)
        memcpy(destPtr, &constants, MemoryLayout<MaterialConstants2D>.size)

        vmaUnmapMemory(vmaAllocator!, materialUBOMemory2D!)
    }

    // TODO: VulkanRenderer is a low-level graphics API wrapper and shouldn't know about high-level concepts like Frustum.
    // This frustum culling logic should be moved to a higher-level rendering system or scene manager.
    public func calculateViewFrustum(projectionMatrix: Matrix4x4, viewMatrix: Matrix4x4) -> Frustum {
        let pvMatrix = projectionMatrix * viewMatrix

        //Extract frustum planes from the combined projection-view matrix
        // Format: ax + by + cz + d = 0
        var planes: [Vector4] = []

        // Left plane
        planes.append(Vector4(
            pvMatrix[3][0] + pvMatrix[0][0],
            pvMatrix[3][1] + pvMatrix[0][1],
            pvMatrix[3][2] + pvMatrix[0][2],
            pvMatrix[3][3] + pvMatrix[0][3]
        ))

        //right plane
        planes.append(Vector4(
            pvMatrix[3][0] - pvMatrix[0][0],
            pvMatrix[3][1] - pvMatrix[0][1],
            pvMatrix[3][2] - pvMatrix[0][2],
            pvMatrix[3][3] - pvMatrix[0][3]
        ))

        //bottom plane
        planes.append(Vector4(
            pvMatrix[3][0] + pvMatrix[1][0],
            pvMatrix[3][1] + pvMatrix[1][1],
            pvMatrix[3][2] + pvMatrix[1][2],
            pvMatrix[3][3] + pvMatrix[1][3]
        ))

        //top plane
        planes.append(Vector4(
            pvMatrix[3][0] - pvMatrix[1][0],
            pvMatrix[3][1] - pvMatrix[1][1],
            pvMatrix[3][2] - pvMatrix[1][2],
            pvMatrix[3][3] - pvMatrix[1][3]
        ))

        // near plane
        planes.append(Vector4(
            pvMatrix[3][0] + pvMatrix[2][0],
            pvMatrix[3][1] + pvMatrix[2][1],
            pvMatrix[3][2] + pvMatrix[2][2],
            pvMatrix[3][3] + pvMatrix[2][3]
        ))

        //far plane
        planes.append(Vector4(
            pvMatrix[3][0] - pvMatrix[2][0],
            pvMatrix[3][1] - pvMatrix[2][1],
            pvMatrix[3][2] - pvMatrix[2][2],
            pvMatrix[3][3] - pvMatrix[2][3]
        ))

        //normalize the planes
        planes = planes.map { plane in
            let length = sqrt(plane.x * plane.x + plane.y * plane.y + plane.z * plane.z)
            return plane / length
        }

        // TODO: Refactor frustum creation out of VulkanRenderer. Renderer is low-level and should not depend on scene/culling domain types.
        return Frustum(planes: planes)

    }

    private var debugFrameCount = 0
    
    private func updateFrameUBO() {
        // Create frame constants with current camera data - matching shader layout exactly
        var frameConstants = FrameConstants(
            viewMatrix: camera.viewMatrix,
            projectionMatrix: camera.projectionMatrix,  
            lightPosition: Vector3(50.0, 50.0, -50.0), // Move light much further away and behind camera
            lightColor: Vector3(2.0, 2.0, 2.0),        // Brighter white light
            cameraPosition: camera.position             // viewPos in shader
        )
        
        // Debug: Print camera matrices occasionally
        debugFrameCount += 1
        if debugFrameCount == 1 {
            print("🎯 CAMERA DEBUG - Camera at position: \(camera.position)")
        }
        
        // Map the frame UBO memory and copy data
        var mappedMemory: UnsafeMutableRawPointer?
        let result = vmaMapMemory(vmaAllocator!, frameUBOMemory!, &mappedMemory)
        if result == VK_SUCCESS {
            withUnsafeBytes(of: &frameConstants) { bytes in
                mappedMemory!.copyMemory(from: bytes.baseAddress!, byteCount: MemoryLayout<FrameConstants>.stride)
            }
            vmaUnmapMemory(vmaAllocator!, frameUBOMemory!)
        }
    }

    private func updateUIProjection() {
        guard let _ = uiProjectionUBO, let uiProjectionUBOMemory = uiProjectionUBOMemory else {
            print("Warning: UI projection UBO not available")
            return
        }
        
        // Get current screen size from swapchain
        let screenWidth = Float(swapchainExtent!.width)
        let screenHeight = Float(swapchainExtent!.height)
        
        // Create orthographic projection matrix for screen space to NDC
        // Maps screen coordinates (0,0) at top-left to (screenWidth,screenHeight) at bottom-right
        // NDC range: (-1,-1) to (1,1)
        // NOTE: For correct orthographic matrix, top > bottom
        let left: Float = 0.0
        let right: Float = screenWidth
        let top: Float = screenHeight    // Larger Y value (bottom of screen in screen coords)
        let bottom: Float = 0.0         // Smaller Y value (top of screen in screen coords)
        let near: Float = -1.0
        let far: Float = 1.0
        
        let orthoMatrix = orthographicMatrix(left: left, right: right, bottom: bottom, top: top, near: near, far: far)
        
        print("🔢 UI Orthographic matrix: left=\(left), right=\(right), top=\(top), bottom=\(bottom)")
        print("🔢 Matrix: [\(orthoMatrix[0]), \(orthoMatrix[1]), \(orthoMatrix[2]), \(orthoMatrix[3])]")
        
        var uiProjectionConstants = UIProjectionConstants(
            projection: orthoMatrix,
            screenSize: Vector2(screenWidth, screenHeight),
            padding: Vector2(0, 0)
        )
        
        // Map the UI projection UBO memory and copy data
        var mappedMemory: UnsafeMutableRawPointer?
        let result = vmaMapMemory(vmaAllocator!, uiProjectionUBOMemory, &mappedMemory)
        if result == VK_SUCCESS {
            withUnsafeBytes(of: &uiProjectionConstants) { bytes in
                mappedMemory!.copyMemory(from: bytes.baseAddress!, byteCount: MemoryLayout<UIProjectionConstants>.stride)
            }
            vmaUnmapMemory(vmaAllocator!, uiProjectionUBOMemory)
        }
        
        print("📱 Updated UI projection: screen=\(screenWidth)x\(screenHeight)")
    }

    //Synchronization shit
    func createSyncObjects() {
        imageAvailableSemaphores = DynamicArray<VkSemaphore?>(capacity: UInt32(MAX_FRAMES_IN_FLIGHT))
        renderFinishedSemaphores = DynamicArray<VkSemaphore?>(capacity: UInt32(MAX_FRAMES_IN_FLIGHT))
        inFlightFences = DynamicArray<VkFence?>(capacity: UInt32(MAX_FRAMES_IN_FLIGHT))

        var semaphoreInfo = VkSemaphoreCreateInfo()
        semaphoreInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO

        var fenceInfo = VkFenceCreateInfo()
        fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
        fenceInfo.flags = UInt32(VK_FENCE_CREATE_SIGNALED_BIT.rawValue)

        for _ in 0..<MAX_FRAMES_IN_FLIGHT {
            var semaphore1: VkSemaphore? = nil
            var semaphore2: VkSemaphore? = nil
            var fence: VkFence? = nil

            if vkCreateSemaphore(logicalDevice, &semaphoreInfo, nil, &semaphore1) != VK_SUCCESS
                || vkCreateSemaphore(logicalDevice, &semaphoreInfo, nil, &semaphore2) != VK_SUCCESS
                || vkCreateFence(logicalDevice, &fenceInfo, nil, &fence) != VK_SUCCESS {
                    fatalError("failed to create synchronization objects for a frame!")
            }

            imageAvailableSemaphores?.append(semaphore1)
            renderFinishedSemaphores?.append(semaphore2)
            inFlightFences?.append(fence)
        }
        
        print("Created semaphores and fence successfully!")
    }

    func synchronize() {

    }

    //MARK: - Frame lifecycle (Low level Vulkan operations)

    //Phase 1: Acquire swapchain image and prepare for rendering
    func acquireFrame() -> UInt32? {
        vkWaitForFences(logicalDevice, 1, &inFlightFences![currentFrame], VK_TRUE, UInt64.max)
    
        var imageIndex: UInt32 = 0
        let result = vkAcquireNextImageKHR(logicalDevice, swapchain, UInt64.max,
            imageAvailableSemaphores![currentFrame], nil, &imageIndex)

        if result == VK_ERROR_OUT_OF_DATE_KHR {
            recreateSwapchain()
            return nil
        } else if result != VK_SUCCESS && result != VK_SUBOPTIMAL_KHR {
            fatalError("Failed to acquire swapchain image!")
        }

        vkResetFences(logicalDevice, 1, &inFlightFences![currentFrame])

        return imageIndex
    }

    //Phase 2: Begin command buffer recording and render pass
    func beginRenderPass(imageIndex: UInt32) {
        vkResetCommandBuffer(commandBuffer, 0)

        //Begin command buffer
        var beginInfo = VkCommandBufferBeginInfo()
        beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
        vkBeginCommandBuffer(commandBuffer, &beginInfo)

        //Begin render pass
        var renderPassInfo = VkRenderPassBeginInfo()
        renderPassInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
        renderPassInfo.renderPass = renderPass
        renderPassInfo.framebuffer = swapchainFrameBuffers![Int(imageIndex)]
        renderPassInfo.renderArea.offset = VkOffset2D(x: 0, y: 0)
        renderPassInfo.renderArea.extent = swapchainExtent!

        let clearValues = [
            VkClearValue(color: VkClearColorValue(float32: (0.1, 0.2, 0.3, 1.0))),  // Faded blue background
            VkClearValue(depthStencil: VkClearDepthStencilValue(depth: 1.0, stencil: 0))
        ]

        renderPassInfo.clearValueCount = 2
        clearValues.withUnsafeBufferPointer { ptr in
            renderPassInfo.pClearValues = ptr.baseAddress
        }

        vkCmdBeginRenderPass(commandBuffer, &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE)

        //Set viewport and scissor (Shared by all pipelines)
        setViewportAndScissor()

        //DONT BIND ANY PIPELINE - thats the job of VulkanPipelineImpl
    }

    private func setViewportAndScissor() {
        var viewport = VkViewport()
        viewport.x = 0.0
        viewport.y = 0.0
        viewport.width = Float(swapchainExtent!.width)
        viewport.height = Float(swapchainExtent!.height)
        viewport.minDepth = 0.0
        viewport.maxDepth = 1.0

        print("📺 Viewport: (\(viewport.x), \(viewport.y)) size: \(viewport.width)x\(viewport.height)")
        print("📺 Expected: 800x600, Swapchain extent: \(swapchainExtent!.width)x\(swapchainExtent!.height)")
        vkCmdSetViewport(commandBuffer, 0, 1, &viewport)

        var scissor = VkRect2D()
        scissor.offset = VkOffset2D(x: 0, y: 0)
        scissor.extent = swapchainExtent!

        vkCmdSetScissor(commandBuffer, 0, 1, &scissor)
    }

    func endRenderPass() {
        vkCmdEndRenderPass(commandBuffer)
    }

    //MARK: - High-level frame management (for input latency optimization)
    
    /// Phase 1: Acquire frame and begin render pass - call this before polling input
    func createFrame() -> UInt32? {
        guard let imageIndex = acquireFrame() else {
            return nil
        }
        
        // Note: No longer resetting 2D buffers - using smart caching like 3D models!
        
        // Update camera matrices before rendering
        updateFrameUBO()
        
        // Update UI projection matrix
        updateUIProjection()
        
        // Update UI descriptor sets
        updateUIProjectionDescriptorSet()
        updateUIMaterialDescriptorSet()
        
        beginRenderPass(imageIndex: imageIndex)
        return imageIndex
    }
    
    /// Phase 2: End render pass and present - call this after all drawing is done
    func renderFrame(imageIndex: UInt32) {
        endRenderPass()
        presentFrame(imageIndex: imageIndex)
    }

    func presentFrame(imageIndex: UInt32) {
        vkEndCommandBuffer(commandBuffer)

        // Submit command buffer to graphics queue
        var submitInfo = VkSubmitInfo()
        submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO
        
        let waitSemaphores = [imageAvailableSemaphores![currentFrame]]
        let waitStages: [VkPipelineStageFlags] = [UInt32(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue)]
        let signalSemaphores = [renderFinishedSemaphores![currentFrame]]
        
        waitSemaphores.withUnsafeBufferPointer { waitSemPtr in
            waitStages.withUnsafeBufferPointer { waitStagePtr in
                signalSemaphores.withUnsafeBufferPointer { signalSemPtr in
                    submitInfo.waitSemaphoreCount = 1
                    submitInfo.pWaitSemaphores = waitSemPtr.baseAddress
                    submitInfo.pWaitDstStageMask = waitStagePtr.baseAddress
                    submitInfo.commandBufferCount = 1
                    submitInfo.pCommandBuffers = withUnsafePointer(to: commandBuffer) { $0 }
                    submitInfo.signalSemaphoreCount = 1
                    submitInfo.pSignalSemaphores = signalSemPtr.baseAddress
                    
                    if vkQueueSubmit(queueManager?.graphicsQueue, 1, &submitInfo, inFlightFences![currentFrame]) != VK_SUCCESS {
                        fatalError("Failed to submit draw command buffer!")
                    }
                }
            }
        }
        
        // Present to swapchain
        var presentInfo = VkPresentInfoKHR()
        presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR
        presentInfo.waitSemaphoreCount = 1
        presentInfo.pWaitSemaphores = withUnsafePointer(to: renderFinishedSemaphores![currentFrame]) { $0 }
        presentInfo.swapchainCount = 1
        presentInfo.pSwapchains = withUnsafePointer(to: swapchain) { $0 }
        presentInfo.pImageIndices = withUnsafePointer(to: imageIndex) { $0 }
        
        let presentResult = vkQueuePresentKHR(queueManager?.presentQueue, &presentInfo)
        
        if presentResult == VK_ERROR_OUT_OF_DATE_KHR || presentResult == VK_SUBOPTIMAL_KHR {
            recreateSwapchain()
        } else if presentResult != VK_SUCCESS {
            fatalError("Failed to present swapchain image!")
        }
        
        // Advance to next frame
        currentFrame = (currentFrame + 1) % MAX_FRAMES_IN_FLIGHT
    }

    func bindPipeline(_ pipeline: VkPipeline) {
        vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline)
    }

    func bindDescriptorSets(pipelineLayout: VkPipelineLayout, firstSet: UInt32, sets: [VkDescriptorSet], dynamicOffsets: [UInt32] = []) {
        sets.withUnsafeBufferPointer { setsPtr in
            dynamicOffsets.withUnsafeBufferPointer { offsetsPtr in
                vkCmdBindDescriptorSets(
                    commandBuffer,
                    VK_PIPELINE_BIND_POINT_GRAPHICS,
                    pipelineLayout,
                    firstSet,
                    UInt32(sets.count),
                    UnsafePointer<VkDescriptorSet?>(OpaquePointer(setsPtr.baseAddress)),
                    UInt32(dynamicOffsets.count),
                    offsetsPtr.baseAddress
                )
            }
        }
    }
    
    private var drawDebugCount = 0
    
    func drawModelsWithDynamicOffsets(_ models: [Model], pipelineLayout: VkPipelineLayout, transformDescriptorSet: VkDescriptorSet) {
        print("📍 drawModelsWithDynamicOffsets called with \(models.count) models")
        print("📍 pipelineLayout: \(pipelineLayout), transformDescriptorSet: \(transformDescriptorSet)")
        var currentTransformIndex = 0
        
        drawDebugCount += 1
        let showDebug = drawDebugCount <= 3
        if showDebug {

        }
        
        for model in models {
            // Bind vertex buffer for all models (same buffer)
            print("📍 Command buffer: \(commandBuffer != nil ? "valid" : "NULL")")
            print("📍 Resource manager: \(resourceManager != nil ? "valid" : "NULL")")
            resourceManager?.withStaticVertexBuffer { vertexBuffer in
                if showDebug {
                    print("    Binding vertex buffer: size=\(vertexBuffer.size)")
                }
                print("📍 Binding vertex buffer: handle=\(vertexBuffer.bufferHandle.asVulkanBuffer())")
                vkCmdBindVertexBuffers(commandBuffer, 0, 1, withUnsafePointer(to: vertexBuffer.bufferHandle.asVulkanBuffer()) { $0 }, withUnsafePointer(to: VkDeviceSize(0)) { $0 })
            }

            // Bind index buffer (same for all models)
            resourceManager?.withIndexBuffer { indexBuffer in
                if showDebug {
                    print("    Binding index buffer: size=\(indexBuffer.size)")
                }
                print("📍 Binding index buffer: handle=\(indexBuffer.bufferHandle.asVulkanBuffer())")
                vkCmdBindIndexBuffer(commandBuffer, indexBuffer.bufferHandle.asVulkanBuffer(), 0, VK_INDEX_TYPE_UINT32)
            }

            // Update transform for this model
            let transformOffset = currentTransformIndex * Int(transformAlignment)
            print("📍 Transform offset: \(transformOffset), alignment: \(transformAlignment)")
            updateTransformUBO(at: transformOffset, transform: model.transform)
            
            // Rebind transform descriptor set with correct dynamic offset for this model
            let dynamicOffsets = [UInt32(transformOffset)]
            print("📍 Binding transform descriptor set (set 1) with offset: \(dynamicOffsets)")
            bindDescriptorSets(pipelineLayout: pipelineLayout, firstSet: 1, sets: [transformDescriptorSet], dynamicOffsets: dynamicOffsets)

            // Draw all meshes in this model
            if showDebug {
                print("  Model \(currentTransformIndex): position=\(model.transform.position), scale=\(model.transform.scale), \(model.meshes.count) meshes")
            }
            print("📍 About to draw \(model.meshes.count) meshes for model \(currentTransformIndex)")
            for mesh in model.meshes {
                if showDebug {
                    print("    Drawing mesh: indices=\(mesh.indexCount), offset=\(mesh.indexOffset), vertexOffset=\(mesh.vertexOffset)")
                }
                print("📍 Drawing mesh: indices=\(mesh.indexCount), offset=\(mesh.indexOffset), vertexOffset=\(mesh.vertexOffset)")
                vkCmdDrawIndexed(
                    commandBuffer!,
                    UInt32(mesh.indexCount),
                    1,
                    UInt32(mesh.indexOffset),
                    Int32(mesh.vertexOffset),
                    0
                )
                print("✅ Draw call executed successfully")
            }
            
            currentTransformIndex += 1
        }
    }
    
    /// Clean UI rendering method that mirrors 3D model rendering
    /// Uses 2D buffers and existing UI descriptor sets
    func drawUIModelsWithOffsets(_ uiModels: [ModelUI], pipelineLayout: VkPipelineLayout) {
        print("🎨 drawUIModelsWithOffsets called with \(uiModels.count) UI models")
        
        guard !uiModels.isEmpty else {
            print("📦 No UI models to render")
            return
        }
        
        // Use resource manager to access 2D buffers (same as UI upload system)
        resourceManager?.withVertex2DBuffer { vertexBuffer in
            resourceManager?.withIndex2DBuffer { indexBuffer in
                // Bind 2D buffers once for all UI models
                print("🎨 Binding 2D vertex buffer: \(vertexBuffer.bufferHandle.asVulkanBuffer())")
                vkCmdBindVertexBuffers(commandBuffer, 0, 1, 
                                     withUnsafePointer(to: vertexBuffer.bufferHandle.asVulkanBuffer()) { $0 }, 
                                     withUnsafePointer(to: VkDeviceSize(0)) { $0 })
                
                print("🎨 Binding 2D index buffer: \(indexBuffer.bufferHandle.asVulkanBuffer())")
                vkCmdBindIndexBuffer(commandBuffer, indexBuffer.bufferHandle.asVulkanBuffer(), 
                                   VkDeviceSize(0), VK_INDEX_TYPE_UINT32)
                
                // Draw all UI models
                for uiModel in uiModels {
                    for uiMesh in uiModel.meshes {
                        print("🎨 Drawing UI mesh: vertices=\(uiMesh.vertexCount), indices=\(uiMesh.indexCount)")
                        print("    - vertexOffset=\(uiMesh.vertexOffset), indexOffset=\(uiMesh.indexOffset)")
                        
                        // Draw this UI element using cached offsets (no new allocations!)
                        vkCmdDrawIndexed(
                            commandBuffer!,
                            UInt32(uiMesh.indexCount),
                            1,
                            UInt32(uiMesh.indexOffset),
                            Int32(uiMesh.vertexOffset),
                            0
                        )
                    }
                }
                print("✅ Rendered \(uiModels.count) UI models from cached 2D buffer data (zero allocations)")
            }
        }
    }

    func bindVertexBuffer(_ buffer: VkBuffer, offset: VkDeviceSize = 0) {
        let buffers: [VkBuffer?] = [buffer]
        let offsets = [offset]
        buffers.withUnsafeBufferPointer { buffersPtr in
            offsets.withUnsafeBufferPointer { offsetsPtr in
                vkCmdBindVertexBuffers(commandBuffer, 0, 1, buffersPtr.baseAddress, offsetsPtr.baseAddress)
            }
        }
    }

    func bindIndexBuffer(_ buffer: VkBuffer, offset: VkDeviceSize = 0) {
        vkCmdBindIndexBuffer(commandBuffer, buffer, offset, VK_INDEX_TYPE_UINT32)
    }

    func drawIndexed(indexCount: UInt32, instanceCount: UInt32 = 1, firstIndex: UInt32 = 0, vertexOffset: Int32 = 0, firstInstance: UInt32 = 0)  {
        vkCmdDrawIndexed(commandBuffer, indexCount, instanceCount, firstIndex, vertexOffset, firstInstance)
    }

    // MARK: - UI Batching System
    
    /// Add UI element to batch for efficient rendering
    func batchUIQuad(vertices: [Vertex2D], indices: [UInt32], color: Color, textureID: UInt32?) {
        // Adjust indices to account for existing vertices in batch
        let indexOffset = UInt32(batchedUIVertices.count)
        let adjustedIndices = indices.map { $0 + indexOffset }
        
        // Add to batched arrays
        batchedUIVertices.append(contentsOf: vertices)
        batchedUIIndices.append(contentsOf: adjustedIndices)
        uiBatchCount += 1
        
        // Debug: print("🔢 Batched UI quad \(uiBatchCount): \(vertices.count) vertices, \(indices.count) indices")
    }
    
    /// Render all batched UI elements in one efficient draw call
    func flushUIBatch() {
        guard !batchedUIVertices.isEmpty else { 
            print("📦 No UI elements to flush")
            return 
        }
        
        print("🚀 Flushing UI batch: \(uiBatchCount) elements, \(batchedUIVertices.count) vertices, \(batchedUIIndices.count) indices")
        
        // Use VulkanResourceManager to allocate and render 2D data
        do {
            // Allocate vertices and indices using existing methods
            guard let resourceManager = resourceManager else {
                print("❌ No resource manager available")
                return
            }
            
            let vertexRegion = try resourceManager.allocate2DVertices(vertices: batchedUIVertices)
            let indexRegion = try resourceManager.allocate2DIndices(indices: batchedUIIndices)
            
            let vertexOffset = VkDeviceSize(vertexRegion.offset)
            let indexOffset = VkDeviceSize(indexRegion.offset)
            
            // Bind 2D buffers and draw
            resourceManager.withVertex2DBuffer { vertexBuffer in
                resourceManager.withIndex2DBuffer { indexBuffer in
                    // Bind buffers with proper offsets
                    vkCmdBindVertexBuffers(commandBuffer, 0, 1, withUnsafePointer(to: vertexBuffer.bufferHandle.asVulkanBuffer()) { $0 }, withUnsafePointer(to: vertexOffset) { $0 })
                    vkCmdBindIndexBuffer(commandBuffer, indexBuffer.bufferHandle.asVulkanBuffer(), indexOffset, VK_INDEX_TYPE_UINT32)
                    
                    // Single draw call for all UI elements
                    vkCmdDrawIndexed(commandBuffer, UInt32(batchedUIIndices.count), 1, 0, 0, 0)
                    
                    print("✅ UI batch rendered in single draw call!")
                }
            }
        } catch {
            print("❌ Error flushing UI batch: \(error)")
        }
        
        // Clear batch for next frame
        clearUIBatch()
    }
    
    /// Clear batched UI data
    func clearUIBatch() {
        batchedUIVertices.removeAll(keepingCapacity: true)
        batchedUIIndices.removeAll(keepingCapacity: true)
        uiBatchCount = 0
    }

    /// Render UI elements from already-uploaded buffer data (NO memory allocation)
    /// This is the CLEAN rendering method that uses cached GPU data
    func renderUploadedUIElements(_ elements: [UIRenderable]) {
        guard !elements.isEmpty else { 
            print("📦 No uploaded UI elements to render")
            return 
        }
        
        // Only render elements that have been successfully uploaded
        let uploadedElements = elements.filter { $0.isUploaded }
        guard !uploadedElements.isEmpty else {
            print("⚠️ No uploaded UI elements found - call uploadUIElements first")
            return
        }
        
        print("🎨 Rendering \(uploadedElements.count) uploaded UI elements from cache")
        
        guard let resourceManager = resourceManager else {
            print("❌ No resource manager available")
            return
        }
        
        // Render each uploaded element using its cached buffer offsets
        resourceManager.withVertex2DBuffer { vertexBuffer in
            resourceManager.withIndex2DBuffer { indexBuffer in
                for element in uploadedElements {
                    // Use cached offsets (no new allocations!)
                    let vertexOffset = VkDeviceSize(element.vertexOffset * MemoryLayout<Vertex2D>.stride)
                    let indexOffset = VkDeviceSize(element.indexOffset * MemoryLayout<UInt32>.stride)
                    
                    // Bind buffers with cached offsets
                    vkCmdBindVertexBuffers(commandBuffer, 0, 1, 
                                         withUnsafePointer(to: vertexBuffer.bufferHandle.asVulkanBuffer()) { $0 }, 
                                         withUnsafePointer(to: vertexOffset) { $0 })
                    vkCmdBindIndexBuffer(commandBuffer, indexBuffer.bufferHandle.asVulkanBuffer(), 
                                       indexOffset, VK_INDEX_TYPE_UINT32)
                    
                    // Draw this element using its uploaded data
                    vkCmdDrawIndexed(commandBuffer, UInt32(element.indices.count), 1, 0, 0, 0)
                }
                print("✅ Rendered \(uploadedElements.count) UI elements from cached data (zero allocations)")
            }
        }
    }

    func drawUIQuad(vertices: [Vertex2D], indices: [UInt32], color: Color, textureID: UInt32?) {
        // DEPRECATED: Use flushUIBatch() instead for better performance
        // This method is kept for compatibility but should not be used
        print("⚠️ WARNING: drawUIQuad is deprecated - use batching system instead!")
        
        // Fallback to batching system for consistency
        batchUIQuad(vertices: vertices, indices: indices, color: color, textureID: textureID)
    }

    //MARK: Raw pipeline creation (called by VulkanPipelineImpl)
    func createGraphicsPipeline(
        vertexShaderPath: String,
        fragmentShaderPath: String, 
        vertexInputType: String,
        descriptorSetLayouts: [VkDescriptorSetLayout?],
        cullMode: VkCullModeFlags,
        depthTest: Bool,
        blendMode: String
    ) -> (VkPipeline?, VkPipelineLayout?) {
        
        // Load shaders
        guard let assetsPath = getAssetsPath() else {
            print("Failed to get assets path")
            return (nil, nil)
        }
        
        let vertShaderFullPath = "\(assetsPath)/Shaders/\(vertexShaderPath)"
        let fragShaderFullPath = "\(assetsPath)/Shaders/\(fragmentShaderPath)"
        
        guard var vertShaderCode = try? readFile(filename: vertShaderFullPath),
              var fragShaderCode = try? readFile(filename: fragShaderFullPath) else {
            print("Failed to load shaders: \(vertShaderFullPath), \(fragShaderFullPath)")
            return (nil, nil)
        }
        
        // Create shader modules
        let vertShaderModule = createShaderModule(code: &vertShaderCode)
        let fragShaderModule = createShaderModule(code: &fragShaderCode)
        
        defer {
            if let vertModule = vertShaderModule {
                vkDestroyShaderModule(logicalDevice, vertModule, nil)
            }
            if let fragModule = fragShaderModule {
                vkDestroyShaderModule(logicalDevice, fragModule, nil)
            }
        }
        
        guard let vertModule = vertShaderModule,
              let fragModule = fragShaderModule else {
            print("Failed to create shader modules")
            return (nil, nil)
        }
        
        // Create shader stages
        var vertShaderStageInfo = VkPipelineShaderStageCreateInfo()
        vertShaderStageInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
        vertShaderStageInfo.stage = VK_SHADER_STAGE_VERTEX_BIT
        vertShaderStageInfo.module = vertModule
        vertShaderStageInfo.pName = UnsafePointer(shaderEntryPointName)
        
        var fragShaderStageInfo = VkPipelineShaderStageCreateInfo()
        fragShaderStageInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
        fragShaderStageInfo.stage = VK_SHADER_STAGE_FRAGMENT_BIT
        fragShaderStageInfo.module = fragModule
        fragShaderStageInfo.pName = UnsafePointer(shaderEntryPointName)
        
        let shaderStages = [vertShaderStageInfo, fragShaderStageInfo]
        
        // Vertex input based on vertexInputType
        var vertexInputInfo = VkPipelineVertexInputStateCreateInfo()
        vertexInputInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
        
        var bindingDescriptions: [VkVertexInputBindingDescription] = []
        var attributeDescriptions: [VkVertexInputAttributeDescription] = []
        
        switch vertexInputType {
        case "Vertex3D":
            // 3D vertex: position(12) + padding(4) + normal(12) + padding(4) + texcoord(8) + padding(8) = 48 bytes (aligned)
            bindingDescriptions = [
                VkVertexInputBindingDescription(
                    binding: 0,
                    stride: 48,  // Fixed: actual stride is 48, not 32!
                    inputRate: VK_VERTEX_INPUT_RATE_VERTEX
                )
            ]
            attributeDescriptions = [
                // Position at location 0
                VkVertexInputAttributeDescription(
                    location: 0,
                    binding: 0,
                    format: VK_FORMAT_R32G32B32_SFLOAT,
                    offset: 0
                ),
                // Normal at location 1
                VkVertexInputAttributeDescription(
                    location: 1,
                    binding: 0,
                    format: VK_FORMAT_R32G32B32_SFLOAT,
                    offset: 16  // Fixed: actual offset is 16, not 12!
                ),
                // TexCoord at location 2
                VkVertexInputAttributeDescription(
                    location: 2,
                    binding: 0,
                    format: VK_FORMAT_R32G32_SFLOAT,
                    offset: 32  // Fixed: actual offset is 32, not 24!
                )
            ]
        case "Vertex2D":
            // 2D vertex: position(8) + texcoord(8) + color(16) + padding(16) = 48 bytes (aligned)
            bindingDescriptions = [
                VkVertexInputBindingDescription(
                    binding: 0,
                    stride: 48,  // Fixed: actual runtime stride is 48 bytes
                    inputRate: VK_VERTEX_INPUT_RATE_VERTEX
                )
            ]
            attributeDescriptions = [
                // Position at location 0
                VkVertexInputAttributeDescription(
                    location: 0,
                    binding: 0,
                    format: VK_FORMAT_R32G32_SFLOAT,
                    offset: 0
                ),
                // TexCoord at location 1
                VkVertexInputAttributeDescription(
                    location: 1,
                    binding: 0,
                    format: VK_FORMAT_R32G32_SFLOAT,
                    offset: 8
                ),
                // Color at location 2 - matches UI shader expectation!
                VkVertexInputAttributeDescription(
                    location: 2,
                    binding: 0,
                    format: VK_FORMAT_R32G32B32A32_SFLOAT,
                    offset: 16
                )
            ]
        default:
            // Fallback to no vertex input
            break
        }
        
        vertexInputInfo.vertexBindingDescriptionCount = UInt32(bindingDescriptions.count)
        vertexInputInfo.vertexAttributeDescriptionCount = UInt32(attributeDescriptions.count)
        
        if bindingDescriptions.isEmpty {
            vertexInputInfo.pVertexBindingDescriptions = nil
        } else {
            bindingDescriptions.withUnsafeBufferPointer { ptr in
                vertexInputInfo.pVertexBindingDescriptions = ptr.baseAddress
            }
        }
        
        if attributeDescriptions.isEmpty {
            vertexInputInfo.pVertexAttributeDescriptions = nil
        } else {
            attributeDescriptions.withUnsafeBufferPointer { ptr in
                vertexInputInfo.pVertexAttributeDescriptions = ptr.baseAddress
            }
        }
        
        // Input assembly
        var inputAssembly = VkPipelineInputAssemblyStateCreateInfo()
        inputAssembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
        inputAssembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
        inputAssembly.primitiveRestartEnable = VK_FALSE
        
        // Viewport and scissor (dynamic)
        var viewportState = VkPipelineViewportStateCreateInfo()
        viewportState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO
        viewportState.viewportCount = 1
        viewportState.scissorCount = 1
        
        // Rasterizer
        var rasterizer = VkPipelineRasterizationStateCreateInfo()
        rasterizer.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO
        rasterizer.depthClampEnable = VK_FALSE
        rasterizer.rasterizerDiscardEnable = VK_FALSE
        rasterizer.polygonMode = VK_POLYGON_MODE_FILL
        rasterizer.lineWidth = 1.0
        rasterizer.cullMode = cullMode
        rasterizer.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE
        rasterizer.depthBiasEnable = VK_FALSE
        
        // Multisampling
        var multisampling = VkPipelineMultisampleStateCreateInfo()
        multisampling.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
        multisampling.sampleShadingEnable = VK_FALSE
        multisampling.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT
        
        // Depth stencil
        var depthStencil = VkPipelineDepthStencilStateCreateInfo()
        depthStencil.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
        depthStencil.depthTestEnable = depthTest ? VK_TRUE : VK_FALSE
        depthStencil.depthWriteEnable = depthTest ? VK_TRUE : VK_FALSE
        depthStencil.depthCompareOp = VK_COMPARE_OP_LESS
        depthStencil.depthBoundsTestEnable = VK_FALSE
        depthStencil.stencilTestEnable = VK_FALSE
        
        // Color blending
        var colorBlendAttachment = VkPipelineColorBlendAttachmentState()
        colorBlendAttachment.colorWriteMask = UInt32(VK_COLOR_COMPONENT_R_BIT.rawValue | 
                                                     VK_COLOR_COMPONENT_G_BIT.rawValue | 
                                                     VK_COLOR_COMPONENT_B_BIT.rawValue | 
                                                     VK_COLOR_COMPONENT_A_BIT.rawValue)
        
        // Set blend mode based on parameter
        if blendMode.lowercased() == "alpha" {
            colorBlendAttachment.blendEnable = VK_TRUE
            colorBlendAttachment.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA
            colorBlendAttachment.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
            colorBlendAttachment.colorBlendOp = VK_BLEND_OP_ADD
            colorBlendAttachment.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE
            colorBlendAttachment.dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO
            colorBlendAttachment.alphaBlendOp = VK_BLEND_OP_ADD
        } else {
            colorBlendAttachment.blendEnable = VK_FALSE
        }
        
        var colorBlending = VkPipelineColorBlendStateCreateInfo()
        colorBlending.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
        colorBlending.logicOpEnable = VK_FALSE
        colorBlending.attachmentCount = 1
        withUnsafePointer(to: &colorBlendAttachment) { colorBlending.pAttachments = $0 }
        
        // Dynamic state
        let dynamicStates = [VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR]
        var dynamicState = VkPipelineDynamicStateCreateInfo()
        dynamicState.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO
        dynamicState.dynamicStateCount = UInt32(dynamicStates.count)
        dynamicStates.withUnsafeBufferPointer { dynamicState.pDynamicStates = $0.baseAddress }
        
        // Pipeline layout
        var pipelineLayoutInfo = VkPipelineLayoutCreateInfo()
        pipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
        
        // Filter out nil descriptor set layouts
        let validLayouts = descriptorSetLayouts.compactMap { $0 }
        pipelineLayoutInfo.setLayoutCount = UInt32(validLayouts.count)
        if !validLayouts.isEmpty {
            validLayouts.withUnsafeBufferPointer { layoutPtr in
                pipelineLayoutInfo.pSetLayouts = layoutPtr.baseAddress?.withMemoryRebound(to: VkDescriptorSetLayout?.self, capacity: validLayouts.count) { $0 }
            }
        }
        
        var pipelineLayout: VkPipelineLayout? = nil
        let layoutResult = vkCreatePipelineLayout(logicalDevice, &pipelineLayoutInfo, nil, &pipelineLayout)
        if layoutResult != VK_SUCCESS {
            print("Failed to create pipeline layout!")
            return (nil, nil)
        }
        
        // Create graphics pipeline
        var pipelineInfo = VkGraphicsPipelineCreateInfo()
        pipelineInfo.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO
        pipelineInfo.stageCount = UInt32(shaderStages.count)
        shaderStages.withUnsafeBufferPointer { stagePtr in
            pipelineInfo.pStages = stagePtr.baseAddress
        }
        pipelineInfo.pVertexInputState = withUnsafePointer(to: &vertexInputInfo) { $0 }
        pipelineInfo.pInputAssemblyState = withUnsafePointer(to: &inputAssembly) { $0 }
        pipelineInfo.pViewportState = withUnsafePointer(to: &viewportState) { $0 }
        pipelineInfo.pRasterizationState = withUnsafePointer(to: &rasterizer) { $0 }
        pipelineInfo.pMultisampleState = withUnsafePointer(to: &multisampling) { $0 }
        pipelineInfo.pDepthStencilState = withUnsafePointer(to: &depthStencil) { $0 }
        pipelineInfo.pColorBlendState = withUnsafePointer(to: &colorBlending) { $0 }
        pipelineInfo.pDynamicState = withUnsafePointer(to: &dynamicState) { $0 }
        pipelineInfo.layout = pipelineLayout!
        pipelineInfo.renderPass = renderPass!
        pipelineInfo.subpass = 0
        
        var pipeline: VkPipeline? = nil
        let pipelineResult = vkCreateGraphicsPipelines(logicalDevice, nil, 1, &pipelineInfo, nil, &pipeline)
        if pipelineResult != VK_SUCCESS {
            print("Failed to create graphics pipeline!")
            if let layout = pipelineLayout {
                vkDestroyPipelineLayout(logicalDevice, layout, nil)
            }
            return (nil, nil)
        }
        
        print("Successfully created low-level Vulkan graphics pipeline")
        return (pipeline, pipelineLayout)
    }

    func waitIdle() {
        //have to wait for logicalDevice to be idle before destroying everything!
        vkDeviceWaitIdle(logicalDevice)
    }

    
    // Create Vulkan textures from loaded texture data in ResourceManager
    public func createTexturesFromResourceManager() {
        guard let resourceManager = resourceManager else {
            print("No resource manager available for texture creation")
            return
        }
        
        guard let textureManager = textureManager else {
            print("No texture manager available for texture creation")
            return
        }
        
        // Get all textures from resource manager
        let textureCount = resourceManager.getTextureCount()
        print("Creating \(textureCount) Vulkan textures from resource manager")
        
        for textureId in 0..<textureCount {
            let result = resourceManager.withTexture(id: textureId) { textureData in
                return textureManager.createTexture(from: textureData)
            }
            
            if let vulkanTextureIndex = result, vulkanTextureIndex >= 0 {
                print("Created Vulkan texture \(vulkanTextureIndex) from resource texture \(textureId)")
            } else {
                print("Failed to create Vulkan texture from resource texture \(textureId)")
            }
        }
        
        // Update material descriptor set now that textures are available
        if textureCount > 0 {
            updateMaterialDescriptorSet()
            print("Re-updated material descriptor set with newly loaded textures")
        }
    }

    public func createUITextureRGBA(width: Int, height: Int, pixels: [UInt8], srgb: Bool = true) -> Int? {
        guard let textureManager = textureManager else {
            print("No texture manager available for UI texture creation")
            return nil
        }

        // MSDF/UI atlases should use clamp + non-anisotropic sampling to avoid edge softening.
        let textureIndex = textureManager.createTextureRGBA(width: width, height: height, pixels: pixels, srgb: srgb, preferClampSampler: true)
        if textureIndex < 0 {
            return nil
        }
        return textureIndex
    }

    public func createUITextureR8(width: Int, height: Int, pixels: [UInt8]) -> Int? {
        guard let textureManager = textureManager else {
            print("No texture manager available for UI texture creation")
            return nil
        }

        let textureIndex = textureManager.createTextureR8(width: width, height: height, pixels: pixels)
        if textureIndex < 0 {
            return nil
        }
        return textureIndex
    }

}

func vkResultToString(_ result: VkResult) -> String {
    switch result {
    case VK_SUCCESS: return "Success"
    case VK_NOT_READY: return "Not Ready"
    case VK_TIMEOUT: return "Timeout"
    case VK_EVENT_SET: return "Event Set"
    case VK_EVENT_RESET: return "Event Reset"
    case VK_INCOMPLETE: return "Incomplete"
    case VK_ERROR_OUT_OF_HOST_MEMORY: return "Out of Host Memory"
    case VK_ERROR_OUT_OF_DEVICE_MEMORY: return "Out of Device Memory"
    case VK_ERROR_INITIALIZATION_FAILED: return "Initialization Failed"
    case VK_ERROR_DEVICE_LOST: return "Device Lost"
    case VK_ERROR_MEMORY_MAP_FAILED: return "Memory Map Failed"
    case VK_ERROR_LAYER_NOT_PRESENT: return "Layer Not Present"
    case VK_ERROR_EXTENSION_NOT_PRESENT: return "Extension Not Present"
    case VK_ERROR_FEATURE_NOT_PRESENT: return "Feature Not Present"
    case VK_ERROR_INCOMPATIBLE_DRIVER: return "Incompatible Driver"
    case VK_ERROR_TOO_MANY_OBJECTS: return "Too Many Objects"
    case VK_ERROR_FORMAT_NOT_SUPPORTED: return "Format Not Supported"
    default: return "Unknown Vulkan error (\(result))"
    }
}

// Add aspect ratio getter
extension VulkanRenderer {
    func getAspectRatio() -> Float {
        guard let extent = swapchainExtent else { return 16.0 / 9.0 }  // Default fallback
        return Float(extent.width) / Float(extent.height)
    }
}