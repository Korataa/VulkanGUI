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

func cCharTupleToString(cChars: Any) -> String? {
    return withUnsafeBytes(of: cChars) { rawBuffer in
        let ptr = rawBuffer.baseAddress!.assumingMemoryBound(to: CChar.self)
        return String(cString: ptr)
    }
}

public struct DynamicArray<T>: ~Copyable {
    //UnsafeMutablePointer is just a pointer to a block of memory
    private var buffer: UnsafeMutableRawPointer?
    private var count: Int
    private var capacity: Int
    private var elementSize: Int    //store the size of each element

    init(capacity: UInt32) {
        self.capacity = Int(capacity)
        if self.capacity <= 0 { self.capacity = 10 }
        self.count = 0
        self.elementSize = MemoryLayout<T>.size     //store the size of T
        
        //alocate raw memory for the buffer
        self.buffer = UnsafeMutableRawPointer.allocate(byteCount: self.capacity * elementSize, alignment: MemoryLayout<T>.alignment)
    }

    //handle optional types
    init(capacity: UInt32, count: Int) {
        self.capacity = Int(capacity)
        if self.capacity <= 0 { self.capacity = 10 }
        self.count = count
        self.elementSize = MemoryLayout<T>.size     //store the size of T
        
        //alocate raw memory for the buffer
        self.buffer = UnsafeMutableRawPointer.allocate(byteCount: self.capacity * elementSize, alignment: MemoryLayout<T>.alignment)
    }

    //handle non optional types
    init(repeating defaultValue: T, count: UInt32) {
        self.capacity = Int(count)
        if self.capacity <= 0 { self.capacity = 5 }
        self.count = Int(count)
        self.elementSize = MemoryLayout<T>.size     //store the size of T
        
        //alocate raw memory for the buffer
        self.buffer = UnsafeMutableRawPointer.allocate(byteCount: self.capacity * elementSize, alignment: MemoryLayout<T>.alignment)

        //initialize memory with nil (for optionals)
        self.buffer?.initializeMemory(as: T.self, repeating: defaultValue, count: self.capacity)
    }

    init(_ elements: T...) {
        self.capacity = max(elements.count, 10)
        self.count = elements.count
        self.elementSize = MemoryLayout<T>.size

        //Allocate raw memory for the buffer
        self.buffer = UnsafeMutableRawPointer.allocate(byteCount: self.capacity * elementSize, alignment: MemoryLayout<T>.alignment)

        //intialize memory with the provided elements
        for (index, element) in elements.enumerated() {
            let pointer = buffer?.advanced(by: index * elementSize).assumingMemoryBound(to: T.self)
            pointer?.initialize(to: element)
        }
    }

    deinit {
        if let buffer = buffer {
            for index in 0..<count {
                let pointer = buffer.advanced(by: index * elementSize).assumingMemoryBound(to: T.self)
                pointer.deinitialize(count: 1)
            }
            buffer.deallocate()
        }
    }

    mutating func append(_ element: T) {
        if count == capacity {
            doubleCapacity()
        }

        //store element in the buffer
        let pointer = buffer?.advanced(by: count * elementSize).assumingMemoryBound(to: T.self)
        pointer?.initialize(to: element)

        count += 1
    }

    mutating func remove(at index: Int) -> T {
        //ensure index is within bounds
        guard index >= 0 && index < count else {
            fatalError("Index is out of bounds!!")
        }

        //get the element at the specified index
        let pointer = buffer?.advanced(by: index * elementSize).assumingMemoryBound(to: T.self)
        let element = pointer!.pointee

        //shift all elements after the removed index
        for i in index..<count - 1 {
            let from = buffer?.advanced(by: (i + 1) * elementSize).assumingMemoryBound(to: T.self)
            let to = buffer?.advanced(by: i * elementSize).assumingMemoryBound(to: T.self)
            to?.initialize(to: from!.pointee)
        }

        //deinitialize the last element and reduce the count
        let lastPointer = buffer?.advanced(by: (count - 1) * elementSize).assumingMemoryBound(to: T.self)
        lastPointer?.deinitialize(count: 1)
        count -= 1
        
        return element
    }

    /// Removes all elements but leaves memory intact, could be useful but the function that also frees memory
    /// is probably the one you want to use ( removeAllAndFreeMemory() )
    mutating func removeAll() {
        if let buffer = buffer {
            for index in 0..<count {
                let pointer = buffer.advanced(by: index * elementSize).assumingMemoryBound(to: T.self)
                pointer.deinitialize(count: 1)
            }
        }
        count = 0
    }

    /// Removes all elements and frees memory, make sure to create a new DynamicArray after using this!!!
    mutating func removeAllAndFreeMemory() {
        if let buffer = buffer {
            for index in 0..<count {
                let pointer = buffer.advanced(by: index * elementSize).assumingMemoryBound(to: T.self)
                pointer.deinitialize(count: 1)
            }
        }

        buffer?.deallocate()
        self.buffer = nil
        self.capacity = 0
        count = 0
    }

    private mutating func doubleCapacity() {
        let newCapacity: Int = capacity * 2
        allocateCapacity(newCapacity: newCapacity)
    }

