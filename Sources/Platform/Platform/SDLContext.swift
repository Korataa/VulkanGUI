import Core
import CSDL3

struct SurfaceDetails {
    var surfaceHandle: OpaquePointer?   // raw graphics api surface handle (e.g. VkSurfaceKHR)
    var width: Int
    var height: Int

    //optional fields for platform-specific details
    var pixelFormat: String?
    var surfaceType: String?

    init(surfaceHandle: OpaquePointer?, width: Int, height: Int, pixelFormat: String? = nil, surfaceType: String? = nil) {
        self.surfaceHandle = surfaceHandle
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.surfaceType = surfaceType
    }
}

public class SDLContext {
    private var windowHandle: OpaquePointer?

    private var windowMinimized: Bool = false

    public init() {}

    public func initialize() {
        // Prefer raw/unaccelerated input where available (set hints before SDL_Init)
        // Use literal hint names to avoid depending on binding constants.
        SDL_SetHint("SDL_HINT_WINDOWS_RAW_KEYBOARD", "1")
        SDL_SetHint("SDL_HINT_JOYSTICK_RAWINPUT", "1")

        // sdl specific initialization
        if !SDL_Init(SDL_INIT_VIDEO) {
            fatalError("SDL Error: \(String(cString: SDL_GetError()))")
        }

        if !SDL_Vulkan_LoadLibrary(nil) {
            fatalError("Failed to load Vulkan library: \(String(cString: SDL_GetError()))")
        }

        print("SDL initialized!")
    }

    func setWindowHandle(sdlWindow: OpaquePointer?) {
        self.windowHandle = sdlWindow
    }

    public func getWindowHandle() -> OpaquePointer? {
        return windowHandle
    }

    public func createSurface(instance: OpaquePointer, surface: inout OpaquePointer?) -> Bool {
        let result = SDL_Vulkan_CreateSurface(windowHandle, instance, nil, &surface)

        if !result {
            fatalError("Failed to create vulkan surface with SDL!")
        }

        print("created vulkan surface: \(surface!)")
        return result
    }

    func cleanup() {
        //clean up sdl resources
        SDL_Quit()

    }

    //FUNCTIONS TO HELP OUTSIDE USERS

    public func getRequiredVulkanExtensionsFromSDL() -> DynamicArray<UnsafePointer<CChar>?> {
        print("inside of getrequiredvulkanextensionsFromSDL")
        var count: UInt32 = 0
        let extensions: UnsafePointer<UnsafePointer<CChar>?>? = SDL_Vulkan_GetInstanceExtensions(&count)

        print("inside of getrequiredvulkanextensionsFromSDL")

        var extensionsList = DynamicArray<UnsafePointer<CChar>?>(capacity: 2)


        for var i in 0..<count {
            if let ext = extensions?[Int(i)] {
                extensionsList.append(ext)
            }
            i += 1
        }

        return extensionsList
    }

    public func getWindowSizeInPixels(width: inout Int32, height: inout Int32) {
        SDL_GetWindowSizeInPixels(windowHandle, &width, &height)
    }

    // Runtime helpers to prefer raw input via SDL hints (some hints must be set before init).
    public func setWindowsRawKeyboardPreferred(_ enabled: Bool) {
        SDL_SetHint("SDL_HINT_WINDOWS_RAW_KEYBOARD", enabled ? "1" : "0")
    }

    public func setJoystickRawInputPreferred(_ enabled: Bool) {
        SDL_SetHint("SDL_HINT_JOYSTICK_RAWINPUT", enabled ? "1" : "0")
    }

    // Set relative mouse mode for the current window (captures cursor and provides deltas).
    // Uses the SDL_SetWindowRelativeMouseMode binding which accepts the window handle and a Bool.
    public func setWindowRelativeMouseMode(_ enabled: Bool) {
        SDL_SetWindowRelativeMouseMode(windowHandle, enabled)
    }

    public func setWindowMinimize(minimize: Bool) {
        self.windowMinimized = minimize
    }

    public func isWindowMinimized() -> Bool {
        return self.windowMinimized
    }
}