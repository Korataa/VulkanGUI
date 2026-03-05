import Platform
import Core
// UI Layout Containers and Convenience Functions

import Foundation

// Result builder for declarative UI composition
@resultBuilder
public struct UIBuilder {
    public static func buildBlock(_ components: Element...) -> [Element] {
        return Array(components)
    }
    
    public static func buildOptional(_ component: [Element]?) -> [Element] {
        return component ?? []
    }
    
    public static func buildEither(first component: [Element]) -> [Element] {
        return component
    }
    
    public static func buildEither(second component: [Element]) -> [Element] {
        return component
    }
    
    public static func buildArray(_ components: [[Element]]) -> [Element] {
        return components.flatMap { $0 }
    }
}

// MARK: - Layout Containers

/// Vertical stack layout container
public func Column(spacing: Float = 8, @UIBuilder content: () -> [Element]) -> Element {
    return Element(type: .container, children: content())
        .layoutType(.flex(direction: .column, justify: .start, align: .stretch))
        .spacing(spacing)
}

/// Horizontal stack layout container
public func Row(spacing: Float = 8, @UIBuilder content: () -> [Element]) -> Element {
    return Element(type: .container, children: content())
        .layoutType(.flex(direction: .row, justify: .start, align: .center))
        .spacing(spacing)
}

/// Layered/overlapping layout container (z-index based)
public func Stack(@UIBuilder content: () -> [Element]) -> Element {
    return Element(type: .container, children: content())
        .layoutType(.absolute(position: Vector2(0, 0)))
}

/// Empty Column container for explicit API
public func Column() -> Element {
    return Element(type: .container)
        .layoutType(.flex(direction: .column, justify: .start, align: .stretch))
}

/// Empty Row container for explicit API
public func Row() -> Element {
    return Element(type: .container)
        .layoutType(.flex(direction: .row, justify: .start, align: .center))
}

/// Empty Stack container for explicit API
public func Stack() -> Element {
    return Element(type: .container)
        .layoutType(.absolute(position: Vector2(0, 0)))
}

// MARK: - Content Elements

/// Text display element
public func Text(_ content: String = "") -> Element {
    return Element(type: .text(content: content, font: Font.system(size: 14)))
}

/// Interactive button element
public func Button(_ title: String, action: (() -> Void)? = nil) -> Element {
    let element = Element(type: .text(content: title, font: Font.system(size: 14)))
    
    if let action = action {
        return element.onTap(action)
    }
    
    return element
}

/// Empty button for explicit API
public func Button() -> Element {
    return Element(type: .text(content: "", font: Font.system(size: 14)))
}

// MARK: - Layout Helpers

/// Flexible spacing element that grows to fill available space
public func Spacer() -> Element {
    return Element(type: .container)
        .layoutType(.flex(direction: .column, justify: .start, align: .stretch))
}

// MARK: - Extension for content setting (explicit API)
public extension Element {
    func content(@UIBuilder _ builder: () -> [Element]) -> Element {
        var copy = self
        copy.children = builder()
        return copy
    }
    
    func content(_ elements: [Element]) -> Element {
        var copy = self
        copy.children = elements
        return copy
    }
    
    func text(_ content: String) -> Element {
        var copy = self
        if case .text(_, let font) = copy.elementType {
            copy.elementType = .text(content: content, font: font)
        } else {
            copy.elementType = .text(content: content, font: Font.system(size: 14))
        }
        return copy
    }
    
    func title(_ title: String) -> Element {
        return text(title)
    }
}