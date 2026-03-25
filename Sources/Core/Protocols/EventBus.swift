public protocol EventBus {
	// Subscribe to an event name. Returns an id that can be used to unsubscribe.
	@discardableResult
	func subscribe(event: String, _ handler: @escaping (Any?) -> Void) -> Int

	// Unsubscribe a previously-subscribed handler by id for an event name.
	func unsubscribe(event: String, id: Int)

	// Publish an event with an optional payload.
	func publish(event: String, payload: Any?)
}
