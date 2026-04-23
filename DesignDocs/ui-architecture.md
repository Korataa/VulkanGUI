# UI Architecture Plan

## Core Decisions
- Keep components as the author-facing API and `Element` as the runtime/backend representation.
- Components describe intent; elements execute layout, hit-testing, event dispatch, and rendering.
- `UIManager` processes only `Element` trees, not specific component classes.

## Implementation Checklist
- [x] Add a component bridge API (`Component` protocol with `build() -> Element`).
- [x] Map `ButtonComponent` callbacks into runtime element handlers:
	- `onClick` -> `tapHandler`
	- `onHoverStart` -> `onHoverStart`
	- `onHoverEnd` -> `onHoverEnd`
- [x] Add stable element identity (`Element.id`) for interaction continuity.
- [x] Make hover transition logic in `UIManager` compare stable IDs, not transient rebuilt values.
- [x] Use layouted runtime `Element` tree for hit-testing.
- [ ] Add focused element state and keyboard navigation.
- [ ] Add text input focus continuity and edit-state persistence.
- [ ] Add keyed diffing/reconciliation to minimize rebuild churn.

## Why This Works
- Component APIs remain stable even if the internal element subtree evolves.
- Runtime behavior (layout/render/input) stays centralized in `Element` + `UIManager`.
- Stable IDs prevent hover/focus glitches when the UI is rebuilt each frame.

The difference is who triggers the rebuild.

Your current approach — manual:


isMenuOpen.value = trueuiManager.setRoot(buildHUD())  // you have to remember to do this
You change state and manually tell the UI to rebuild. Two steps, easy to forget the second one.

React/SwiftUI — automatic:


isMenuOpen = true  // that's it, rebuild happens automatically
The framework watches the state. When it changes, it rebuilds for you. One step, you can't forget.

Your Reactive<T> with onChange wired up — also automatic:


isMenuOpen.value = true  // onChange fires, setRoot called automatically
Same idea, just your own implementation of it.

The gap between where you are now and React/SwiftUI is basically just that one wire-up — making state changes automatically trigger rebuilds instead of requiring a manual setRoot call after every mutation.


Reviewed Reactive.swift
It's an observer pattern. Here's how it works:

The core mechanic:


var value: T {    get { _value }    set {        _value = newValue        notifyObservers()  // tell everyone it changed    }}
observers is just an array of closures. When .value is set, it loops through every closure in that array and calls it with the new value.

You subscribe like this:


let hp = Reactive(100)hp.observe { newValue in    print("HP changed to \(newValue)")}hp.value = 50  // prints "HP changed to 50" automatically
What's missing to make it work for UI rebuilds:

The bind extension on Element already subscribes to changes, but the observer just does print("UI Update needed: ...") — it never actually calls setRoot. That's the one incomplete piece. If that line called uiManager.setRoot(buildHUD()) instead, the whole thing would be automatic.

The problem is Reactive lives in the UI module but it doesn't know about uiManager or buildHUD — those are in your runtime. So you'd wire it from outside:


hp.onChange { _ in    uiManager.setRoot(buildHUD())}
That's literally all that's missing.

