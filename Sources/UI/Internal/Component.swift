/// Author-facing UI component abstraction.
/// Components are pure intent and are converted to runtime `Element` trees.
public protocol Component {
	func build() -> Element
}

public extension Component {
	func asElement() -> Element {
		build()
	}
}
