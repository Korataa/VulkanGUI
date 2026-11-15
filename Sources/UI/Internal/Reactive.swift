import Foundation

private protocol ReactiveSource: AnyObject {
    var revision: UInt64 { get }
    func addRegionObserver(_ callback: @escaping () -> Void) -> UUID
    func removeRegionObserver(_ id: UUID)
}

private final class DependencyTracker {
    private(set) var dependencies: [ObjectIdentifier: (source: any ReactiveSource, revision: UInt64)] = [:]

    func record(_ source: any ReactiveSource) {
        let id = ObjectIdentifier(source)
        if dependencies[id] == nil {
            dependencies[id] = (source, source.revision)
        }
    }
}

private enum ReactiveTracking {
    private static let key = "DeckRPGUI.ReactiveTracking"

    static var current: DependencyTracker? {
        Thread.current.threadDictionary[key] as? DependencyTracker
    }

    static func evaluate<T>(_ body: () -> T) -> (T, DependencyTracker) {
        let dictionary = Thread.current.threadDictionary
        let previous = dictionary[key]
        let tracker = DependencyTracker()
        dictionary[key] = tracker
        defer {
            if let previous {
                dictionary[key] = previous
            } else {
                dictionary.removeObject(forKey: key)
            }
        }
        return (body(), tracker)
    }

    static func untracked<T>(_ body: () -> T) -> T {
        let dictionary = Thread.current.threadDictionary
        let previous = dictionary[key]
        dictionary.removeObject(forKey: key)
        defer {
            if let previous { dictionary[key] = previous }
        }
        return body()
    }
}

/// A value that can be observed by `Dynamic` regions.
/// Values used by the UI must be read and changed on the main thread.
public final class Reactive<T>: ReactiveSource {
    private var storedValue: T
    private var observers: [(T) -> Void] = []
    private var regionObservers: [UUID: () -> Void] = [:]
    fileprivate private(set) var revision: UInt64 = 0

    public var value: T {
        get {
            if !regionObservers.isEmpty {
                precondition(Thread.isMainThread, "UI reactive values must be read on the main thread")
            }
            ReactiveTracking.current?.record(self)
            return storedValue
        }
        set {
            if !regionObservers.isEmpty {
                precondition(Thread.isMainThread, "UI reactive values must be changed on the main thread")
            }
            storedValue = newValue
            revision &+= 1
            let regionCallbacks = Array(regionObservers.values)
            let callbacks = observers
            regionCallbacks.forEach { $0() }
            callbacks.forEach { $0(storedValue) }
        }
    }

    public init(_ initialValue: T) {
        storedValue = initialValue
    }

    /// Subscribe to changes, receiving the current value immediately.
    public func observe(_ callback: @escaping (T) -> Void) {
        observers.append(callback)
        callback(storedValue)
    }

    public func onChange(_ callback: @escaping (T) -> Void) {
        observe(callback)
    }

    fileprivate func addRegionObserver(_ callback: @escaping () -> Void) -> UUID {
        let id = UUID()
        regionObservers[id] = callback
        return id
    }

    fileprivate func removeRegionObserver(_ id: UUID) {
        regionObservers.removeValue(forKey: id)
    }
}

final class ReactiveRegion {
    private let build: () -> Element
    private var subscriptions: [(source: any ReactiveSource, id: UUID)] = []
    private(set) var isDirty = true
    var onInvalidate: (() -> Void)?

    init(_ build: @escaping () -> Element) {
        self.build = build
    }

    deinit {
        for subscription in subscriptions {
            subscription.source.removeRegionObserver(subscription.id)
        }
    }

    func evaluate() -> Element {
        precondition(Thread.isMainThread, "Dynamic UI regions must be evaluated on the main thread")
        isDirty = false
        let (element, tracker) = ReactiveTracking.evaluate(build)

        for subscription in subscriptions {
            subscription.source.removeRegionObserver(subscription.id)
        }
        subscriptions = tracker.dependencies.values.map { dependency in
            let id = dependency.source.addRegionObserver { [weak self] in
                self?.invalidate()
            }
            if dependency.source.revision != dependency.revision {
                invalidate()
            }
            return (dependency.source, id)
        }
        return element
    }

    private func invalidate() {
        if !isDirty {
            isDirty = true
            onInvalidate?()
        }
    }
}

public extension Element {
    /// Bind text to a reactive value. The element retains its styling and handlers.
    func bind<T>(_ reactive: Reactive<T>, transform: @escaping (T) -> String) -> Element {
        var element = self
        let initialText = ReactiveTracking.untracked { transform(reactive.value) }
        if case .text(_, let font) = element.elementType {
            element.elementType = .text(content: initialText, font: font)
        } else {
            element.elementType = .text(content: initialText, font: Font.system(size: 14))
        }
        element.reactiveText = { transform(reactive.value) }
        return element
    }

    func bind(_ reactive: Reactive<String>) -> Element {
        bind(reactive) { $0 }
    }

    func bind(_ reactive: Reactive<Int>) -> Element {
        bind(reactive) { "\($0)" }
    }
}
