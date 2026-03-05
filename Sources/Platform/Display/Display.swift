import Core
import CSDL3

class Display {
    private var sdlContext: SDLContext
    private var windowHandle: OpaquePointer?

    public var width = 800
    public var height = 600
    public var title: String = "Game engine"

    init(_ context: SDLContext) {
        self.sdlContext = context

        #if os(Windows) || os(macOS) || os(Linux)
        //use vulkan on all of these platforms
        self.windowHandle = SDL_CreateWindow(title, Int32(width), Int32(height), 
            SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE)
        #else
        //havent set anythnig else up yet
        fatalError("The engine has not been set up for this platform yet!")
        #endif

        if self.windowHandle == nil {
            fatalError("couldnt create the window, SDL_GetError(): \(String(cString: SDL_GetError()))")
        }

        let windowFlags: SDL_WindowFlags = SDL_GetWindowFlags(windowHandle)
        print("Window flags are: \(windowFlags)")

        if (windowFlags & 0x0000000010000000) == 0 {
            print("The window does not have Vulkan support enabled!")
        } else {
            print("Vulkan support is enabled on the window.")
        }

        sdlContext.setWindowHandle(sdlWindow: windowHandle)
    }

    func cleanup() {
        print("Destroying window!")
        SDL_DestroyWindow(windowHandle)
    }
}