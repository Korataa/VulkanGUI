import Core
import Foundation
import Graphics
import Math
import Platform
import UI

/// Information available to an optional per-frame callback.
public struct GUIFrame {
    public let graphics: Graphics
    public let ui: UIManager
    /// Number of successfully presented frames during this run.
    public let presentedFrames: Int
}

/// Runs a standalone GUI window. Call `run` on the main thread.
public final class GUIApplication {
    private let title: String
    private let width: Int
    private let height: Int
    private var running = false
    private var shouldQuit = false
    private var needsRefresh = false

    public init(title: String, width: Int = 800, height: Int = 600) {
        precondition(width > 0 && width <= Int(Int32.max), "Window width must be a positive Int32")
        precondition(height > 0 && height <= Int(Int32.max), "Window height must be a positive Int32")
        self.title = title
        self.width = width
        self.height = height
    }

    /// Request that the content closure be evaluated again on the next update.
    public func refresh() {
        needsRefresh = true
    }

    /// Close the application after the current callback returns.
    public func quit() {
        shouldQuit = true
    }

    /// Creates the window, runs the event loop, and releases its resources on exit.
    /// The optional frame callback runs after UI updates and before rendering,
    /// including while rendering is paused for a minimized window.
    public func run(onFrame: ((GUIFrame) -> Void)? = nil, content: () -> Element) {
        precondition(!running, "GUIApplication is already running")
        running = true
        shouldQuit = false
        needsRefresh = false

        let context = SDLContext()
        context.initialize()
        let window = Window(sdlContext: context)
        window.createWindow(title: title, width: width, height: height)
        let graphics = Graphics(sdlContext: context)
        graphics.initialize()
        defer {
            graphics.cleanup()
            window.cleanup()
            context.cleanup()
            running = false
        }

        let ui = UIManager(graphics: graphics)
        ui.setRoot(content())
        let events = EventManager(context)
        guard let handle = context.getWindowHandle() else {
            fatalError("SDL window is unavailable")
        }
        let input = SDLInputProvider(window: handle)
        var lastWidth: Int32 = 0
        var lastHeight: Int32 = 0
        var presentedFrames = 0

        while !shouldQuit {
            events.pollEvents(shouldQuit: &shouldQuit)
            if shouldQuit { break }
            input.update()
            ui.handleInput(input: input)
            if shouldQuit { break }

            var screenWidth: Int32 = 0
            var screenHeight: Int32 = 0
            context.getWindowSizeInPixels(width: &screenWidth, height: &screenHeight)
            if screenWidth > 0 && screenHeight > 0 &&
                (screenWidth != lastWidth || screenHeight != lastHeight) {
                ui.setScreenBounds(Rectangle(
                    position: Vector2(0, 0), width: Float(screenWidth), height: Float(screenHeight)
                ))
                lastWidth = screenWidth
                lastHeight = screenHeight
            }
            if needsRefresh {
                needsRefresh = false
                ui.setRoot(content())
            }
            if shouldQuit { break }
            ui.update()
            onFrame?(GUIFrame(graphics: graphics, ui: ui, presentedFrames: presentedFrames))
            if shouldQuit { break }
            if context.isWindowMinimized() || screenWidth <= 0 || screenHeight <= 0 {
                Thread.sleep(forTimeInterval: 0.016)
                continue
            }
            if graphics.createFrame() && graphics.presentFrameWithResult() {
                presentedFrames += 1
            }
        }
    }
}
