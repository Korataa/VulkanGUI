import XCTest
import Foundation
import DeckRPGUI
import CSDL3

final class GUIApplicationTests: XCTestCase {
    func testReactiveContentUpdatesWithoutRefresh() throws {
        guard ProcessInfo.processInfo.environment["DECKRPGUI_GPU_TESTS"] == "1" else {
            throw XCTSkip("Set DECKRPGUI_GPU_TESTS=1 to run Vulkan integration tests")
        }

        let app = GUIApplication(title: "Reactive test", width: 320, height: 240)
        let state = Reactive(0)
        var rootBuilds = 0
        var regionBuilds = 0
        var firstElementCount = 0
        var checkedFinalUpdate = false
        app.run(onFrame: { frame in
            if frame.presentedFrames == 0 && state.value == 0 {
                firstElementCount = frame.graphics.uiElementCount
                frame.graphics.addUIElement(frame.graphics.createSprite(at: (10, 10), size: (5, 5)))
                state.value = 1
            } else if frame.presentedFrames == 1 && state.value == 1 {
                XCTAssertEqual(rootBuilds, 1)
                XCTAssertEqual(regionBuilds, 2)
                XCTAssertEqual(frame.graphics.uiElementCount, firstElementCount + 1)
                state.value = 2
            } else if frame.presentedFrames == 2 && !checkedFinalUpdate {
                XCTAssertEqual(rootBuilds, 1)
                XCTAssertEqual(regionBuilds, 3)
                XCTAssertGreaterThan(frame.graphics.uiElementCount, firstElementCount + 1)
                checkedFinalUpdate = true
            } else if frame.presentedFrames == 3 {
                app.quit()
            }
        }) {
            rootBuilds += 1
            return Column {
                Dynamic {
                    regionBuilds += 1
                    return Text(state.value == 0 ? "A" : (state.value == 1 ? "C" : "Longer text"))
                }
                Text().bind(state) { $0 == 0 ? "B" : ($0 == 1 ? "D" : "More bound text") }
            }
        }
        XCTAssertEqual(regionBuilds, 3)
        XCTAssertTrue(checkedFinalUpdate)
    }

    func testRunnerRefreshesContentAndCanRunAgain() throws {
        guard ProcessInfo.processInfo.environment["DECKRPGUI_GPU_TESTS"] == "1" else {
            throw XCTSkip("Set DECKRPGUI_GPU_TESTS=1 to run Vulkan integration tests")
        }

        let app = GUIApplication(title: "Application test", width: 320, height: 240)
        var state = 0
        var builds = 0
        var frames: [Int] = []
        var firstElementCount = 0
        app.run(onFrame: { frame in
            if frames.last != frame.presentedFrames { frames.append(frame.presentedFrames) }
            if frame.presentedFrames == 0 && state == 0 {
                firstElementCount = frame.graphics.uiElementCount
                state = 1
                app.refresh()
            } else if frame.presentedFrames == 1 {
                XCTAssertEqual(builds, 2)
                XCTAssertGreaterThan(frame.graphics.uiElementCount, firstElementCount)
                app.quit()
            }
        }) {
            builds += 1
            return Text(state == 0 ? "One" : "Longer text")
        }
        XCTAssertEqual(frames, [0, 1])
        XCTAssertEqual(builds, 2)

        var secondRunFrames: [Int] = []
        app.run(onFrame: { frame in
            if secondRunFrames.last != frame.presentedFrames {
                secondRunFrames.append(frame.presentedFrames)
            }
            if frame.presentedFrames == 1 { app.quit() }
        }) {
            Text("Second run")
        }
        XCTAssertEqual(secondRunFrames, [0, 1])

        var refreshBuilds = 0
        var callbackCount = 0
        app.run(onFrame: { _ in
            callbackCount += 1
            app.refresh()
        }) {
            refreshBuilds += 1
            if refreshBuilds == 2 { app.quit() }
            return Text("Quit during refresh")
        }
        XCTAssertEqual(refreshBuilds, 2)
        XCTAssertEqual(callbackCount, 1)
    }

    func testRunnerPausesRenderingWhenMinimizedAndHandlesQuitEvent() throws {
        guard ProcessInfo.processInfo.environment["DECKRPGUI_GPU_TESTS"] == "1" else {
            throw XCTSkip("Set DECKRPGUI_GPU_TESTS=1 to run Vulkan integration tests")
        }

        let app = GUIApplication(title: "Event test", width: 320, height: 240)
        var phase = 0
        var framesWhenMinimized = 0
        app.run(onFrame: { frame in
            var event = SDL_Event()
            switch phase {
            case 0:
                event.type = UInt32(SDL_EVENT_WINDOW_MINIMIZED.rawValue)
            case 1:
                framesWhenMinimized = frame.presentedFrames
                event.type = UInt32(SDL_EVENT_WINDOW_RESTORED.rawValue)
            case 2:
                XCTAssertEqual(frame.presentedFrames, framesWhenMinimized)
                event.type = UInt32(SDL_EVENT_QUIT.rawValue)
            default:
                XCTFail("Callback was invoked after the quit event")
                app.quit()
                return
            }
            phase += 1
            XCTAssertTrue(SDL_PushEvent(&event))
        }) {
            Text("Window events")
        }
        XCTAssertEqual(phase, 3)
    }
}
