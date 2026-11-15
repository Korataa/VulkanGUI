import Foundation

//internal cross product for SIMD3 type
private func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    return SIMD3<Float>(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    )
}

//internal dot product for SIMD3 type
private func dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    return a.x * b.x + a.y * b.y + a.z * b.z
}

public struct Matrix3x3 {
    var c0: SIMD3<Float>
    var c1: SIMD3<Float>
    var c2: SIMD3<Float>

    public init(_ c0: SIMD3<Float>, _ c1: SIMD3<Float>, _ c2: SIMD3<Float>) {
        self.c0 = c0
        self.c1 = c1
        self.c2 = c2
    }

    public static func identity() -> Matrix3x3 {
        return Matrix3x3(
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, 1, 0), 
            SIMD3<Float>(0, 0, 1)
        )
    }

    public func transposed() -> Matrix3x3 {
        return Matrix3x3(
            SIMD3<Float>(c0.x, c1.x, c2.x),
            SIMD3<Float>(c0.y, c1.y, c2.y),
            SIMD3<Float>(c0.z, c1.z, c2.z)
        )
    }

    public func row(_ index: Int) -> SIMD3<Float> {
        return SIMD3<Float>(c0[index], c1[index], c2[index])
    }

    public func inverted() -> Matrix3x3 {
        let r0 = cross(c1, c2)
        let r1 = cross(c2, c0)
        let r2 = cross(c0, c1)

        let det = dot(c0, r0)
        if abs(det) < 1e-6 {
            //not invertible
            return Matrix3x3.identity()
        }

        let invDet = 1.0 / det
        return Matrix3x3(
            r0 * invDet,
            r1 * invDet,
            r2 * invDet
        ).transposed()
    }

    public var columns: [SIMD3<Float>] {
        [c0, c1, c2]
    }

    // Matrix-vector multiplication
    public static func *(lhs: Matrix3x3, rhs: SIMD3<Float>) -> SIMD3<Float> {
        return SIMD3<Float>(
            dot(lhs.row(0), rhs),
            dot(lhs.row(1), rhs),
            dot(lhs.row(2), rhs)
        )
    }

    public subscript(index: Int) -> SIMD3<Float> {
        get {
            switch index {
            case 0: return c0
            case 1: return c1
            case 2: return c2
            default:
                fatalError("Index out of bounds for Matrix3x3")
            }
        }

        set {
            switch index {
                case 0: c0 = newValue
                case 1: c1 = newValue
                case 2: c2 = newValue
                default:
                    fatalError("Index out of bounds for Matrix3x3")
            }
        }
    }
}

public struct Matrix4x4 {
    var c0: SIMD4<Float>
    var c1: SIMD4<Float>
    var c2: SIMD4<Float>
    var c3: SIMD4<Float>

    public init(_ c0: SIMD4<Float>, _ c1: SIMD4<Float>, _ c2: SIMD4<Float>, _ c3: SIMD4<Float>) {
        self.c0 = c0
        self.c1 = c1
        self.c2 = c2
        self.c3 = c3
    }

    public init(
        _ m0: Float, _ m1: Float, _ m2: Float, _ m3: Float,
        _ m4: Float, _ m5: Float, _ m6: Float, _ m7: Float,
        _ m8: Float, _ m9: Float, _ m10: Float, _ m11: Float,
        _ m12: Float, _ m13: Float, _ m14: Float, _ m15: Float
    ) {
        self.c0 = SIMD4<Float>(m0, m1, m2, m3)
        self.c1 = SIMD4<Float>(m4, m5, m6, m7)
        self.c2 = SIMD4<Float>(m8, m9, m10, m11)
        self.c3 = SIMD4<Float>(m12, m13, m14, m15)
    }

    init(translation t: Vector3) {
        self = Matrix4x4.identity()
        self[3] = SIMD4<Float>(t.x, t.y, t.z, 1)
    }

    init(scale s: Vector3) {
        self = Matrix4x4.identity()
        self[0].x = s.x
        self[1].y = s.y
        self[2].z = s.z
    }

