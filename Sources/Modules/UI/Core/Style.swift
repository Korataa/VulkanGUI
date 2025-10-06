//Simple styling system for ui elements
//Start basic, expand as needed
public struct Style {
    //Visual properties
    public var backgroundColor: Color?
    public var borderColor: Color?
    public var textColor: Color = .white

    //Layout properties
    public var padding: Spacing = Spacing()
    public var margin: Spacing = Spacing()
}