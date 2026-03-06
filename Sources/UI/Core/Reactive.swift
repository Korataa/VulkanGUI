import Core
import Graphics
import Core
// Reactive State Management for UI System

import Foundation

/// Simple reactive value container that notifies observers when the value changes
public class Reactive<T> {
    private var _value: T
    private var observers: [(T) -> Void] = []
    
    /// Current value - triggers observers when set
    public var value: T {
        get { _value }
        set { 
            _value = newValue
            notifyObservers()
        }
    }
    
    public init(_ initialValue: T) {
        self._value = initialValue
    }
    
    /// Subscribe to value changes
    public func observe(_ callback: @escaping (T) -> Void) {
        observers.append(callback)
        // Call immediately with current value
        callback(_value)
    }
    
    /// Subscribe to value changes (same as observe, more SwiftUI-like name)
    public func onChange(_ callback: @escaping (T) -> Void) {
        observe(callback)
    }
    
    private func notifyObservers() {
        observers.forEach { $0(_value) }
    }
}

// MARK: - Element Extensions for Reactive Binding

public extension Element {
    /// Bind element content to a reactive value with a transform function
    func bind<T>(_ reactive: Reactive<T>, transform: @escaping (T) -> String) -> Element {
        var element = self
        
        // Set initial value based on element type
        let initialText = transform(reactive.value)
        if case .text(_, let font) = element.elementType {
            element.elementType = .text(content: initialText, font: font)
        } else {
            element.elementType = .text(content: initialText, font: Font.system(size: 14))
        }
        
        // Subscribe to updates (in a real implementation, we'd need weak references to avoid retain cycles)
        reactive.observe { [element] newValue in
            let newText = transform(newValue)
            // In a full implementation, this would trigger a UI update
            // For now, we'll implement the update mechanism later
            print("UI Update needed: \(newText)")
        }
        
        return element
    }
    
    /// Bind element content directly to a reactive string
    func bind(_ reactive: Reactive<String>) -> Element {
        return bind(reactive) { $0 }
    }
    
    /// Bind element content to a reactive Int
    func bind(_ reactive: Reactive<Int>) -> Element {
        return bind(reactive) { "\($0)" }
    }
}