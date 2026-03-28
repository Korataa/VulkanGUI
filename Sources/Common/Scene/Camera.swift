import Foundation

// Minimal camera type kept in Common so other modules can reference it
public struct Camera {
    public var projectionMatrix: [Float] = Array(repeating: 0.0, count: 16)
    public var viewMatrix: [Float] = Array(repeating: 0.0, count: 16)
}
