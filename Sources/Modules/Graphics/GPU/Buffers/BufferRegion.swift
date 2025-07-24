import Foundation

/// Represents a region within a GPU buffer, encapsulating the offset, size, and buffer reference.
/// This type helps prevent common errors when working with buffer sections by keeping all related information together.
public struct BufferRegion: ~Copyable {
    /// The offset in bytes from the start of the buffer
    public let offset: Int
    
    /// The size in bytes of this region
    public let size: Int
    
    /// Reference to the actual GPU buffer this region belongs to
    public let buffer: any GPUBuffer
    
    /// Creates a new buffer region
    /// - Parameters:
    ///   - offset: Byte offset from start of buffer
    ///   - size: Size of region in bytes
    ///   - buffer: The GPU buffer this region belongs to
    public init(offset: Int, size: Int, buffer: any GPUBuffer) {
        self.offset = offset
        self.size = size
        self.buffer = buffer
    }
    
    /// The end offset of this region (exclusive)
    public var endOffset: Int {
        offset + size
    }
    
    /// Whether this region overlaps with another region
    /// - Parameter other: The other region to check
    /// - Returns: true if the regions overlap
    public func overlaps(with other: borrowing BufferRegion) -> Bool {
        // Check for overlap
        return !(endOffset <= other.offset || other.endOffset <= offset)
    }
    
    /// Checks if this region is completely contained within another region
    /// - Parameter other: The other region to check against
    /// - Returns: true if this region is fully contained within other
    public func isContainedIn(_ other: borrowing BufferRegion) -> Bool {
        return offset >= other.offset && endOffset <= other.endOffset
    }
}
