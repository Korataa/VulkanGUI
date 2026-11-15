# DeckRPGUI

An in-progress Swift GUI foundation using SDL3 for windows and input and Vulkan
for 2D and UI rendering. The Swift package exposes the `DeckRPGUI` library.
The former game, editor, glTF loader, and model rendering path have been removed.
Existing UI, font, image, and 2D resource handling remain.

## Build and run

Install Swift 6, SDL3, and the Vulkan SDK. On Windows the package uses
`VULKAN_SDK` and `VCPKG_ROOT` when set; otherwise it expects Vulkan SDK
`C:\VulkanSDK\1.4.341.1` and SDL3 at
`C:\vcpkg\installed\x64-windows`. SDL3's DLL must be on `PATH`.

From the repository root:

```powershell
swift build
swift run GUIExample
```

## Create an application

Your app can be a separate Swift package. For example, if its directory sits
beside this `DeckRPG` directory, add the library to its `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyApp",
    dependencies: [.package(path: "../DeckRPG")],
    targets: [
        .executableTarget(
            name: "MyApp",
            dependencies: [.product(name: "DeckRPGUI", package: "DeckRPG")]
        )
    ]
)
```

Put your app code in `Sources/MyApp/main.swift` in that package. The package
name in the product dependency matches the library directory's name.

The application runner owns the window, input, event loop, rendering, and
cleanup. Run it on the main thread:

```swift
import DeckRPGUI

let app = GUIApplication(title: "My App")
let count = Reactive(0)

app.run {
    Column {
        Dynamic {
            Text("Count: \(count.value)")
        }
        Button("Increment") {
            count.value += 1
        }
    }.padding(20)
}
```

`Dynamic` tracks the `Reactive` values read while its closure builds the
region. Assigning `count.value` updates that region automatically, without
rebuilding unrelated regions. Changes that affect layout also update the
necessary descendants. A text element can alternatively use
`Text().bind(count) { "Count: \($0)" }`. Read and change UI-bound reactive
values on the main thread. For a `Reactive` holding a reference type, assign
`value` after changing it to notify the UI.

Ordinary variables and reactive values read outside a `Dynamic` region are not
tracked. Call `app.refresh()` to reevaluate the whole content closure when
using those values. Call `quit()` to close the application from a callback.
An optional `onFrame` callback gives advanced applications access to
the UI and graphics objects after each UI update and before rendering;
its `presentedFrames` counts successful presentations. Rendering pauses while
the window is minimized, but the callback continues to run. These objects
should not be used after `run` returns.
The lower-level APIs remain available for applications that manage their own
window and event loop.

The example closes normally via its window. Use `swift run GUIExample --smoke`
to render three frames and exit, or `--buffer-growth-smoke` to exercise buffer
growth as well.

UI elements can be moved and resized with `updateTransform`, recolored by
setting `color`, and given a different `textureID` at runtime. Rebuild the UI
with `setRoot` or `markNeedsRebuild` after changing its contents. The projection
updates automatically as the window size changes; applications do not need to
provide matrices. UI regions are updated incrementally on the CPU; when geometry
changes, the renderer currently repacks and uploads the UI buffers.

The resource manager starts with 1 MiB of vertex buffers, 256 KiB of index
buffers and a 256 KiB staging buffer. These grow when the UI needs more space,
instead of scaling with total VRAM. Vulkan allocator blocks, swapchain images,
textures and other GPU resources use additional memory.

The renderer currently loads compiled shaders and fonts from an asset directory,
not from a Swift package resource bundle. Run from the repository root with its
`config.json`, or set `DECKRPGUI_ASSETS` to the absolute path of the `Assets`
directory before running an application. The `Shaders` and `Fonts` subdirectories
must be present. Recompile shaders with the scripts in `Assets/Shaders` when
changing shader sources.

## Status

The library and example have been built and smoke-tested on Windows. Linux and
macOS support is a goal, not yet validated; their SDL3/Vulkan dependency and
runtime setup needs verification. UI batches preserve draw order and use
independent material state. The 2D pipeline uses its own projection and
material descriptors; the renderer no longer contains 3D camera, lighting,
or PBR resources. The low-level `Graphics2D` pipeline currently binds a default
material; use the UI sprite path for per-element colors and textures.
