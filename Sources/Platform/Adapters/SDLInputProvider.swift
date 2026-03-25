import CSDL3
import Core

public final class SDLInputProvider: InputProvider {
    private var mouseX: Float = 0
    private var mouseY: Float = 0
    private var mouseButtons: Set<Int> = []
    private var keyStates: Set<SDL_Scancode> = []

    public var mousePosition: (x: Float, y: Float) { (mouseX, mouseY) }

    public func isMouseButtonDown(_ button: Int) -> Bool {
        mouseButtons.contains(button)
    }

    public func isKeyDown(_ keyCode: Int) -> Bool {
        keyStates.contains(SDL_Scancode(Int32(keyCode)))
    }

    //Call this from your SDL event loop
    public func handleSDLEvent(_ event: SDL_Event) {
        switch event.type {
            case UInt32(SDL_EVENT_MOUSE_MOTION.rawValue):
                mouseX = Float(event.motion.x)
                mouseY = Float(event.motion.y)
            case UInt32(SDL_EVENT_MOUSE_BUTTON_DOWN.rawValue):
                mouseButtons.insert(Int(event.button.button))
            case UInt32(SDL_EVENT_MOUSE_BUTTON_UP.rawValue):
                mouseButtons.remove(Int(event.button.button))
            case UInt32(SDL_EVENT_KEY_DOWN.rawValue):
                keyStates.insert(event.key.scancode)
            case UInt32(SDL_EVENT_KEY_UP.rawValue):
                keyStates.remove(event.key.scancode)
            default:
                break

                
        }
    }

    public func update() {
        // Refresh keyboard state snapshot
        var numKeys: Int32 = 0
        if let keys = SDL_GetKeyboardState(&numKeys) {
            keyStates.removeAll()
            for i in 0..<Int(numKeys) {
                if keys[i] {
                    let sc = SDL_Scancode(Int32(i))
                    keyStates.insert(sc)
                }
            }
        }

        // Refresh mouse position and buttons
        var mx: Float = 0
        var my: Float = 0
        let mask = SDL_GetMouseState(&mx, &my)
        mouseX = mx
        mouseY = my

        mouseButtons.removeAll()
        let buttons: [Int32] = [SDL_BUTTON_LEFT, SDL_BUTTON_MIDDLE, SDL_BUTTON_RIGHT, SDL_BUTTON_X1, SDL_BUTTON_X2]
        for b in buttons {
            let bit: UInt32 = 1 << (UInt32(b) - 1)
            if (mask & bit) != 0 {
                mouseButtons.insert(Int(b))
            }
        }
    }
}