import Core
import Foundation

public final class EventBusImpl: EventBus {
	private var nextId: Int = 1
	private var listeners: [String: [Int: (Any?) -> Void]] = [:]
	private let lock = NSLock()

	public init() {}

	@discardableResult
	public func subscribe(event: String, _ handler: @escaping (Any?) -> Void) -> Int {
		lock.lock()
		defer { lock.unlock() }
		let id = nextId
		nextId += 1
		var map = listeners[event] ?? [:]
		map[id] = handler
		listeners[event] = map
		return id
	}

	public func unsubscribe(event: String, id: Int) {
		lock.lock()
		defer { lock.unlock() }
		listeners[event]?[id] = nil
		if let map = listeners[event], map.isEmpty {
			listeners[event] = nil
		}
	}

	public func publish(event: String, payload: Any?) {
		var handlers: [(Any?) -> Void] = []
		lock.lock()
		if let map = listeners[event] {
			handlers = Array(map.values)
		}
		lock.unlock()

		for h in handlers { h(payload) }
	}
}
