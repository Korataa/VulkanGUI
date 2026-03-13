# DeckRPG — Project TODO (UI, Job System, Repo Reorg)

Summary
- Keep UI code as a dedicated module that depends only on small engine-facing protocols.
- Use the engine renderer for UI now via an adapter; keep the UI API (`UIRenderer`) minimal.
- Support both screen-space (overlay) and world-space (diegetic) UI with the same `UIComponent` API; differences are coordinate transforms and hit-test context. (TBH the diegetic part is kinda not that improtant AT FIRST, but then again it would be cool to have in my first game even... so actually maybe it is important)
- Implement a small, upgradeable job system in core with a main-thread completion/dispatcher for safe UI/SDL interactions.
- Centralize input on main thread via an `InputProvider` (SDL-backed) and route input through a `ScreenManager`/`InputRouter`.

Proposed folder / target layout
- `Sources/CoreAPI/` — small protocols: `UIRenderer`, `InputProvider`, `AssetLoader`, `EventBus`, `TimeProvider`, `JobSystem` types.
- `Sources/UI/` — retained UI system: `ScreenManager.swift`, `Screens/`, `Components/`, `Diegetic/`, `Layouts/` (prefabs).
- `Sources/Runtime/` — engine implementations: `SDLInputProvider.swift`, `JobSystem.swift` (thread-pool), `MainThreadDispatcher.swift`, `EngineUIRenderer.swift`, app bootstrap.
- `Sources/Graphics/` — renderer surfaces and adapters where needed.
- `Assets/UI/` — JSON/YAML layouts, styles, prefabs for hot-reload later.

Design decisions
- UI depends only on `CoreAPI` protocols; `Runtime` injects concrete implementations at startup (dependency injection).
- `UIRenderer` is a thin protocol. Implement `EngineUIRenderer` that forwards to the engine renderer (batches, texture handles, transforms).
- Keep UI and SDL on main thread (input, hit-testing, final rendering). Workers must never call SDL or UI APIs.
- Job system belongs to `CoreAPI` (so UI, tools, runtime can enqueue work). Concrete scheduler lives in `Runtime` and can be swapped later.
- Start minimal and extensible: provide `enqueue(job)`, `enqueue(job, completion)`, `JobHandle`/`JobCounter`, and `dispatchToMain`/`flush`.
- Design the job API and `MainThreadDispatcher` so replacement with a library (EnkiTS, TBB) is straightforward later.

UI specifics
- `UIComponent` interface: `onAttach`, `update(delta)`, `render(services, transform)`, `hitTest(point)`.
- `Screen` objects manage lifecycle (`enter`/`exit`), hold components, and are pushed/popped by `ScreenManager`.
- Input routing: `ScreenManager`/`InputRouter` receives events from `InputProvider`, does top-down z-ordered hit-testing for screen UI, then projects to world ray for diegetic UI.
- Hit-testing: components expose `hitTest` (point or ray); return `HitResult` with local point and component reference. Use AABB/sphere for fast rejects; allow pixel-perfect later.
- View-models: for app-like screens, bind to small view-models so UI code doesn't directly mutate simulation state.

Job system specifics
- Concrete runtime should start as a simple thread-pool + synchronized queue (reliable, easy to debug).
- Workers enqueue completion closures or result handles to the `MainThreadDispatcher`; main thread drains these each frame before UI update.
- Provide `JobCounter`/`join` primitives for simple dependencies; keep API stable so advanced features can be added later (work-stealing, priorities, futures).

Eventing
- Reuse engine `EventBus` via a `CoreAPI` protocol. UI emits `UIAction`/`UIEvent` types; systems subscribe to high-level UI events.
- Keep input consumption separate: low-level input consumption is synchronous and returns consumed flag; high-level UI events are posted on the bus.

Immediate next steps (recommended order)
1. Create `Sources/UI` skeleton (folders and placeholder files) and migrate existing UI files into it.
2. Add `Sources/CoreAPI/Services.swift` with the minimal protocol definitions.
3. Reorganize SwiftPM targets and overall project structure if needed (make `CoreAPI`, `UI`, and `Runtime` targets).
4. Scaffold a minimal `Runtime` `JobSystem` (thread-pool + completion queue) and `MainThreadDispatcher`, then wire them into `main.swift`.
5. Add `SDLInputProvider` in `Sources/Runtime` and replace direct SDL calls in UI with `InputProvider` usage.
6. Implement `ScreenManager` and a small `MainMenuScreen`/`Button` example.

Notes / tradeoffs
- Using the engine renderer for UI today keeps performance and feature access; decoupling can wait until there is a strong need.
- Start minimal but design clear extension points: pluggable job backend, small protocol surface for renderer/input/asset APIs.
- Keep everything main-thread safe where required and use the job system for heavy tasks (text shaping, atlas generation, layout, asset decoding).

If you'd like, I can scaffold items 1–3 now (CoreAPI stubs + UI skeleton + job system scaffold). Tell me which to scaffold first.
# DeckRPG — Project TODO

This file contains short-term project tasks tracked for UI reorganization and the job system.

## Current priorities

- [ ] Implement minimal `JobSystem` scaffold (thread-pool + completion queue)
- [ ] Add `MainThreadDispatcher` / completion queue and example wiring in `main.swift`
- [ ] Reorganize `Sources/UI` layout (Components, Screens, Diegetic) and move examples
- [ ] Wire `SDLInputProvider` with `InputProvider` protocol in `Sources/CoreAPI` and `Sources/Runtime`
- [ ] Offer small `ScreenManager` scaffold and example `MainMenuScreen`

## Notes / design decisions

- Keep UI on the main thread (SDL + windowing + final rendering + hit-testing).
- Job system should support: `enqueue(job)`, `enqueue(job, completion)`, `JobHandle`, and a `JobCounter` for dependencies.
- Design `JobSystem` behind a small protocol so backends (custom, EnkiTS, TBB) can be swapped later.
- UI should depend only on small `CoreAPI` protocols (`UIRenderer`, `InputProvider`, `AssetLoader`, `EventBus`, `TimeProvider`).
- Support both screen-space (overlay) and world-space (diegetic) UI using the same `UIComponent` API; difference is transform and hit-test context.

## Next steps (suggested order)

1. Scaffold minimal `JobSystem` + `MainThreadDispatcher` in `Sources/Runtime` and wire an example job posting back to main.
2. Add `Sources/CoreAPI/Services.swift` with the UI-facing protocols.
3. Create `Sources/UI` folders and add `ScreenManager.swift`, `Components/Button.swift`, and an example `Screens/MainMenuScreen.swift`.
4. Replace direct SDL/engine calls from UI components with the `CoreAPI` protocols and inject concrete implementations from `Runtime`.
5. Gradually offload expensive UI tasks (layout, text shaping, atlas generation) to the `JobSystem` and dispatch results via `MainThreadDispatcher`.