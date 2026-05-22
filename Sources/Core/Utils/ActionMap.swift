public final class ActionMap<Action: Hashable> {
    private var bindings: [Action: Set<Key>] = [:]
    private var currentState: [Action: Bool] = [:]
    private var previousState: [Action: Bool] = [:]

    public init() {}

    public func bind(_ action: Action, to key: Key) {
        bindings[action, default: []].insert(key)
        currentState[action] = currentState[action] ?? false
        previousState[action] = previousState[action] ?? false
    }

    public func bind(_ action: Action, to keys: [Key]) {
        for key in keys {
            bind(action, to: key)
        }
    }

    public func clearBindings(for action: Action) {
        bindings[action] = []
        currentState[action] = false
        previousState[action] = false
    }

    public func update(input: InputProvider) {
        previousState = currentState

        for (action, keys) in bindings {
            currentState[action] = keys.contains { input.isKeyDown($0) }
        }
    }

    public func isDown(_ action: Action) -> Bool {
        currentState[action] ?? false
    }

    public func isJustPressed(_ action: Action) -> Bool {
        let current = currentState[action] ?? false
        let previous = previousState[action] ?? false
        return current && !previous
    }

    public func isJustReleased(_ action: Action) -> Bool {
        let current = currentState[action] ?? false
        let previous = previousState[action] ?? false
        return !current && previous
    }
}