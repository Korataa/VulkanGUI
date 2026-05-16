import CSDL3
import Core
import Math

public final class SDLInputProvider: InputProvider {
    private let window: OpaquePointer
    public init(window: OpaquePointer) {
        self.window = window
    }
    private var mouseX: Float = 0
    private var mouseY: Float = 0
    private var mouseButtons: Set<Int> = []
    private var keyStates: Set<SDL_Scancode> = []
    private var useRelativeMode: Bool = false

    public var mousePosition: Vector2 { Vector2(mouseX, mouseY) }

    public func isMouseButtonDown(_ button: Int) -> Bool {
        mouseButtons.contains(button)
    }

    //Windows and linux use different types for the keycode
    //On windows we use Int32 and on linux we use UInt32
    //Need to put windows and linux specific code here probably or figure out another way to make it work
    public func isKeyDown(_ keyCode: Int) -> Bool {
        keyStates.contains(SDL_Scancode(UInt32(keyCode)))
    }

    //Call this from your SDL event loop
    public func handleSDLEvent(_ event: SDL_Event) {
        switch event.type {
            case UInt32(SDL_EVENT_MOUSE_MOTION.rawValue):
                // When using relative/polled mode we ignore motion events to avoid
                // double-counting; otherwise update absolute position from events.
                if !useRelativeMode {
                    mouseX = Float(event.motion.x)
                    mouseY = Float(event.motion.y)
                }
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
        updateMouse()
        updateKeyboard()
    }

    public func updateMouse() {
        if useRelativeMode {
            // Poll relative state for low-latency device deltas
            var dx: Float = 0
            var dy: Float = 0
            let mask: SDL_MouseButtonFlags = SDL_GetRelativeMouseState(&dx, &dy)

            // Accumulate device deltas into our logical mouse position
            mouseX += Float(dx)
            mouseY += Float(dy)

            // Update button mask from returned mask
            mouseButtons.removeAll()
            let buttons: [Int32] = [SDL_BUTTON_LEFT, SDL_BUTTON_MIDDLE, SDL_BUTTON_RIGHT, SDL_BUTTON_X1, SDL_BUTTON_X2]
            for b: Int32 in buttons {
                let bit: UInt32 = 1 << (UInt32(b) - 1)
                if (mask & bit) != 0 {
                    mouseButtons.insert(Int(b))
                }
            }
        } else {
            var mx: Float = 0
            var my: Float = 0
            let mask: SDL_MouseButtonFlags = SDL_GetMouseState(&mx, &my)
            mouseX = mx
            mouseY = my

            mouseButtons.removeAll()
            let buttons: [Int32] = [SDL_BUTTON_LEFT, SDL_BUTTON_MIDDLE, SDL_BUTTON_RIGHT, SDL_BUTTON_X1, SDL_BUTTON_X2]
            for b: Int32 in buttons {
                let bit: UInt32 = 1 << (UInt32(b) - 1)
                if(mask & bit) != 0 {
                    mouseButtons.insert(Int(b))
                }
            }
        }
    }

    // Toggle relative/raw mouse handling. Enabling this will make the provider
    // accumulate `xrel`/`yrel` from `SDL_Event.motion`; actually enabling
    // relative mouse mode on the SDL window should be done via `SDLContext`.
    public func setRelativeMode(_ enabled: Bool) {
        useRelativeMode = enabled
        SDL_SetWindowRelativeMouseMode(window, enabled ? true : false)
        if !enabled {
            // when leaving relative mode, reset accumulated position
            mouseX = 0
            mouseY = 0
        }
    }

    public func updateKeyboard() {
        var numKeys: Int32 = 0
        if let keys = SDL_GetKeyboardState(&numKeys) {
            keyStates.removeAll()
            for i in 0..<Int(numKeys) {
                if keys[i] {
                    let sc = SDL_Scancode(UInt32(i))
                    keyStates.insert(sc)
                }
            }
        }
    }
}