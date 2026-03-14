# Project TODO — Game-First UI

This file captures the immediate, actionable work to implement a game-first UI for DeckRPG.

Priority 1 — Core (minimal, run-first)
- [ ] Add `Sources/CoreAPI/Services.swift` with protocol stubs: `UIRenderer`, `InputProvider`, `AssetLoader`, `JobSystem`, `MainThreadDispatcher`.
- [ ] Implement retained UI system: `UIComponent`, `UIElement`, `Screen`, `ScreenManager` under `Sources/UI/Core/`.
- [ ] Add `Sources/UI/Components/HealthBarComponent.swift` (pooled, lightweight) and `Sources/UI/Screens/GameHUD.swift`.

Priority 2 — Game integration
- [ ] Create `Sources/Game/Inventory/InventorySystem.swift` API (if missing) and `Sources/Game/Events/EventBus.swift` (or wire to existing event system).
- [ ] Add `Sources/UI/ViewModels/InventoryViewModel.swift` as an adapter for menu usage.
- [ ] Add `Sources/UI/Components/InventoryPanel.swift` using virtualization (render visible range only).
- [ ] Implement `Sources/Runtime/DiegeticWidgetAdapter.swift` to map entity transforms → UI transforms.

Priority 3 — Performance & tooling
- [ ] MSDF / atlas integration review (Assets/Fonts, generate-msdf tools); ensure `GraphicsResourceManager` supports SDF atlases.
- [ ] UI pooling and layout cache (dirty flags) for high-frequency HUD updates.
- [ ] JobSystem tasks: thumbnail/asset generation, texture atlas building; marshal results via `MainThreadDispatcher`.

Priority 4 — UX, polish, and examples
- [ ] Build small example levels showing: HUD (health/score), inventory menu, diegetic label on an entity.
- [ ] Add `Sources/UI/Examples/GameFirstHUD/README.md` describing how to run the example.

Notes & constraints
- Keep UI read-only over game state: UI components may query game state or subscribe to events but must not contain simulation logic.
- Menus may use lightweight `ViewModel`s for form-like interactions; prefer polling components for HUDs for lower latency.
- No immediate-mode UI — retained-only approach for gameplay and menus.

Next steps (short-term)
1. Create `Sources/CoreAPI/Services.swift` and `Sources/UI/Core/UIComponent.swift` skeletons.
2. Scaffold `HealthBarComponent.swift` and `GameHUD.swift` under `Sources/UI/Examples/GameFirstHUD/`.
3. Re-run `swift build` and iterate on compiler errors.

If you'd like, I can scaffold items 1–2 now and run a build to verify. Otherwise I saved this for you to pick up later.
