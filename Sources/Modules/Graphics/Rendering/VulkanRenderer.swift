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

    //RenderPass
    var renderPass: VkRenderPass? = nil
    var pipelineLayout: VkPipelineLayout? = nil
    var graphicsPipeline: VkPipeline? = nil

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

    //uniform buffer shit
    var frameUBO: VkBuffer? = nil
    var frameUBOMemory: VmaAllocation? = nil
    
    // New separate UBOs
    var transformUBO: VkBuffer? = nil
    var transformUBOMemory: VmaAllocation? = nil
    var materialUBO: VkBuffer? = nil
    var materialUBOMemory: VmaAllocation? = nil
    
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

    // Material uploader for proper material system
    private var materialUploader: VulkanMaterialUploader?
    
    // Main shader instance
    private var mainShader: VulkanShader?


    //Descriptor sets
    var descriptorPool: VkDescriptorPool? = nil
    var frameDescriptorSet: VkDescriptorSet? = nil
    var objectDescriptorSet: VkDescriptorSet? = nil
    var lightDescriptorSet: VkDescriptorSet? = nil
    
    // New separate descriptor sets
    var transformDescriptorSet: VkDescriptorSet? = nil
    var materialDescriptorSet: VkDescriptorSet? = nil
    
    var frameSetLayout: VkDescriptorSetLayout? = nil
    var objectSetLayout: VkDescriptorSetLayout? = nil
    var lightSetLayout: VkDescriptorSetLayout? = nil
    
    // New separate layouts
    var transformSetLayout: VkDescriptorSetLayout? = nil
    var materialSetLayout: VkDescriptorSetLayout? = nil

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
        print("Destroying Vulkan resources...")

        cleanupSwapchain()

        //command pool and buffer shit
        withUnsafePointer(to: &commandBuffer) { ptr in
            vkFreeCommandBuffers(logicalDevice, commandPool, 1, ptr)
        }

        if queueManager!.graphicsQueueFamilyIndex != queueManager!.transferQueueFamilyIndex {
            vkDestroyCommandPool(logicalDevice, transferCommandPool, nil)
        }
        vkDestroyCommandPool(logicalDevice, commandPool, nil)

        //Cleanup vma resources
        materialUploader?.cleanup()
        mainShader?.cleanup()
        textureManager?.cleanup()
        vmaDestroyBuffer(vmaAllocator!, frameUBO, frameUBOMemory)
        vmaDestroyBuffer(vmaAllocator!, objectUBO, objectUBOMemory)
        vmaDestroyBuffer(vmaAllocator!, vertexBuffer, vertexBufferAllocation)
        vmaDestroyBuffer(vmaAllocator!, indexBuffer, indexBufferAllocation)
        vmaDestroyAllocator(vmaAllocator)

        //this also cleans up descriptorSet
        vkDestroyDescriptorPool(logicalDevice, descriptorPool, nil)

        vkDestroyPipeline(logicalDevice, graphicsPipeline, nil)
        vkDestroyPipelineLayout(logicalDevice, pipelineLayout, nil)
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
        createRenderPass()

        //pipeline creation stuff
        createUniformBuffer()
        //createVertexBuffer()
        //createIndexBuffer()
        //now finally create pipeline
        createGraphicsPipeline()

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
        shader.setupMaterialBinding(materialBuffer: materialUBO!)
        
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

        var colorAttachmentRef = VkAttachmentReference()
        colorAttachmentRef.attachment = 0
        colorAttachmentRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL

        var subpass = VkSubpassDescription()
        subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS
        subpass.colorAttachmentCount = 1
        withUnsafePointer(to: &colorAttachmentRef) { pointer in
            subpass.pColorAttachments = pointer
        }
        
        var renderPassInfo = VkRenderPassCreateInfo()
        renderPassInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO
        renderPassInfo.attachmentCount = 1
        withUnsafePointer(to: &colorAttachment) { pointer in
            renderPassInfo.pAttachments = pointer
        }
        renderPassInfo.subpassCount = 1
        withUnsafePointer(to: &subpass) { pointer in
            renderPassInfo.pSubpasses = pointer
        }

        var dependency = VkSubpassDependency()
        dependency.srcSubpass = VK_SUBPASS_EXTERNAL
        dependency.dstSubpass = 0

        dependency.srcStageMask = UInt32(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue)
        dependency.srcAccessMask = 0

        dependency.dstStageMask = UInt32(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue)
        dependency.dstAccessMask = UInt32(VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue)

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

    func createDescriptorSet() {
        // Set 0: Frame data (camera, lighting)
        var frameBindings = VkDescriptorSetLayoutBinding(
            binding: 0,
            descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            descriptorCount: 1,
            stageFlags: UInt32(VK_SHADER_STAGE_VERTEX_BIT.rawValue | VK_SHADER_STAGE_FRAGMENT_BIT.rawValue),
            pImmutableSamplers: nil
        )
    
        // Set 1: Transform data (per model)
        var transformBindings = VkDescriptorSetLayoutBinding(
            binding: 0,
            descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
            descriptorCount: 1,
            stageFlags: UInt32(VK_SHADER_STAGE_VERTEX_BIT.rawValue),
            pImmutableSamplers: nil
        )
    
        // Set 2: Material data (per mesh) 
        let materialBindings = [
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
    
        // Create frame layout
        var frameLayoutInfo = VkDescriptorSetLayoutCreateInfo()
        frameLayoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
        frameLayoutInfo.bindingCount = 1
        withUnsafePointer(to: &frameBindings) { ptr in
            frameLayoutInfo.pBindings = ptr
        }
    
        let frameLayoutResult = vkCreateDescriptorSetLayout(logicalDevice, &frameLayoutInfo, nil, &frameSetLayout)
        if frameLayoutResult != VK_SUCCESS {
            fatalError("failed to create frame descriptor set layout!")
        }
    
        // Create transform layout
        var transformLayoutInfo = VkDescriptorSetLayoutCreateInfo()
        transformLayoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
        transformLayoutInfo.bindingCount = 1
        withUnsafePointer(to: &transformBindings) { ptr in
            transformLayoutInfo.pBindings = ptr
        }
    
        let transformLayoutResult = vkCreateDescriptorSetLayout(logicalDevice, &transformLayoutInfo, nil, &transformSetLayout)
        if transformLayoutResult != VK_SUCCESS {
            fatalError("Failed to create transform descriptor set layout")
        }
    
        // Create material layout
        var materialLayoutInfo = VkDescriptorSetLayoutCreateInfo()
        materialLayoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
        materialLayoutInfo.bindingCount = 2  // Changed from 1 to 2
        materialBindings.withUnsafeBufferPointer { bufferPtr in
            materialLayoutInfo.pBindings = bufferPtr.baseAddress
        }
    
        let materialLayoutResult = vkCreateDescriptorSetLayout(logicalDevice, &materialLayoutInfo, nil, &materialSetLayout)
        if materialLayoutResult != VK_SUCCESS {
            fatalError("Failed to create material descriptor set layout")
        }
    
        // Create descriptor pool
        let poolSizes = DynamicArray<VkDescriptorPoolSize>(
            VkDescriptorPoolSize(type: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, descriptorCount: 1),  // for frame data
            VkDescriptorPoolSize(type: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC, descriptorCount: 1), // for transform data
            VkDescriptorPoolSize(type: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC, descriptorCount: 1), // for material data
            VkDescriptorPoolSize(type: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, descriptorCount: 1) // for texture samplers
        )
    
        var poolInfo = VkDescriptorPoolCreateInfo()
        poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO
        poolInfo.poolSizeCount = 4  // Changed from 3 to 4
        poolInfo.pPoolSizes = poolSizes.getDataAsConstPointer()
        poolInfo.maxSets = 3 // one for each descriptor set layout
    
        vkCreateDescriptorPool(logicalDevice, &poolInfo, nil, &descriptorPool)
    
        // Allocate descriptor sets
        let layouts = DynamicArray<VkDescriptorSetLayout?>(frameSetLayout!, transformSetLayout!, materialSetLayout!)
    
        var allocInfo = VkDescriptorSetAllocateInfo()
        allocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
        allocInfo.descriptorPool = descriptorPool!
        allocInfo.descriptorSetCount = 3
        allocInfo.pSetLayouts = layouts.getDataAsConstPointer()
    
        let sets = DynamicArray<VkDescriptorSet?>(repeating: nil, count: 3)
        vkAllocateDescriptorSets(logicalDevice, &allocInfo, sets.getData())
    
        frameDescriptorSet = sets[0]
        transformDescriptorSet = sets[1]
        materialDescriptorSet = sets[2]
    
        // Update frame descriptor set
        var frameDescriptorWrite = VkWriteDescriptorSet()
        frameDescriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
        frameDescriptorWrite.dstSet = frameDescriptorSet!
        frameDescriptorWrite.dstBinding = 0
        frameDescriptorWrite.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
        frameDescriptorWrite.descriptorCount = 1
    
        var frameBufferInfo = VkDescriptorBufferInfo(
            buffer: frameUBO,
            offset: 0,
            range: VkDeviceSize(MemoryLayout<FrameConstants>.stride)
        )
        withUnsafePointer(to: &frameBufferInfo) { ptr in
            frameDescriptorWrite.pBufferInfo = ptr
        }
    
        vkUpdateDescriptorSets(logicalDevice, 1, &frameDescriptorWrite, 0, nil)
    
        // Update transform descriptor set
        var transformDescriptorWrite = VkWriteDescriptorSet()
        transformDescriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
        transformDescriptorWrite.dstSet = transformDescriptorSet!
        transformDescriptorWrite.dstBinding = 0
        transformDescriptorWrite.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC
        transformDescriptorWrite.descriptorCount = 1
    
        var transformBufferInfo = VkDescriptorBufferInfo(
            buffer: transformUBO,
            offset: 0,
            range: VkDeviceSize(MemoryLayout<TransformConstants>.stride)
        )
        withUnsafePointer(to: &transformBufferInfo) { ptr in
            transformDescriptorWrite.pBufferInfo = ptr
        }
    
        vkUpdateDescriptorSets(logicalDevice, 1, &transformDescriptorWrite, 0, nil)
    
        // Update material descriptor set with both buffer and texture
        var descriptorWrites: [VkWriteDescriptorSet] = []
        
        // Material buffer binding
        var materialDescriptorWrite = VkWriteDescriptorSet()
        materialDescriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
        materialDescriptorWrite.dstSet = materialDescriptorSet!
        materialDescriptorWrite.dstBinding = 0
        materialDescriptorWrite.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC
        materialDescriptorWrite.descriptorCount = 1
    
        let materialBufferInfo = VkDescriptorBufferInfo(
            buffer: materialUBO,
            offset: 0,
            range: VkDeviceSize(MemoryLayout<MaterialConstants>.stride)
        )
        descriptorWrites.append(materialDescriptorWrite)
        
        // Texture sampler binding 
        var textureDescriptorWrite = VkWriteDescriptorSet()
        textureDescriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
        textureDescriptorWrite.dstSet = materialDescriptorSet!
        textureDescriptorWrite.dstBinding = 1
        textureDescriptorWrite.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
        textureDescriptorWrite.descriptorCount = 1
        
        var imageInfo = VkDescriptorImageInfo()
        var hasValidTexture = false
        if let defaultTexture = textureManager?.getDefaultTexture(),
           let imageView = defaultTexture.imageView,
           let sampler = defaultTexture.sampler {
            imageInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
            imageInfo.imageView = imageView
            imageInfo.sampler = sampler
            hasValidTexture = true
            descriptorWrites.append(textureDescriptorWrite)
        } else {
            print("Warning: No default texture available, skipping texture binding")
        }
        
        // Update all descriptors at once
        withUnsafePointer(to: materialBufferInfo) { bufferPtr in
            descriptorWrites[0].pBufferInfo = bufferPtr
            if hasValidTexture {
                withUnsafePointer(to: imageInfo) { imagePtr in
                    descriptorWrites[1].pImageInfo = imagePtr
                    
                    descriptorWrites.withUnsafeBufferPointer { writes in
                        vkUpdateDescriptorSets(logicalDevice, UInt32(writes.count), writes.baseAddress, 0, nil)
                    }
                }
            } else {
                // Update only the buffer descriptor
                vkUpdateDescriptorSets(logicalDevice, 1, &descriptorWrites[0], 0, nil)
            }
        }
    }

    func createGraphicsPipeline() {
        guard let assetsPath = getAssetsPath() else {
            fatalError("Cant get assets path!")
        }

        let vertShaderPath: String = "\(assetsPath)/Shaders/vert.spv"
        let fragShaderPath: String = "\(assetsPath)/Shaders/frag.spv"

        print("vertShaderPath is: \(vertShaderPath)")

        var vertShaderCode = try? readFile(filename: vertShaderPath)
        var fragShaderCode = try? readFile(filename: fragShaderPath)

        //Make sure both of these are getting created successfully
        let vertShaderModule = createShaderModule(code: &vertShaderCode!)
        let fragShaderModule = createShaderModule(code: &fragShaderCode!)
        defer {
            vkDestroyShaderModule(logicalDevice, vertShaderModule, nil)
            vkDestroyShaderModule(logicalDevice, fragShaderModule, nil)
        }
        
        var vertShaderStageInfo = VkPipelineShaderStageCreateInfo()
        vertShaderStageInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
        vertShaderStageInfo.stage = VK_SHADER_STAGE_VERTEX_BIT
        vertShaderStageInfo.module = vertShaderModule
        vertShaderStageInfo.pName = UnsafePointer(shaderEntryPointName)

        var fragShaderStageInfo = VkPipelineShaderStageCreateInfo()
        fragShaderStageInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
        fragShaderStageInfo.stage = VK_SHADER_STAGE_FRAGMENT_BIT
        fragShaderStageInfo.module = fragShaderModule
        fragShaderStageInfo.pName = UnsafePointer(shaderEntryPointName)

        var shaderStages = DynamicArray<VkPipelineShaderStageCreateInfo>(
            vertShaderStageInfo, fragShaderStageInfo
        )

        let dynamicStates = DynamicArray<VkDynamicState>(
            VK_DYNAMIC_STATE_VIEWPORT,
            VK_DYNAMIC_STATE_SCISSOR
        )

        var dynamicStateInfo = VkPipelineDynamicStateCreateInfo()
        dynamicStateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO
        dynamicStateInfo.dynamicStateCount = UInt32(dynamicStates.getLength())
        dynamicStateInfo.pDynamicStates = dynamicStates.getDataAsConstPointer()

        var vertexInputInfo = VkPipelineVertexInputStateCreateInfo()
        vertexInputInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
        
        //use vertex3d for binding and attributes
        var bindingDescription = Vertex3D.getBindingDescription()
        let attributeDescriptions = Vertex3D.getAttributeDescriptions()

        vertexInputInfo.vertexBindingDescriptionCount = 1
        vertexInputInfo.vertexAttributeDescriptionCount = UInt32(attributeDescriptions.getLength())
        withUnsafePointer(to: &bindingDescription) { pointer in
            vertexInputInfo.pVertexBindingDescriptions = pointer
        }
        vertexInputInfo.pVertexAttributeDescriptions = attributeDescriptions.getDataAsConstPointer()

        var inputAssemblyInfo = VkPipelineInputAssemblyStateCreateInfo()
        inputAssemblyInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
        inputAssemblyInfo.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
        inputAssemblyInfo.primitiveRestartEnable = VK_FALSE

        var viewport = VkViewport()
        viewport.x = 0.0
        viewport.y = 0.0
        guard let swapchainExtent = swapchainExtent else { fatalError("Error in createGraphicsPipeline, swapchainExtent is nil") }
        viewport.width = Float(swapchainExtent.width)
        viewport.height = Float(swapchainExtent.height)
        viewport.minDepth = 0.0
        viewport.maxDepth = 1.0

        var scissor = VkRect2D()
        scissor.offset = VkOffset2D(x: 0, y: 0)
        scissor.extent = swapchainExtent

        var viewportStateInfo = VkPipelineViewportStateCreateInfo()
        viewportStateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO
        viewportStateInfo.viewportCount = 1
        withUnsafePointer(to: &viewport) { pointer in
            viewportStateInfo.pViewports = pointer
        }

        viewportStateInfo.scissorCount = 1
        withUnsafePointer(to: &scissor) { pointer in
            viewportStateInfo.pScissors = pointer
        }

        var rasterizerInfo = VkPipelineRasterizationStateCreateInfo()
        rasterizerInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO
        rasterizerInfo.depthClampEnable = VK_FALSE
        rasterizerInfo.rasterizerDiscardEnable = VK_FALSE
        rasterizerInfo.polygonMode = VK_POLYGON_MODE_FILL
        rasterizerInfo.lineWidth = 1.0
        rasterizerInfo.cullMode = UInt32(VK_CULL_MODE_BACK_BIT.rawValue)  // Enable back-face culling
        rasterizerInfo.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE  // glTF standard
        rasterizerInfo.depthBiasEnable = VK_FALSE

        var multisamplingInfo = VkPipelineMultisampleStateCreateInfo()
        multisamplingInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
        multisamplingInfo.sampleShadingEnable = VK_FALSE
        multisamplingInfo.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT

        var colorBlendAttachmentInfo = VkPipelineColorBlendAttachmentState()
        colorBlendAttachmentInfo.colorWriteMask = UInt32(VK_COLOR_COMPONENT_R_BIT.rawValue) | UInt32(VK_COLOR_COMPONENT_G_BIT.rawValue)
            | UInt32(VK_COLOR_COMPONENT_B_BIT.rawValue) | UInt32(VK_COLOR_COMPONENT_A_BIT.rawValue)
        colorBlendAttachmentInfo.blendEnable = VK_FALSE
        colorBlendAttachmentInfo.srcColorBlendFactor = VK_BLEND_FACTOR_ONE
        colorBlendAttachmentInfo.dstColorBlendFactor = VK_BLEND_FACTOR_ZERO
        colorBlendAttachmentInfo.colorBlendOp = VK_BLEND_OP_ADD
        colorBlendAttachmentInfo.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE
        colorBlendAttachmentInfo.dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO
        colorBlendAttachmentInfo.alphaBlendOp = VK_BLEND_OP_ADD

        var colorBlending = VkPipelineColorBlendStateCreateInfo()
        colorBlending.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
        colorBlending.logicOpEnable = VK_FALSE
        colorBlending.attachmentCount = 1
        withUnsafePointer(to: &colorBlendAttachmentInfo) { pointer in
            colorBlending.pAttachments = pointer
        }
        
        colorBlending.blendConstants.0 = 0.0
        colorBlending.blendConstants.1 = 0.0
        colorBlending.blendConstants.2 = 0.0
        colorBlending.blendConstants.3 = 0.0

        //add depth stencil state
        var depthStencilInfo = VkPipelineDepthStencilStateCreateInfo()
        depthStencilInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
        depthStencilInfo.depthTestEnable = VK_TRUE
        depthStencilInfo.depthWriteEnable = VK_TRUE
        depthStencilInfo.depthCompareOp = VK_COMPARE_OP_LESS

        //Create descriptor set and layout
        createDescriptorSet()

        let setLayouts = DynamicArray<VkDescriptorSetLayout?>(frameSetLayout!, transformSetLayout!, materialSetLayout!)

        var pipelineLayoutInfo = VkPipelineLayoutCreateInfo()
        pipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
        pipelineLayoutInfo.setLayoutCount = UInt32(setLayouts.getLength())
        pipelineLayoutInfo.pSetLayouts = setLayouts.getDataAsConstPointer()

        let result = vkCreatePipelineLayout(logicalDevice, &pipelineLayoutInfo, nil, &pipelineLayout)
        if result != VK_SUCCESS {
            fatalError("failed to create pipeline layout!")
        }

        var pipelineInfo = VkGraphicsPipelineCreateInfo()
        pipelineInfo.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO
        pipelineInfo.stageCount = 2
        pipelineInfo.pStages = shaderStages.getDataAsConstPointer()

        //fixed-function stage
        withUnsafePointer(to: &vertexInputInfo) { pointer in
            pipelineInfo.pVertexInputState = pointer
        }
        withUnsafePointer(to: &inputAssemblyInfo) { pointer in
            pipelineInfo.pInputAssemblyState = pointer
        }
        withUnsafePointer(to: &viewportStateInfo) { pointer in
            pipelineInfo.pViewportState = pointer
        }
        withUnsafePointer(to: &rasterizerInfo) { pointer in
            pipelineInfo.pRasterizationState = pointer
        }
        withUnsafePointer(to: &multisamplingInfo) { pointer in
            pipelineInfo.pMultisampleState = pointer
        }

        //depth stencil info
        withUnsafePointer(to: &depthStencilInfo) { pointer in
            pipelineInfo.pDepthStencilState = pointer //enable depth testing
        }

        withUnsafePointer(to: &colorBlending) { pointer in
            pipelineInfo.pColorBlendState = pointer
        }
        withUnsafePointer(to: &dynamicStateInfo) { pointer in
            pipelineInfo.pDynamicState = pointer
        }
        
        //Pipeline layout
        pipelineInfo.layout = pipelineLayout

        //render pass
        pipelineInfo.renderPass = renderPass
        pipelineInfo.subpass = 0

        pipelineInfo.basePipelineHandle = nil
        pipelineInfo.basePipelineIndex = -1

        let createPipelineResult = vkCreateGraphicsPipelines(logicalDevice, nil, 1, &pipelineInfo, nil, &graphicsPipeline)
        if createPipelineResult != VK_SUCCESS {
            fatalError("Failed to create graphics pipeline!")
        }

        print("Graphics pipeline created successfully!")
    }

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
            var attachments = swapchainImageViews?[i]

            var frameBufferInfo = VkFramebufferCreateInfo()
            frameBufferInfo.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO
            frameBufferInfo.renderPass = renderPass
            frameBufferInfo.attachmentCount = 1
            withUnsafePointer(to: &attachments) { pointer in
                frameBufferInfo.pAttachments = pointer
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

        // Material constants (per mesh)
        let materialUBOSize = VkDeviceSize(MemoryLayout<MaterialConstants>.stride * MAX_MATERIALS)
        createBuffer(
            size: materialUBOSize,
            usage: UInt32(VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT.rawValue),
            properties: UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue) |
                        UInt32(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue),
            isDynamic: true,
            buffer: &materialUBO,
            bufferAllocation: &materialUBOMemory
        )
    }

    //helper function for loading model data
    func uploadModelData(vertices: inout DynamicArray<Vertex3D>, indices: inout DynamicArray<UInt32>) {
        
    }

    private func findMemoryType(typeFilter: UInt32, properties: VkMemoryPropertyFlags) -> UInt32 {
        var memProperties = VkPhysicalDeviceMemoryProperties()
        vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memProperties)

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
        let materialRawSize: VkDeviceSize = VkDeviceSize(MemoryLayout<MaterialConstants>.size)
        materialAlignment = (materialRawSize + minAlignment - 1) & ~(minAlignment - 1)

        print("Transform UBO entry uses \(transformAlignment) bytes")
        print("Material UBO entry uses \(materialAlignment) bytes")
    }

    private var transformDebugCounter = 0
    
    func updateTransformUBO(at offset: Int, transform: Transform) {
        var constants = TransformConstants(
            modelMatrix: transform.modelMatrix,
            normalMatrix: transform.normalMatrix
        )
        
        // Debug: Print the model matrix being sent to the shader
        transformDebugCounter += 1
        if transformDebugCounter <= 3 {  // Only print first few transforms
            print("DEBUG: Transform \(transformDebugCounter) model matrix:")
            print("  Position: \(transform.position)")
            print("  Rotation: \(transform.rotation)")
            print("  Scale: \(transform.scale)")
            print("  Model matrix: \(transform.modelMatrix)")
        }

        var dataPtr: UnsafeMutableRawPointer?
        let result = vmaMapMemory(vmaAllocator!, transformUBOMemory!, &dataPtr)
        if result != VK_SUCCESS {
            fatalError("Failed to map transform UBO memory!")
        }

        let destPtr = dataPtr!.advanced(by: offset)
        memcpy(destPtr, &constants, MemoryLayout<TransformConstants>.size)

        vmaUnmapMemory(vmaAllocator!, transformUBOMemory!)
    }

    func updateMaterialUBO(at offset: Int, material: Material) {
        guard let materialUploader = materialUploader else {
            fatalError("Material uploader not initialized!")
        }
        
        // Use VulkanMaterialUploader to convert Material to MaterialData
        materialUploader.update(from: material)
        
        // Get the MaterialData from the uploader and convert to MaterialConstants format
        // For now, we'll extract the key values and put them into MaterialConstants
        var constants = MaterialConstants(
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
        
        print("DEBUG: Uploading material at offset \(offset) with baseColor: \(constants.baseColor), metallic: \(constants.metallicFactor), roughness: \(constants.roughnessFactor)")

        var dataPtr: UnsafeMutableRawPointer?
        let result = vmaMapMemory(vmaAllocator!, materialUBOMemory!, &dataPtr)
        if result != VK_SUCCESS {
            fatalError("Failed to map material UBO memory!")
        }

        let destPtr = dataPtr!.advanced(by: offset)
        memcpy(destPtr, &constants, MemoryLayout<MaterialConstants>.size)

        vmaUnmapMemory(vmaAllocator!, materialUBOMemory!)
    }

    private func calculateViewFrustum(projectionMatrix: Matrix4x4, viewMatrix: Matrix4x4) -> Frustum {
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

        return Frustum(planes: planes)

    }

    private var debugFrameCount = 0
    
    private func updateFrameUBO() {
        // Create frame constants with current camera data
        var frameConstants = FrameConstants(
            viewMatrix: camera.viewMatrix,
            projectionMatrix: camera.projectionMatrix,
            cameraPosition: camera.position,
            time: 0.0, // TODO: Add time tracking if needed
            lightPosition: Vector3(50.0, 50.0, -50.0), // Move light much further away and behind camera
            lightColor: Vector3(2.0, 2.0, 2.0),    // Brighter white light
            ambientColor: Vector3(0.3, 0.3, 0.3)   // Brighter ambient
        )
        
        // Debug: Print camera matrices (only once per few frames to avoid spam)
        debugFrameCount += 1
        if debugFrameCount % 60 == 0 {
            print("Camera position: \(camera.position)")
            print("View matrix: \(camera.viewMatrix)")
            print("Projection matrix: \(camera.projectionMatrix)")
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

    func render(models: [Model]) {
        // Check if resource manager and buffers are available
        guard let resourceManager = resourceManager else {
            return
        }
        
        // Use borrowing to access buffers safely
        guard resourceManager.staticVertexBuffer != nil,
              resourceManager.dynamicVertexBuffer != nil,
              resourceManager.indexBuffer != nil else {
            return
        }

        // Update camera matrices in the frame UBO
        updateFrameUBO()

        //Calculate the view frustum for culling
        let frustum = calculateViewFrustum(projectionMatrix: camera.projectionMatrix, viewMatrix: camera.viewMatrix)

        // Sort models by their first mesh's material ID for better batching
        let sortedModels = models.sorted { 
            ($0.meshes.first?.materialID ?? 0) < ($1.meshes.first?.materialID ?? 0) 
        }

        //for static meshes
        var currentMaterialID: UInt32 = UInt32.max
        var currentTransformIndex: Int = 0
        
        print("DEBUG: Processing \(sortedModels.count) sorted models")
        for (i, model) in sortedModels.enumerated() {
            let isDynamic = model.isDynamic
            let isVisible = model.isVisible(in: frustum)
            print("  Model \(i): isDynamic=\(isDynamic), isVisible=\(isVisible), meshes=\(model.meshes.count)")
            
            if !isDynamic && isVisible {
                print("    -> Model \(i) WILL BE RENDERED")
            } else {
                print("    -> Model \(i) SKIPPED (isDynamic=\(isDynamic), isVisible=\(isVisible))")
            }
        }
        
        for model in sortedModels where !model.isDynamic && model.isVisible(in: frustum) {
            //bind static vertex buffer
            resourceManager.withStaticVertexBuffer { staticBuffer in
                let vertexBuffers = DynamicArray<VkBuffer?>(staticBuffer.bufferHandle.asVulkanBuffer())
                let offsets = DynamicArray<VkDeviceSize>(0)
                vkCmdBindVertexBuffers(commandBuffer, 0, 1, vertexBuffers.getData(), offsets.getData())
            }

            //bind index buffer
            resourceManager.withIndexBuffer { indexBuffer in
                vkCmdBindIndexBuffer(commandBuffer, indexBuffer.bufferHandle.asVulkanBuffer(), 0, VK_INDEX_TYPE_UINT32)
            }

            // Update transform UBO once per model
            let transformOffset = currentTransformIndex * Int(transformAlignment)
            updateTransformUBO(at: transformOffset, transform: model.transform)
            
            // Bind transform descriptor set with dynamic offset
            var transformOffsetValue = UInt32(transformOffset)
            vkCmdBindDescriptorSets(
                commandBuffer,
                VK_PIPELINE_BIND_POINT_GRAPHICS,
                pipelineLayout,
                1, // Set 1: transforms
                1, &transformDescriptorSet,
                1, &transformOffsetValue
            )

            //draw the model - each mesh can have different materials
            for mesh in model.meshes {
                //update material state only if it changed
                if currentMaterialID != mesh.materialID {
                    currentMaterialID = mesh.materialID
                    
                    // Get the actual material from the model
                    let material = model.materials.count > Int(mesh.materialID) ? 
                        model.materials[Int(mesh.materialID)] : 
                        Material() // Fallback to default white material
                    
                    // Update material UBO
                    let materialOffset = Int(mesh.materialID) * Int(materialAlignment)
                    updateMaterialUBO(at: materialOffset, material: material)
                    
                    // Update material shader binding with texture
                    mainShader?.getMaterialBinding()?.update(material: material, textureIndex: material.baseColorTextureIndex, frameIndex: currentFrame)
                    
                    // Bind material descriptor set with texture
                    if let materialSet = mainShader?.getMaterialBinding()?.getDescriptorSet(frameIndex: currentFrame) {
                        var descriptorSet: VkDescriptorSet? = materialSet
                        var materialOffsetValue = UInt32(materialOffset)
                        vkCmdBindDescriptorSets(
                            commandBuffer,
                            VK_PIPELINE_BIND_POINT_GRAPHICS,
                            pipelineLayout,
                            2, // Set 2: materials
                            1, &descriptorSet,
                            1, &materialOffsetValue // Dynamic offset for material UBO
                        )
                    }
                }

                //Draw
                print("DEBUG: Drawing STATIC mesh: indexCount=\(mesh.indexCount), indexOffset=\(mesh.indexOffset), vertexOffset=\(mesh.vertexOffset)")
                vkCmdDrawIndexed(
                    commandBuffer!,
                    UInt32(mesh.indexCount),    // Number of indices
                    1,                          // Instance count
                    UInt32(mesh.indexOffset),   // First index
                    Int32(mesh.vertexOffset),   // Vertex offset
                    0                           // First instance
                )
            }
            
            currentTransformIndex += 1
        }

        //Reset material tracking for dynamic objects
        currentMaterialID = UInt32.max

        //for dynamic meshes
        for model in sortedModels where model.isDynamic && model.isVisible(in: frustum) {
            // bind dynamic vertex buffer
            resourceManager.withDynamicVertexBuffer { dynamicBuffer in
                let vertexBuffers = DynamicArray<VkBuffer?>(dynamicBuffer.bufferHandle.asVulkanBuffer())
                let offsets = DynamicArray<VkDeviceSize>(0)
                vkCmdBindVertexBuffers(commandBuffer!, 0, 1, vertexBuffers.getData(), offsets.getData())
            }

            //bind index buffer (only if needed)
            if !model.meshes.isEmpty {
                resourceManager.withIndexBuffer { indexBuffer in
                    vkCmdBindIndexBuffer(commandBuffer, indexBuffer.bufferHandle.asVulkanBuffer(), 0, VK_INDEX_TYPE_UINT32)
                }
            }

            // Update transform UBO once per model
            let transformOffset = currentTransformIndex * Int(transformAlignment)
            updateTransformUBO(at: transformOffset, transform: model.transform)
            
            // Bind transform descriptor set with dynamic offset
            var transformOffsetValue = UInt32(transformOffset)
            vkCmdBindDescriptorSets(
                commandBuffer,
                VK_PIPELINE_BIND_POINT_GRAPHICS,
                pipelineLayout,
                1, // Set 1: transforms
                1, &transformDescriptorSet,
                1, &transformOffsetValue
            )

            // draw all meshes for this model - each mesh can have different materials
            for mesh in model.meshes {
                //update material state only if it changed
                if currentMaterialID != mesh.materialID {
                    currentMaterialID = mesh.materialID
                    
                    // Get the actual material from the model
                    let material = model.materials.count > Int(mesh.materialID) ? 
                        model.materials[Int(mesh.materialID)] : 
                        Material() // Fallback to default white material
                    
                    // Update material UBO
                    let materialOffset = Int(mesh.materialID) * Int(materialAlignment)
                    updateMaterialUBO(at: materialOffset, material: material)
                    
                    // Update material shader binding with texture
                    mainShader?.getMaterialBinding()?.update(material: material, textureIndex: material.baseColorTextureIndex, frameIndex: currentFrame)
                    
                    // Bind material descriptor set with texture
                    if let materialSet = mainShader?.getMaterialBinding()?.getDescriptorSet(frameIndex: currentFrame) {
                        var descriptorSet: VkDescriptorSet? = materialSet
                        var materialOffsetValue = UInt32(materialOffset)
                        vkCmdBindDescriptorSets(
                            commandBuffer,
                            VK_PIPELINE_BIND_POINT_GRAPHICS,
                            pipelineLayout,
                            2, // Set 2: materials
                            1, &descriptorSet,
                            1, &materialOffsetValue // Dynamic offset for material UBO
                        )
                    }
                }

                //Draw
                let vertexOffsetInVertices = mesh.vertexOffset / MemoryLayout<Vertex3D>.stride
                vkCmdDrawIndexed(
                    commandBuffer!,
                    UInt32(mesh.indexCount),    // Number of indices
                    1,                          // Instance count
                    UInt32(mesh.indexOffset),   // First index
                    Int32(vertexOffsetInVertices), // Vertex offset (in vertices, not bytes)
                    0                           // First instance
                )
            }
            
            currentTransformIndex += 1
        }
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

    internal func synchronize() {

    }

    //DRAWING FUNCTIONS

    func beginFrame() {
        //Vulkan-specific logic to start a frame
    }

    // Frame lifecycle management - called by Graphics class
    func beginFrame() -> UInt32? {
        vkWaitForFences(logicalDevice, 1, &inFlightFences![currentFrame], VK_TRUE, UInt64.max)

        var imageIndex: UInt32 = 0
        let result = vkAcquireNextImageKHR(logicalDevice, swapchain, UInt64.max,
            imageAvailableSemaphores![currentFrame], nil, &imageIndex)

        if result == VK_ERROR_OUT_OF_DATE_KHR {
            recreateSwapchain()
            return nil
        } else if result != VK_SUCCESS && result != VK_SUBOPTIMAL_KHR {
            fatalError("Failed to acquire swapchain image")
        }

        vkResetFences(logicalDevice, 1, &inFlightFences![currentFrame])
        vkResetCommandBuffer(commandBuffer, 0)
        
        // Begin command buffer and render pass
        var beginInfo = VkCommandBufferBeginInfo()
        beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
        vkBeginCommandBuffer(commandBuffer, &beginInfo)

        var renderPassInfo = VkRenderPassBeginInfo()
        renderPassInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
        renderPassInfo.renderPass = renderPass
        renderPassInfo.framebuffer = swapchainFrameBuffers![Int(imageIndex)]
        renderPassInfo.renderArea.offset = VkOffset2D(x: 0, y: 0)
        renderPassInfo.renderArea.extent = swapchainExtent!

        var clearColor = VkClearValue(color: VkClearColorValue(float32: (0.1, 0.2, 0.3, 1.0)))
        renderPassInfo.clearValueCount = 1
        withUnsafePointer(to: &clearColor) { ptr in
            renderPassInfo.pClearValues = ptr
        }

        vkCmdBeginRenderPass(commandBuffer, &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE)
        vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, graphicsPipeline)

        // Set viewport and scissor
        var viewport = VkViewport()
        viewport.x = 0.0
        viewport.y = 0.0
        viewport.width = Float(swapchainExtent!.width)
        viewport.height = Float(swapchainExtent!.height)
        viewport.minDepth = 0.0
        viewport.maxDepth = 1.0
        vkCmdSetViewport(commandBuffer, 0, 1, &viewport)

        var scissor = VkRect2D()
        scissor.offset = VkOffset2D(x: 0, y: 0)
        scissor.extent = swapchainExtent!
        vkCmdSetScissor(commandBuffer, 0, 1, &scissor)

        // Bind frame descriptor set (camera and lighting)
        vkCmdBindDescriptorSets(
            commandBuffer,
            VK_PIPELINE_BIND_POINT_GRAPHICS,
            pipelineLayout,
            0, // Set 0: frame data
            1, &frameDescriptorSet,
            0, nil
        )

        return imageIndex
    }

    func endFrame(imageIndex: UInt32) {
        vkCmdEndRenderPass(commandBuffer)
        vkEndCommandBuffer(commandBuffer)

        // Submit command buffer
        var submitInfo = VkSubmitInfo()
        submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO

        let waitSemaphores = DynamicArray<VkSemaphore?>(imageAvailableSemaphores![currentFrame])
        let waitStages = DynamicArray<VkPipelineStageFlags>(UInt32(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue))
        submitInfo.waitSemaphoreCount = 1
        submitInfo.pWaitSemaphores = waitSemaphores.getDataAsConstPointer()
        submitInfo.pWaitDstStageMask = waitStages.getDataAsConstPointer()
        
        submitInfo.commandBufferCount = 1
        withUnsafePointer(to: &commandBuffer) { ptr in
            submitInfo.pCommandBuffers = ptr
        }
        let signalSemaphores = DynamicArray<VkSemaphore?>(renderFinishedSemaphores![currentFrame])
        submitInfo.signalSemaphoreCount = 1
        submitInfo.pSignalSemaphores = signalSemaphores.getDataAsConstPointer()

        vkQueueSubmit(queueManager!.graphicsQueue, 1, &submitInfo, inFlightFences![currentFrame])

        // Present
        var presentInfo = VkPresentInfoKHR()
        presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR
        presentInfo.waitSemaphoreCount = 1
        presentInfo.pWaitSemaphores = signalSemaphores.getDataAsConstPointer()

        let swapchains = DynamicArray<VkSwapchainKHR?>(swapchain)
        presentInfo.swapchainCount = 1
        presentInfo.pSwapchains = UnsafePointer(swapchains.getData())
        withUnsafePointer(to: imageIndex) { ptr in
            presentInfo.pImageIndices = ptr
        }

        let result = vkQueuePresentKHR(queueManager!.presentQueue, &presentInfo)
        if result == VK_ERROR_OUT_OF_DATE_KHR || result == VK_SUBOPTIMAL_KHR {
            recreateSwapchain()
        } else if result != VK_SUCCESS {
            fatalError("failed to present swapchain image!")
        }

        currentFrame = (currentFrame + 1) % MAX_FRAMES_IN_FLIGHT
    }

    func endFrame() {
        //Vulkan-specific logic to end a frame
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