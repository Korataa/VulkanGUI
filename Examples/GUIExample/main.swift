import DeckRPGUI
import Foundation

let app = GUIApplication(title: "GUI Example", width: 800, height: 600)
let clickCount = Reactive(0)
let bufferGrowthSmoke = CommandLine.arguments.contains("--buffer-growth-smoke")
let smokeTest = CommandLine.arguments.contains("--smoke") || bufferGrowthSmoke
var addedSmokeSprites = false
var animatedSmokeSprite: Renderable2D?
var checkedFirstFrame = false

app.run(onFrame: { frame in
    guard smokeTest else { return }
    if !addedSmokeSprites {
        guard let red = frame.graphics.createUITextureRGBA(width: 1, height: 1, pixels: [255, 0, 0, 255]),
              let green = frame.graphics.createUITextureRGBA(width: 1, height: 1, pixels: [0, 255, 0, 255]) else {
            fatalError("Failed to create smoke-test textures")
        }
        let sprite = frame.graphics.createSprite(at: (100, 100), size: (40, 40), color: .blue)
        frame.graphics.addUIElement(sprite)
        animatedSmokeSprite = sprite
        frame.graphics.addUIElement(frame.graphics.createSprite(at: (160, 100), size: (40, 40), textureID: red))
        frame.graphics.addUIElement(frame.graphics.createSprite(at: (220, 100), size: (40, 40), textureID: green))
        frame.graphics.addUIElement(frame.graphics.createSprite(at: (280, 100), size: (40, 40), textureID: red))
        if bufferGrowthSmoke {
            let large = frame.graphics.createSprite(at: (0, 0), size: (1, 1))
            large.vertices = Array(repeating: large.vertices[0], count: 23_000)
            large.indices = Array(repeating: 0, count: 66_000)
            frame.graphics.addUIElement(large)
        }
        addedSmokeSprites = true
    }
    if frame.presentedFrames == 1 && !checkedFirstFrame {
        animatedSmokeSprite?.updateTransform(position: SIMD2(120, 120), size: SIMD2(50, 50))
        animatedSmokeSprite?.color = .green
        if bufferGrowthSmoke {
            guard let vertexSize = frame.graphics.resourceManager.vertex2DBuffer?.size,
                  let indexSize = frame.graphics.resourceManager.index2DBuffer?.size,
                  let transferSize = frame.graphics.resourceManager.transferBuffer?.size,
                  vertexSize > 1024 * 1024, indexSize > 256 * 1024, transferSize > 256 * 1024 else {
                fatalError("UI buffers did not grow for the large geometry upload")
            }
            print("UI buffers grew for the large geometry upload")
        }
        checkedFirstFrame = true
    }
    if frame.presentedFrames == 3 {
        print("GUI smoke test presented \(frame.presentedFrames) frames")
        app.quit()
    }
}) {
    Column(spacing: 16) {
        Dynamic {
            Text("Clicked \(clickCount.value) times")
        }
        Button("Click me") {
            clickCount.value += 1
        }
    }.padding(20)
}