    public static func identity() -> Matrix4x4 {
        return Matrix4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }

    public static func *(lhs: Matrix4x4, rhs: Matrix4x4) -> Matrix4x4 {
        var result: [SIMD4<Float>] = []
        for i in 0..<4 {
            let rhsCol = rhs[i]
            result.append(SIMD4<Float>( 
                dot(lhs.row(0), rhsCol),
                dot(lhs.row(1), rhsCol),
                dot(lhs.row(2), rhsCol),
                dot(lhs.row(3), rhsCol)
            ))
        }
        return Matrix4x4(result[0], result[1], result[2], result[3])
    }

    // Matrix-vector multiplication
    public static func *(lhs: Matrix4x4, rhs: SIMD4<Float>) -> SIMD4<Float> {
        return SIMD4<Float>(
            dot(lhs.row(0), rhs),
            dot(lhs.row(1), rhs),
            dot(lhs.row(2), rhs),
            dot(lhs.row(3), rhs)
        )
    }

    private static func dot(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Float {
        return (a * b).x + (a * b).y + (a * b).z + (a * b).w
    }

    private func row(_ index: Int) -> SIMD4<Float> {
        return SIMD4<Float>(c0[index], c1[index], c2[index], c3[index])
    }

    public var upperLeft3x3: Matrix3x3 {
        get {
            Matrix3x3( 
                SIMD3<Float>(c0.x, c0.y, c0.z),
                SIMD3<Float>(c1.x, c1.y, c1.z),
                SIMD3<Float>(c2.x, c2.y, c2.z)
            )
        }

        set {
            c0.x = newValue.c0.x; c0.y = newValue.c0.y; c0.z = newValue.c0.z
            c1.x = newValue.c1.x; c1.y = newValue.c1.y; c1.z = newValue.c1.z
            c2.x = newValue.c2.x; c2.y = newValue.c2.y; c2.z = newValue.c2.z
        }
    }

    //an array of columns for easier access
    public var columns: [SIMD4<Float>] {
        [c0, c1, c2, c3]
    }

    public subscript(index: Int) -> SIMD4<Float> {
        get {
            switch index {
            case 0: return c0
            case 1: return c1
            case 2: return c2
            case 3: return c3
            default:
                fatalError("Index out of bounds for Matrix4x4")
            }
        }

        set {
            switch index {
            case 0: c0 = newValue
            case 1: c1 = newValue
            case 2: c2 = newValue
            case 3: c3 = newValue
            default:
                fatalError("Index out of bounds for Matrix4x4")
            }
        }
    }
}

public struct Vector2 {
    var simd: SIMD2<Float>

    public init(_ x: Float, _ y: Float) {
        self.simd = SIMD2(x, y)
    }

    public init(_ simd: SIMD2<Float>) {
        self.simd = simd
    }

    //Computed properties to make the api nicer to use
    public var x: Float { 
        get { simd.x }
        set { simd.x = newValue } 
    }

    public var y: Float {
        get { simd.y }
        set { simd.y = newValue }
    }

    public func length() -> Float {
        return sqrt((simd.x * simd.x) + (simd.y * simd.y))
    }

    public static func zero() -> Vector2 {
        return Vector2(0, 0)
    }

    public static func +(lhs: Vector2, rhs: Vector2) -> Vector2 {
        return Vector2(lhs.simd + rhs.simd)
    }

    public static func -(lhs: Vector2, rhs: Vector2) -> Vector2 {
        return Vector2(lhs.simd - rhs.simd)
    }
}

public struct Vector3 {
    private var simd: SIMD3<Float>
    private let padding: Float = 0

    public init(_ x: Float, _ y: Float, _ z: Float) {
        self.simd = SIMD3(x, y, z)
    }

    public init(_ simd: SIMD3<Float>) {
        self.simd = simd
    }

    public var x: Float { 
        get { simd.x }
        set { simd.x = newValue } 
    }

    public var y: Float {
        get { simd.y }
        set { simd.y = newValue }
    }

