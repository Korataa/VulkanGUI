import Math

public protocol InputProvider {
    //Mouse
    var mousePosition: Vector2 { get }
    func isMouseButtonDown(_ button: Int) -> Bool

    //Keyboard
    func isKeyDown(_ key: Key) -> Bool

    //Polling (maybe we wont use this? idk)
    func update()
}