import Foundation

public struct DynamicArray<T: ~Copyable>: ~Copyable {
    //UnsafeMutablePointer is just a pointer to a block of memory
    private var buffer: UnsafeMutableRawPointer?
    public private(set) var count: Int
    private var capacity: Int
    private var elementSize: Int    //store the size of each element

    public init(capacity: UInt32) {
        self.capacity = Int(capacity)
        if self.capacity <= 0 { self.capacity = 10 }
        self.count = 0
        self.elementSize = MemoryLayout<T>.size     //store the size of T
        
        //alocate raw memory for the buffer
        self.buffer = UnsafeMutableRawPointer.allocate(byteCount: self.capacity * elementSize, alignment: MemoryLayout<T>.alignment)
    }

    //handle optional types
    public init(capacity: UInt32, count: Int) {
        self.capacity = Int(capacity)
        if self.capacity <= 0 { self.capacity = 10 }
        self.count = count
        self.elementSize = MemoryLayout<T>.size     //store the size of T
        
        //alocate raw memory for the buffer
        self.buffer = UnsafeMutableRawPointer.allocate(byteCount: self.capacity * elementSize, alignment: MemoryLayout<T>.alignment)
    }

    //handle non optional types - only available for copyable types
    public init(repeating defaultValue: T, count: UInt32) where T: Copyable {
        self.capacity = Int(count)
        if self.capacity <= 0 { self.capacity = 5 }
        self.count = Int(count)
        self.elementSize = MemoryLayout<T>.size     //store the size of T
        
        //alocate raw memory for the buffer
        self.buffer = UnsafeMutableRawPointer.allocate(byteCount: self.capacity * elementSize, alignment: MemoryLayout<T>.alignment)

        //initialize memory with nil (for optionals)
        self.buffer?.initializeMemory(as: T.self, repeating: defaultValue, count: self.capacity)
    }

    public init(_ elements: T...) where T: Copyable {
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

    public mutating func append(_ element: consuming T) {
        if count == capacity {
            doubleCapacity()
        }

        //store element in the buffer
        let pointer = buffer?.advanced(by: count * elementSize).assumingMemoryBound(to: T.self)
        pointer?.initialize(to: element)

        count += 1
    }

    public mutating func remove(at index: Int) -> T {
        //ensure index is within bounds
        guard index >= 0 && index < count else {
            fatalError("Index is out of bounds!!")
        }

        //get the element at the specified index by moving it out
        let pointer = buffer?.advanced(by: index * elementSize).assumingMemoryBound(to: T.self)
        let element = pointer!.move()

        //shift all elements after the removed index
        for i in index..<count - 1 {
            let from = buffer?.advanced(by: (i + 1) * elementSize).assumingMemoryBound(to: T.self)
            let to = buffer?.advanced(by: i * elementSize).assumingMemoryBound(to: T.self)
            to?.initialize(to: from!.move())
        }

        //the last element was already moved, just reduce the count
        count -= 1
        
        return element
    }

    /// Removes all elements but leaves memory intact, could be useful but the function that also frees memory
    /// is probably the one you want to use ( removeAllAndFreeMemory() )
    public mutating func removeAll() {
        if let buffer = buffer {
            for index in 0..<count {
                let pointer = buffer.advanced(by: index * elementSize).assumingMemoryBound(to: T.self)
                pointer.deinitialize(count: 1)
            }
        }
        count = 0
    }

    /// Removes all elements and frees memory, make sure to create a new DynamicArray after using this!!!
    public mutating func removeAllAndFreeMemory() {
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
                    newPointer.initialize(to: oldPointer.move())
                }
            }

            buffer.deallocate()
        }

        self.buffer = newBuffer
        self.capacity = Int(newCapacity)
    }

    public mutating func move(from other: consuming DynamicArray<T>) {
        self.removeAllAndFreeMemory()

        self.buffer = other.buffer
        self.count = other.count
        self.capacity = other.capacity

        other.buffer = nil
        other.count = 0

    }

    public subscript(index: Int) -> T {
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

    func first() -> T? where T: Copyable {
        guard let _ = buffer, !isEmpty() else { return nil }
        return self[0]
    }

    func last() -> T? where T: Copyable {
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

    public mutating func consumeElement(at index: Int) -> T {
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
    public func getDataAsUInt32Pointer() -> UnsafePointer<UInt32>? {
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