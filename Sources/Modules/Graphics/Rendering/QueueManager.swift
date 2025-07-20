import Cvulkan

class QueueManager {
    public var graphicsQueue: VkQueue?
    public var presentQueue: VkQueue?
    public var transferQueue: VkQueue?
    public var computeQueue: VkQueue?

    public var graphicsQueueFamilyIndex: UInt32?
    public var presentQueueFamilyIndex: UInt32?
    public var transferQueueFamilyIndex: UInt32?
    public var computeQueueFamilyIndex: UInt32?
    private var uniqueQueueFamilyIndices: Set<UInt32>?

    private var preferSeperateGraphicsQueue: Bool = false

    private var queueFamilyCount = 4

    init(physicalDevice: VkPhysicalDevice, vulkanSurface: VkSurfaceKHR, preferSeperateGraphicsQueue: Bool) {
        self.preferSeperateGraphicsQueue = preferSeperateGraphicsQueue
        //initialize all queues and their family indices
        findSuitableQueueFamilies(physDevice: physicalDevice, vkSurface: vulkanSurface)
    }

    /*public func enableSeperateGraphicsQueue(_ enabled: Bool) {
        self.preferSeperateGraphicsQueue = enabled
    }*/

    //PREFERS A COMBINED GRAPHICS+PRESENTATION QUEUE, MIGHT CHANGE LATER TO DEDICATED FOR BOTH
    private func findSuitableQueueFamilies(physDevice: VkPhysicalDevice, vkSurface: VkSurfaceKHR) {
        var queueFamilyCount: UInt32 = 0
        vkGetPhysicalDeviceQueueFamilyProperties(physDevice, &queueFamilyCount, nil)

        let queueFamilies = DynamicArray<VkQueueFamilyProperties>(repeating: VkQueueFamilyProperties(), count: queueFamilyCount)
        vkGetPhysicalDeviceQueueFamilyProperties(physDevice, &queueFamilyCount, queueFamilies.getData())

        var bestGraphicsFamily: UInt32? = nil
        var bestPresentFamily: UInt32? = nil
        var bestTransferFamily: UInt32? = nil
        var bestComputeFamily: UInt32? = nil
    
        for i in 0..<queueFamilies.getLength() {
            let queueFamily = queueFamilies[i]

            //If it supports all 3 then it is likely the main rasterizer & synchronous compute queue
            let supportsGraphics = (queueFamily.queueFlags & UInt32(VK_QUEUE_GRAPHICS_BIT.rawValue)) != 0
            let supportsTransfer = (queueFamily.queueFlags & UInt32(VK_QUEUE_TRANSFER_BIT.rawValue)) != 0
            let supportsCompute  = (queueFamily.queueFlags & UInt32(VK_QUEUE_COMPUTE_BIT.rawValue)) != 0

            //Check for presenting support, its kinda fucking annoying compared to the others
            var presentSupport: VkBool32 = VK_FALSE
            let result = vkGetPhysicalDeviceSurfaceSupportKHR(physDevice, UInt32(i), vkSurface, &presentSupport)
            if result != VK_SUCCESS {
                fatalError("couldnt query physical device surface support")
            }
            let supportsPresent = presentSupport == VK_TRUE

            if preferSeperateGraphicsQueue {
                //prefer dedicated graphics and presentation queues
                if supportsGraphics && !supportsPresent {
                    bestGraphicsFamily = UInt32(i)
                }

                if supportsPresent && !supportsGraphics {
                    bestPresentFamily = UInt32(i)
                }

                if bestGraphicsFamily == nil && bestPresentFamily == nil && 
                    supportsGraphics && supportsPresent {
                        bestGraphicsFamily = UInt32(i)
                        bestPresentFamily = UInt32(i)
                }
            } else {
                //prefer a queue that supports both graphics and presentation
                if supportsGraphics && supportsPresent {
                    bestGraphicsFamily = UInt32(i)
                    bestPresentFamily = UInt32(i)
                }

                //if we havent found a combined graphics+present queue, assign seperate ones
                if supportsGraphics && bestGraphicsFamily == nil {
                    bestGraphicsFamily = UInt32(i)
                }

                if supportsPresent && bestPresentFamily == nil {
                    bestPresentFamily = UInt32(i)
                }
            }

            //prefer a dedicated transfer queue (one that supports transfer but not graphics)
            if supportsTransfer && !supportsGraphics {
                bestTransferFamily = UInt32(i)
            }

            if supportsCompute && !supportsGraphics {
                bestComputeFamily = UInt32(i)
            }
        }

        //fallback: if we didnt find a dedicated transfer queue then just use the graphics one for that
        if bestTransferFamily == nil {
            bestTransferFamily = bestGraphicsFamily
        }

        //same for compute queue
        if bestComputeFamily == nil {
            bestComputeFamily = bestGraphicsFamily
        }

        //yep again
        if bestPresentFamily == nil {
            bestPresentFamily = bestGraphicsFamily
        }

        self.graphicsQueueFamilyIndex = bestGraphicsFamily
        self.presentQueueFamilyIndex = bestPresentFamily
        self.computeQueueFamilyIndex = bestComputeFamily
        self.transferQueueFamilyIndex = bestTransferFamily

        if bestGraphicsFamily == nil {
            fatalError("Failed to find a suitable graphics queue!")
        }
    }

    func setupQueues(logDevice: VkDevice) {
        vkGetDeviceQueue(logDevice, graphicsQueueFamilyIndex!, 0, &graphicsQueue)
        vkGetDeviceQueue(logDevice, presentQueueFamilyIndex!, 0, &presentQueue)
        vkGetDeviceQueue(logDevice, computeQueueFamilyIndex!, 0, &computeQueue)
        vkGetDeviceQueue(logDevice, transferQueueFamilyIndex!, 0, &transferQueue)
    }

    public func getQueueFamilyCount() -> UInt32 {
        return UInt32(queueFamilyCount)
    }

    public func getUniqueQueueFamilyIndices() -> Set<UInt32> {
        if uniqueQueueFamilyIndices == nil {
            uniqueQueueFamilyIndices = Set<UInt32>()
            uniqueQueueFamilyIndices?.insert(graphicsQueueFamilyIndex!)
            uniqueQueueFamilyIndices?.insert(presentQueueFamilyIndex!)
            uniqueQueueFamilyIndices?.insert(transferQueueFamilyIndex!)
            uniqueQueueFamilyIndices?.insert(computeQueueFamilyIndex!)
        }

        return uniqueQueueFamilyIndices!
    }
}