    public mutating func allocateCapacity(newCapacity: Int) {
        let newBuffer = UnsafeMutableRawPointer.allocate(byteCount: Int(newCapacity) * elementSize, alignment: MemoryLayout<T>.alignment)
        if let buffer = buffer {
            //if T is trivially copyable use memcpy for efficiency
            if MemoryLayout<T>.size <= 8 {
                memcpy(newBuffer, buffer, count * elementSize)
            } else {
                for index in 0..<count {
                    let oldPointer = buffer.advanced(by: index * elementSize).assumingMemoryBound(to: T.self)

                    let newPointer = newBuffer.advanced(by: index * elementSize).assumingMemoryBound(to: T.self)
                    newPointer.initialize(to: oldPointer.pointee)

                    oldPointer.deinitialize(count: 1)
                }
            }

            buffer.deallocate()
        }

        self.buffer = newBuffer
        self.capacity = Int(newCapacity)
    }

    mutating func move(from other: consuming DynamicArray<T>) {
        self.removeAllAndFreeMemory()

        self.buffer = other.buffer
        self.count = other.count
        self.capacity = other.capacity

        other.buffer = nil
        other.count = 0

    }

    subscript(index: Int) -> T {
        _read {
            guard index >= 0 && index < count, let buffer = buffer else {
                fatalError("Index out of bounds or buffer is nil!")
            }
            let pointer = buffer.advanced(by: index * elementSize).assumingMemoryBound(to: T.self)
            yield pointer.pointee
        }

        _modify {
            guard index >= 0 && index < count, let buffer = buffer else {
                fatalError("Index out of bounds or buffer is nil")
            }
            let pointer = buffer.advanced(by: index * elementSize).assumingMemoryBound(to: T.self)
            yield &pointer.pointee
        }
    }

    func first() -> T? {
        guard let _ = buffer, !isEmpty() else { return nil }
        return self[0]
    }

    func last() -> T? {
        guard let _ = buffer, !isEmpty() else { return nil }
        return self[count - 1]
    }

    public func getLength() -> Int { 
        return count
    }

    public func isEmpty() -> Bool {
        return getLength() == 0
    }

    //get underlying buffer as an UnsafeMutablePointer
    public func getData() -> UnsafeMutablePointer<T>? {
        return buffer?.assumingMemoryBound(to: T.self)
    }

    public func getMutableRawPointer() -> UnsafeMutableRawPointer? {
        return buffer
    }

    public func getRawPointer() -> UnsafeRawPointer? {
        return UnsafeRawPointer(buffer)
    }

    public func getOptionalData() -> UnsafeMutablePointer<T?>? {
        return buffer?.assumingMemoryBound(to: T?.self)
    }

    public func getDataAsConstPointer() -> UnsafePointer<T>? {
        return UnsafePointer(buffer?.assumingMemoryBound(to: T.self))
    }

    mutating func consumeElement(at index: Int) -> T {
        //ensure index is within bounds
        guard index >= 0 && index < count else {
            fatalError("index out of bounds!")
        }

        //move the elemnt out of the array, basically consuming it
        let consumedElement: T = self.remove(at: index)

        //return the consumed element
        return consumedElement
    }

    //IM NOT SURE IF THIS WORKS YET DONT USE
    /*public func toArray() -> [UnsafePointer<CChar>] {
        var array: [UnsafePointer<CChar>] = []

        for index in 0..<count {
            print("index is: \(index)")
            let ele = getElement(at: index)
            if let pointer = ele as? UnsafePointer<CChar> {
                print("ele is: \(String(cString: pointer))")
                array.append(pointer)
            } else {
                print("🔥 CRASH AVOIDED: ele is NOT an UnsafePointer<CChar>, it's \(type(of: ele))")
            }
            print("Hello there!")
        
        }
        print("Does this work?!")
        print(array)

        return array
    }*/


}

extension DynamicArray where T == UInt8 {
    func getDataAsUInt32Pointer() -> UnsafePointer<UInt32>? {
        //enusre buffer is initialized and has enough data to cast
        guard let rawData = getRawPointer() else { return nil }

        //calulate the number of 32-bit elements in the data
        let countInUInt32 = getLength() / MemoryLayout<UInt32>.size
        guard countInUInt32 > 0 else { return nil }

        //cast the raw pointer to an UnsafePointer<UInt32>
        return rawData.assumingMemoryBound(to: UInt32.self)
    }
}

extension DynamicArray {
    mutating func withMutablePointerToElement(at index: Int, _ body: (UnsafeMutablePointer<T>) -> T) -> T {
        return withUnsafeMutablePointer(to: &self[index], body)
    }

    func forEach(_ body: (T) -> Void) {
        for i in 0..<count {
            body(self[i])
        }
    }
}

//FOR INTERFACING WITH C LIBRARIES (AND MAYBE C++ TOO I GUESS), ITS IN CASE WE CANNOT USE DynamicArray FOR SOME 
// REASON (usually because swift's move-only types are dogshit right now, maybe swift 6.2 will change that)
extension Array {
    func getDataAsConstPointer() -> UnsafePointer<Element>? {
        return self.withUnsafeBufferPointer { $0.baseAddress }
    }

    mutating func getData() -> UnsafeMutablePointer<Element>? {
        return self.withUnsafeMutableBufferPointer { $0.baseAddress }
    }
}

//literally just read the raw data from the file and put it into a DynamicArray
func readFile(filename: String) throws -> DynamicArray<UInt8> {
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

func getAssetsPath() -> String? {
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

func createUnsafeString(_ str: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let str = str else { return nil }

    let length = strlen(str) + 1

    let dup = UnsafeMutablePointer<CChar>.allocate(capacity: length)
    strcpy(dup, str)

    return dup
}

func tupleToArray<T>(_ tuple: T) -> [Any] {
    return Mirror(reflecting: tuple).children.map { $0.value }
}