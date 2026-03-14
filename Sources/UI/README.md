UI module structure

- `ScreenManager.swift` — top-level screen push/pop manager
- `Screens/` — place for concrete screen implementations (MainMenu, HUD, Settings)
- `Components/` — reusable UI components (Button, Label, Panel)
- `Diegetic/` — helpers for world-space UI widgets
- `Core/` — current UI core helpers (existing files moved here)

Keep UI code dependent only on `CoreAPI` protocol types. Runtime will inject concrete implementations.
