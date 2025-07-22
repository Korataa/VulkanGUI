import Foundation

public struct Color: Hashable {
    var r: Float
    var g: Float
    var b: Float
    var a: Float

    private(set) var linearR: Float
    private(set) var linearG: Float
    private(set) var linearB: Float
    private(set) var linearA: Float
    
    public static func == (lhs: Color, rhs: Color) -> Bool {
        return lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b && lhs.a == rhs.a
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(r)
        hasher.combine(g)
        hasher.combine(b)
        hasher.combine(a)
    }

    init(_ r: Float, _ g: Float, _ b: Float, _ a: Float) {
        self.r = r; self.g = g; self.b = b; self.a = a;

        linearR = 0
        linearG = 0
        linearB = 0
        linearA = 0

        updateLinearValues()
    }

    private mutating func updateLinearValues() {
        self.linearR = sRGBToLinear(r)
        self.linearG = sRGBToLinear(g)
        self.linearB = sRGBToLinear(b)
        self.linearA = a / 255.0
    }

    public mutating func setColor(_ r: Float, _ g: Float, _ b: Float, _ a: Float) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
        updateLinearValues()
    }

    public static var red: Color { Color(255, 0, 0, 255) }
    public static var green: Color { Color(0, 255, 0, 255) }
    public static var blue: Color { Color(0, 0, 255, 255) }

    public static var white: Color { Color(255, 255, 255, 255) }
    public static var black: Color { Color(0, 0, 0, 255) }

    public func sRGBToLinear(_ value: Float) -> Float {
        let normalized = value / 255.0

        // sRGB to linear conversion formula:
        // LinearValue = (normalized / 12.92) for normalized <= 0.04045
        // LinearValue = ((normalized + 0.055) / 1.055) ^ 2.4 for normalized > 0.04045

        return normalized <= 0.04045
            ? normalized / 12.92                        //linear section of the sRGB curve
            : pow((normalized + 0.055) / 1.055, 2.4)    //Gamma correction
    }
}