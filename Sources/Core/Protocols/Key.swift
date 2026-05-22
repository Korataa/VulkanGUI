public enum Key {
    // Letters
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z

    // Numbers (top row)
    case num0, num1, num2, num3, num4
    case num5, num6, num7, num8, num9

    // Function keys
    case f1, f2, f3, f4, f5, f6
    case f7, f8, f9, f10, f11, f12

    // Navigation
    case up, down, left, right
    case home, end, pageUp, pageDown

    // Editing
    case space, enter, escape, backspace, delete, tab

    // Modifiers
    case leftShift, rightShift
    case leftCtrl, rightCtrl
    case leftAlt, rightAlt

    // Numpad
    case numpad0, numpad1, numpad2, numpad3, numpad4
    case numpad5, numpad6, numpad7, numpad8, numpad9
    case numpadEnter, numpadPlus, numpadMinus, numpadMultiply, numpadDivide

    // Misc
    case insert, printScreen, scrollLock, pause
    case capsLock, numLock
    case leftBracket, rightBracket
    case semicolon, apostrophe, comma, period, slash, backslash
    case minus, equals, grave
}
