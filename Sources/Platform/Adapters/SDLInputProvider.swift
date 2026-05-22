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
    private var keyboardState: UnsafePointer<Bool>? = nil
    private var numKeys: Int32 = 0
    private var useRelativeMode: Bool = false

    public var mousePosition: Vector2 { Vector2(mouseX, mouseY) }

    public func isMouseButtonDown(_ button: Int) -> Bool {
        mouseButtons.contains(button)
    }

    public func isKeyDown(_ key: Key) -> Bool {
        guard let keys = keyboardState else { return false }
        let sc = Self.scancode(for: key)
        let idx = Int(sc.rawValue)
        guard idx < Int(numKeys) else { return false }
        return keys[idx]
    }

    private static func scancode(for key: Key) -> SDL_Scancode {
        switch key {
        case .a: return SDL_SCANCODE_A
        case .b: return SDL_SCANCODE_B
        case .c: return SDL_SCANCODE_C
        case .d: return SDL_SCANCODE_D
        case .e: return SDL_SCANCODE_E
        case .f: return SDL_SCANCODE_F
        case .g: return SDL_SCANCODE_G
        case .h: return SDL_SCANCODE_H
        case .i: return SDL_SCANCODE_I
        case .j: return SDL_SCANCODE_J
        case .k: return SDL_SCANCODE_K
        case .l: return SDL_SCANCODE_L
        case .m: return SDL_SCANCODE_M
        case .n: return SDL_SCANCODE_N
        case .o: return SDL_SCANCODE_O
        case .p: return SDL_SCANCODE_P
        case .q: return SDL_SCANCODE_Q
        case .r: return SDL_SCANCODE_R
        case .s: return SDL_SCANCODE_S
        case .t: return SDL_SCANCODE_T
        case .u: return SDL_SCANCODE_U
        case .v: return SDL_SCANCODE_V
        case .w: return SDL_SCANCODE_W
        case .x: return SDL_SCANCODE_X
        case .y: return SDL_SCANCODE_Y
        case .z: return SDL_SCANCODE_Z
        case .num0: return SDL_SCANCODE_0
        case .num1: return SDL_SCANCODE_1
        case .num2: return SDL_SCANCODE_2
        case .num3: return SDL_SCANCODE_3
        case .num4: return SDL_SCANCODE_4
        case .num5: return SDL_SCANCODE_5
        case .num6: return SDL_SCANCODE_6
        case .num7: return SDL_SCANCODE_7
        case .num8: return SDL_SCANCODE_8
        case .num9: return SDL_SCANCODE_9
        case .f1: return SDL_SCANCODE_F1
        case .f2: return SDL_SCANCODE_F2
        case .f3: return SDL_SCANCODE_F3
        case .f4: return SDL_SCANCODE_F4
        case .f5: return SDL_SCANCODE_F5
        case .f6: return SDL_SCANCODE_F6
        case .f7: return SDL_SCANCODE_F7
        case .f8: return SDL_SCANCODE_F8
        case .f9: return SDL_SCANCODE_F9
        case .f10: return SDL_SCANCODE_F10
        case .f11: return SDL_SCANCODE_F11
        case .f12: return SDL_SCANCODE_F12
        case .up: return SDL_SCANCODE_UP
        case .down: return SDL_SCANCODE_DOWN
        case .left: return SDL_SCANCODE_LEFT
        case .right: return SDL_SCANCODE_RIGHT
        case .home: return SDL_SCANCODE_HOME
        case .end: return SDL_SCANCODE_END
        case .pageUp: return SDL_SCANCODE_PAGEUP
        case .pageDown: return SDL_SCANCODE_PAGEDOWN
        case .space: return SDL_SCANCODE_SPACE
        case .enter: return SDL_SCANCODE_RETURN
        case .escape: return SDL_SCANCODE_ESCAPE
        case .backspace: return SDL_SCANCODE_BACKSPACE
        case .delete: return SDL_SCANCODE_DELETE
        case .tab: return SDL_SCANCODE_TAB
        case .leftShift: return SDL_SCANCODE_LSHIFT
        case .rightShift: return SDL_SCANCODE_RSHIFT
        case .leftCtrl: return SDL_SCANCODE_LCTRL
        case .rightCtrl: return SDL_SCANCODE_RCTRL
        case .leftAlt: return SDL_SCANCODE_LALT
        case .rightAlt: return SDL_SCANCODE_RALT
        case .numpad0: return SDL_SCANCODE_KP_0
        case .numpad1: return SDL_SCANCODE_KP_1
        case .numpad2: return SDL_SCANCODE_KP_2
        case .numpad3: return SDL_SCANCODE_KP_3
        case .numpad4: return SDL_SCANCODE_KP_4
        case .numpad5: return SDL_SCANCODE_KP_5
        case .numpad6: return SDL_SCANCODE_KP_6
        case .numpad7: return SDL_SCANCODE_KP_7
        case .numpad8: return SDL_SCANCODE_KP_8
        case .numpad9: return SDL_SCANCODE_KP_9
        case .numpadEnter: return SDL_SCANCODE_KP_ENTER
        case .numpadPlus: return SDL_SCANCODE_KP_PLUS
        case .numpadMinus: return SDL_SCANCODE_KP_MINUS
        case .numpadMultiply: return SDL_SCANCODE_KP_MULTIPLY
        case .numpadDivide: return SDL_SCANCODE_KP_DIVIDE
        case .insert: return SDL_SCANCODE_INSERT
        case .printScreen: return SDL_SCANCODE_PRINTSCREEN
        case .scrollLock: return SDL_SCANCODE_SCROLLLOCK
        case .pause: return SDL_SCANCODE_PAUSE
        case .capsLock: return SDL_SCANCODE_CAPSLOCK
        case .numLock: return SDL_SCANCODE_NUMLOCKCLEAR
        case .leftBracket: return SDL_SCANCODE_LEFTBRACKET
        case .rightBracket: return SDL_SCANCODE_RIGHTBRACKET
        case .semicolon: return SDL_SCANCODE_SEMICOLON
        case .apostrophe: return SDL_SCANCODE_APOSTROPHE
        case .comma: return SDL_SCANCODE_COMMA
        case .period: return SDL_SCANCODE_PERIOD
        case .slash: return SDL_SCANCODE_SLASH
        case .backslash: return SDL_SCANCODE_BACKSLASH
        case .minus: return SDL_SCANCODE_MINUS
        case .equals: return SDL_SCANCODE_EQUALS
        case .grave: return SDL_SCANCODE_GRAVE
        }
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
        keyboardState = SDL_GetKeyboardState(&numKeys)
    }
}