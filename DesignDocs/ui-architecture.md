# UI Architecture Notes
- Decision: Keep components as author-facing API and `Element` as runtime/backend representation.
- Rule: Components describe intent; elements execute layout, hit-testing, event dispatch, and rendering.
- `UIManager` should process only `Element` trees, not specific component classes.
- `ButtonComponent.onClick` / hover callbacks should map into built element handlers (`tapHandler`, `onHoverStart`, `onHoverEnd`).
- Benefit: Component API stays stable even if internal element subtree changes.
- Watchout: preserve stable identity/state across rebuilds (keys/IDs) for hover/focus/text-input continuity.
