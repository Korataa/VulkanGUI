import Foundation

public let SDL_WINDOW_FULLSCREEN:UInt64 =              0x0000000000000001
public let SDL_WINDOW_OPENGL: UInt64 =                 0x0000000000000002
public let SDL_WINDOW_OCCLUDED:UInt64 =                0x0000000000000004
public let SDL_WINDOW_HIDDEN: UInt64 =                 0x0000000000000008
public let SDL_WINDOW_BORDERLESS: UInt64 =             0x0000000000000010
public let SDL_WINDOW_RESIZABLE: UInt64 =              0x0000000000000020
public let SDL_WINDOW_MINIMIZED: UInt64 =              0x0000000000000040
public let SDL_WINDOW_MAXIMIZED: UInt64 =              0x0000000000000080
public let SDL_WINDOW_MOUSE_GRABBED: UInt64 =          0x0000000000000100
public let SDL_WINDOW_INPUT_FOCUS: UInt64 =            0x0000000000000200
public let SDL_WINDOW_MOUSE_FOCUS: UInt64 =            0x0000000000000400
public let SDL_WINDOW_MODAL: UInt64 =                  0x0000000000001000
public let SDL_WINDOW_HIGH_PIXEL_DENSITY: UInt64 =     0x0000000000002000
public let SDL_WINDOW_MOUSE_CAPTURE: UInt64 =          0x0000000000004000
public let SDL_WINDOW_MOUSE_RELATIVE_MODE: UInt64 =    0x0000000000008000
public let SDL_WINDOW_ALWAYS_ON_TOP: UInt64 =          0x0000000000010000
public let SDL_WINDOW_UTILITY: UInt64 =                0x0000000000020000
public let SDL_WINDOW_TOOLTIP: UInt64 =                0x0000000000040000
public let SDL_WINDOW_POPUP_MENU: UInt64 =             0x0000000000080000
public let SDL_WINDOW_KEYBOARD_GRABBED: UInt64 =       0x0000000000100000
public let SDL_WINDOW_VULKAN: UInt64 =                 0x0000000010000000
public let SDL_WINDOW_METAL: UInt64 =                  0x0000000020000000
public let SDL_WINDOW_TRANSPARENT: UInt64 =            0x0000000040000000
public let SDL_WINDOW_NOT_FOCUSABLE: UInt64 =          0x0000000080000000

public func cCharTupleToString(cChars: Any) -> String? {
    return withUnsafeBytes(of: cChars) { rawBuffer in
        let ptr = rawBuffer.baseAddress!.assumingMemoryBound(to: CChar.self)
        return String(cString: ptr)
    }
}

public func readFile(filename: String) throws -> DynamicArray<UInt8> {
    let fileURL = URL(fileURLWithPath: filename)

    do {
        let data: Data = try Data(contentsOf: fileURL)
        var dynamicArray = DynamicArray<UInt8>(repeating: 0, count: UInt32(data.count))
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
