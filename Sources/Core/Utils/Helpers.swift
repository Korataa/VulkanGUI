//this container is for interacting with low level c libraries (and maybe c++)
//its basically a C++ std::vector

import Foundation

public let SDL_WINDOW_FULLSCREEN:UInt64 =              0x0000000000000001  /**< window is in fullscreen mode */
public let SDL_WINDOW_OPENGL: UInt64 =                 0x0000000000000002    /**< window usable with OpenGL context */
public let SDL_WINDOW_OCCLUDED:UInt64 =                0x0000000000000004    /**< window is occluded */
public let SDL_WINDOW_HIDDEN: UInt64 =                 0x0000000000000008    /**< window is neither mapped onto the desktop nor shown in the taskbar/dock/window list; SDL_ShowWindow() is required for it to become visible */
public let SDL_WINDOW_BORDERLESS: UInt64 =             0x0000000000000010    /**< no window decoration */
public let SDL_WINDOW_RESIZABLE: UInt64 =              0x0000000000000020    /**< window can be resized */
public let SDL_WINDOW_MINIMIZED: UInt64 =              0x0000000000000040    /**< window is minimized */
public let SDL_WINDOW_MAXIMIZED: UInt64 =              0x0000000000000080    /**< window is maximized */
public let SDL_WINDOW_MOUSE_GRABBED: UInt64 =          0x0000000000000100    /**< window has grabbed mouse input */
public let SDL_WINDOW_INPUT_FOCUS: UInt64 =            0x0000000000000200    /**< window has input focus */
public let SDL_WINDOW_MOUSE_FOCUS: UInt64 =            0x0000000000000400    /**< window has mouse foclet SDL_WINDOW_EXTERNAL*/
public let SDL_WINDOW_MODAL: UInt64 =                  0x0000000000001000    /**< window is modal */
public let SDL_WINDOW_HIGH_PIXEL_DENSITY: UInt64 =     0x0000000000002000    /**< window uses high pixel density back buffer if possible */
public let SDL_WINDOW_MOUSE_CAPTURE: UInt64 =          0x0000000000004000    /**< window has mouse captured (unrelated to MOUSE_GRABBED) */
public let SDL_WINDOW_MOUSE_RELATIVE_MODE: UInt64 =    0x0000000000008000    /**< window has relative mode enabled */
public let SDL_WINDOW_ALWAYS_ON_TOP: UInt64 =          0x0000000000010000    /**< window should always be above others */
public let SDL_WINDOW_UTILITY: UInt64 =                0x0000000000020000    /**< window should be treated as a utility window, not showing in the task bar and window list */
public let SDL_WINDOW_TOOLTIP: UInt64 =                0x0000000000040000    /**< window should be treated as a tooltip and does not get mouse or keyboard focus, requires a parent window */
public let SDL_WINDOW_POPUP_MENU: UInt64 =             0x0000000000080000    /**< window should be treated as a popup menu, requires a parent window */
public let SDL_WINDOW_KEYBOARD_GRABBED: UInt64 =       0x0000000000100000    /**< window has grabbed keyboard input */
public let SDL_WINDOW_VULKAN: UInt64 =                 0x0000000010000000    /**< window usable for Vulkan surface */
public let SDL_WINDOW_METAL: UInt64 =                  0x0000000020000000    /**< window usable for Metal view */
public let SDL_WINDOW_TRANSPARENT: UInt64 =            0x0000000040000000    /**< window with transparent buffer */
public let SDL_WINDOW_NOT_FOCUSABLE: UInt64 =          0x0000000080000000

//VULKAN FLAGS

public func cCharTupleToString(cChars: Any) -> String? {
    return withUnsafeBytes(of: cChars) { rawBuffer in
        let ptr = rawBuffer.baseAddress!.assumingMemoryBound(to: CChar.self)
        return String(cString: ptr)
    }
}

//literally just read the raw data from the file and put it into a DynamicArray
public func readFile(filename: String) throws -> DynamicArray<UInt8> {
    let fileURL = URL(fileURLWithPath: filename)

    do {
        let data: Data = try Data(contentsOf: fileURL)
        var dynamicArray = DynamicArray<UInt8>(repeating: 0, count: UInt32(data.count))
        print("data.count is: \(data.count)")
        
        //copy the bytes from data into the dynamicArray
        for (index, byte) in data.enumerated() {
            dynamicArray[index] = byte
        }

        return dynamicArray
    } catch {
        throw NSError(domain: "FileReadError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open file!"])
    }
}

func printCurrentPath() {
    let fileManager = FileManager.default
    let currentPath = fileManager.currentDirectoryPath
    print("Current directory path: \(currentPath)")
}

struct Config: Decodable {
    let assetsDirectory: String
}

public func getAssetsPath() -> String? {
    let configURL = URL(fileURLWithPath: "config.json")

    do {
        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(Config.self, from: data)
        return config.assetsDirectory
    } catch {
        print("Failed to load or decode config file: \(error)")
    }

    return nil
}

public func createUnsafeString(_ str: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let str = str else { return nil }

    let length = strlen(str) + 1

    let dup = UnsafeMutablePointer<CChar>.allocate(capacity: length)
    strcpy(dup, str)

    return dup
}

public func tupleToArray<T>(_ tuple: T) -> [Any] {
    return Mirror(reflecting: tuple).children.map { $0.value }
}