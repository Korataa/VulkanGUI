import CSDL3

public class EventManager {
    private var sdlContext: SDLContext
    private var resizeCallback: (() -> Void)? = nil     

    public init(_ context: SDLContext) {
        self.sdlContext = context
    }

    func setResizeCallback(callback: @escaping () -> Void) {
        self.resizeCallback = callback
    }

    public func pollEvents(shouldQuit: inout Bool) {
        var event = SDL_Event()

        while SDL_PollEvent(&event) {
            switch Int32(event.type) {
                case Int32(SDL_EVENT_QUIT.rawValue):
                    print("pressed close!")
                    shouldQuit = true

                case Int32(SDL_EVENT_WINDOW_RESTORED.rawValue):
                    print("Window has been restored!")
                    sdlContext.setWindowMinimize(minimize: false)

                case Int32(SDL_EVENT_WINDOW_MINIMIZED.rawValue):
                    print("Window has been minimized!")
                    sdlContext.setWindowMinimize(minimize: true)
                
                case Int32(SDL_EVENT_WINDOW_RESIZED.rawValue):
                    print("Window has been resized!")
                    resizeCallback!()

                default:
                    break
            }
        }
    }

    public func cleanup() {
        
    }
}