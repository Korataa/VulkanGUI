public struct Rectangle {
    public var position: Vector2
    public var width: Float
    public var height: Float
}

//Doing this because i am lazy and dont want to have to write public in front of everything, also its stupid you
//have to mark everything with public anyways if you dont do this
public extension Rectangle {
    var topLeft: Vector2 { position }
    var topRight: Vector2 { Vector2(position.x + width, position.y) }
    var bottomLeft: Vector2 { Vector2(position.x, position.y + height) }
    var bottomRight: Vector2 { Vector2(position.x + width, position.y + height) }

    var left: Float { position.x }
    var right: Float { position.x + width }
    var top: Float { position.y }
    var bottom: Float { position.y + height }

    var center: Vector2 {
        Vector2(position.x + width / 2, position.y + height / 2)
    }

    func contains(_ point: Vector2) -> Bool {
        point.x >= left && point.x <= right &&
        point.y >= top && point.y <= bottom
    }

    func intersects (_ other: Rectangle) -> Bool {
        !(right < other.left || left > other.right ||
            bottom < other.top || top > other.bottom)
    }
}