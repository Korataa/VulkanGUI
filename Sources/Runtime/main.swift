// The Swift Programming Language
// https://docs.swift.org/swift-book
import CSDL3

import Modules

var quit: Bool = false

//------------------------------SDLCONTEXT INITIALIZE BECASUE EVERYTHING RELIES ON IT--------------------------------
let sdlContext = SDLContext()
sdlContext.initialize()

//----------------------------------------Create window next-----------------------------------------------------

let window = Window(sdlContext: sdlContext)
window.createWindow(title: "CardRPG", width: 800, height: 600)

//----------------------------------------Init subsystems here-----------------------------------------------------

// Create event manager for input handling
let eventManager = EventManager(sdlContext)

// Create VulkanRenderer to get device and allocator

// Create Graphics, which now owns and creates its GraphicsResourceManager
let graphics = Graphics(sdlContext: sdlContext)
graphics.initialize()

// Create ResourceSystem using graphics resource manager (high-level orchestrator)
let resourceSystem = ResourceSystem(graphicsResourceManager: graphics.resourceManager)

// Use ResourceSystem for all resource operations, not graphics.resourceManager directly
let assetLoader = AssetLoader(resourceManager: resourceSystem.graphicsResourceManager)

if let loadedModel = assetLoader.loadModel(at: "Assets/Models/girl/scene.gltf") {
    let model = assetLoader.createModel(from: loadedModel)
    
    // Keep model in its original orientation (no rotation)
    // model.transform.rotation = Quaternion.identity()  // This is already the default
    
    // Keep original scale
    model.transform.scale = Vector3(1.0, 1.0, 1.0)
    
    print("Model created with \(model.meshes.count) meshes, bounding sphere: \(model.boundingSphere)")
    print("Model transform: \(model.transform)")
    graphics.addModel(model: model)
    print("Model loaded successfully!")
} else {
    print("Failed to load model!")
}

// Initialize camera for rendering - position camera to view entire model
// Model bounding sphere: center=(0,0,9.5), radius=14.9, extends from Z≈-5.4 to Z≈24.4
let camera = Camera(
    position: Vector3(0.0, 0.0, 35.0),  // Far back to see entire model
    target: Vector3(0.0, 0.0, 9.5),     // Look at model center
    up: Vector3(0.0, 1.0, 0.0)          // Standard up vector
)
print("Camera created: \(camera)")
graphics.setCamera(camera)

//----------------------------------------GAME LOOP-----------------------------------------------------
while !quit {
    eventManager.pollEvents(shouldQuit: &quit)
    graphics.update()
}