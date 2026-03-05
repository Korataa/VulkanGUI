import Core
import CSDL3
import Cvulkan

public class Window {
    private var sdlContext: SDLContext

    var width: Int = 0
    var height: Int = 0

    private var windowHandle: OpaquePointer? = nil

    public init(sdlContext: SDLContext) {
        self.sdlContext = sdlContext
    }

    public func createWindow(title: String, width: Int, height: Int, flags: SDL_WindowFlags = SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE) {
        self.windowHandle = SDL_CreateWindow(
            title,
            Int32(width),
            Int32(height), 
            flags
        )

        self.width = width
        self.height = height

        sdlContext.setWindowHandle(sdlWindow: windowHandle)
    }

    func cleanup() {
        //clean up sdl resources
        SDL_Quit()
    }
}