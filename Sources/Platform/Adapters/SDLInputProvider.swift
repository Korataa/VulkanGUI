import CSDL3

public final class SDLInputProvider: InputProvider {
    private var mouseX: Float = 0
    private var mouseY: Float = 0
    private var mouseButtons: Set<Int> = []
    private var keyStates: Set<Int> = []

    public var mousePosition: (x: Float, y: Float) { (mouseX, mouseY) }

    public func isMouseButtonDown(_ button: Int) -> Bool {
        mouseButtons.contains(button)
    }

    public func isKeyDown(_ keyCode: Int) -> Bool {
        keyStates.contains(keyCode)
    }

    //Call this from your SDL event loop
    public func handleSDLEvent(_ event: SDL_Event) {
        switch event.type {
            case UInt32(SDL_EVENT_MOUSE_MOTION.rawValue):
                // Example: update mouse position here
                mouseX = Float(event.motion.x)
                mouseY = Float(event.motion.y)
        }
    }
}