    public var z: Float {
        get { simd.z }
        set { simd.z = newValue }
    }

    public func length() -> Float {
        return sqrt(simd.x * simd.x + simd.y * simd.y + simd.z * simd.z)
    }

    public func zero() -> Vector3 {
        return Vector3(0, 0, 0)
    }

    public static func +(lhs: Vector3, rhs: Vector3) -> Vector3 {
        return Vector3(lhs.simd + rhs.simd)
    }

    public static func -(lhs: Vector3, rhs: Vector3) -> Vector3 {
        return Vector3(lhs.simd - rhs.simd)
    }

    /// The cross product
    ///                     (Ay * Bz) - (Az * By)
    /// Formula: A x B =    (Az * Bx) - (Ax * Bz)
    ///                     (Ax * By) - (Ay * Bx)
    public func cross(other: Vector3) -> Vector3 {
        return Vector3(
            (self.simd.y * other.simd.z) - (self.simd.z * other.simd.y),
            (self.simd.z * other.simd.x) - (self.simd.x * other.simd.z),
            (self.simd.x * other.simd.y) - (self.simd.y * other.simd.x)
        )
    }

    ///Alternative cross product function
    public func x(other: Vector3) {

    }

    /// The dot product
    /// 
    /// Formula: A . B =    (Ax * Bx) +  (Ay * By) + (Az * Bz)
    /// 
    public func dot(other: Vector3) -> Float {
        return  (self.simd.x * other.simd.x) + 
                (self.simd.y * other.simd.y) + 
                (self.simd.z * other.simd.z)
    }

    public func normalize() -> Vector3 {
        let len = self.length()
        if len == 0 { return self }
        return Vector3(simd / len)
    }
}

public struct Vector4 {
    private var simd: SIMD4<Float>

    public init(_ x: Float, _ y: Float, _ z: Float, _ w: Float) {
        self.simd = SIMD4(x, y, z, w)
    }

    public init(_ xyz: Vector3, _ w: Float) {
        self.simd = SIMD4(xyz.x, xyz.y, xyz.z, w)
    }

    public init(_ simd: SIMD4<Float>) {
        self.simd = simd
    }

    public var x: Float { 
        get { simd.x }
        set { simd.x = newValue } 
    }

    public var y: Float {
        get { simd.y }
        set { simd.y = newValue }
    }

    public var z: Float {
        get { simd.z }
        set { simd.z = newValue }
    }

    public var w: Float {
        get { simd.w }
        set { simd.w = newValue }
    }

    public func length() -> Float {
        return sqrt(simd.x * simd.x + simd.y * simd.y + simd.z * simd.z + simd.w * simd.w)
    }

    public static func zero() -> Vector4 {
        return Vector4(0, 0, 0, 0)
    }

    public static func +(lhs: Vector4, rhs: Vector4) -> Vector4 {
        return Vector4(lhs.simd + rhs.simd)
    }

    public static func -(lhs: Vector4, rhs: Vector4) -> Vector4 {
        return Vector4(lhs.simd - rhs.simd)
    }

    public static func /(lhs: Vector4, rhs: Float) -> Vector4 {
        return Vector4(lhs.simd / rhs)
    }

    public func dot(_ other: Vector4) -> Float {
        return (self.simd.x * other.simd.x) + 
               (self.simd.y * other.simd.y) + 
               (self.simd.z * other.simd.z) +
               (self.simd.w * other.simd.w)
    }

    public func normalize() -> Vector4 {
        let len = self.length()
        if len == 0 { return self }
        return Vector4(simd / len)
    }
}

public func orthographicMatrix(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> Matrix4x4 {
    let rl = right - left
    let tb = top - bottom
    let fn = far - near
    
    return Matrix4x4(
        SIMD4<Float>(2.0 / rl, 0, 0, 0),
        SIMD4<Float>(0, 2.0 / tb, 0, 0),
        SIMD4<Float>(0, 0, -1.0 / fn, 0),
        SIMD4<Float>(-(right + left) / rl, -(top + bottom) / tb, -near / fn, 1)
    )
}