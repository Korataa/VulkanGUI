//let cameraDistance: Float = 10.0  // Back to reasonable distanceThe Swift Programming Language
// https://docs.swift.org/s// Camera orbit controls - Simple close position for debugging
var cameraDistance: Float = 5.0  // Much closer for debugging
var cameraAngleY: Float = 0.0      // Horizontal rotation (around Y axis)
var cameraAngleX: Float = 0.0      // Vertical rotation (pitch)
let cameraTarget = Vector3(0.0, 0.0, 0.0)
import CSDL3
import Foundation

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

// Test our new pipeline architecture
graphics.testPipelineCreation()

// Create ResourceSystem using graphics resource manager (high-level orchestrator)
let resourceSystem = ResourceSystem(graphicsResourceManager: graphics.resourceManager)

// Use ResourceSystem for all resource operations, not graphics.resourceManager directly
let assetLoader = AssetLoader(resourceManager: resourceSystem.graphicsResourceManager)

if let loadedModel = assetLoader.loadModel(at: "Assets/Models/Megaman/scene.gltf") {
    let model = assetLoader.createModel(from: loadedModel)
    
    // Set model to reasonable transform for viewing
    model.transform.position = Vector3(0.0, 0.0, 0.0)   // Center it at origin
    model.transform.rotation = Quaternion.identity()     // No rotation - face camera directly  
    model.transform.scale = Vector3(1.0, 1.0, 1.0)      // Normal size
    
    print("Model created with \(model.meshes.count) meshes, bounding sphere: \(model.boundingSphere)")
    print("Model transform: \(model.transform)")
    graphics.addModel(model: model)
    print("Model loaded successfully!")
    
    // Test UI elements - create some UI overlays using screen pixel coordinates
    print("Creating test UI elements...")
    
    // Create multiple UI elements positioned to not cover the center (where 3D model is)
    // Screen is 800x600, so avoid center area around (400, 300)
    // Using larger spacing to ensure no overlap
    
    // Red square in top-left corner
    let redSquare = graphics.createSprite(at: (80, 80), size: (60, 60), color: Color.red)
    graphics.addUIElement(redSquare)
    
    // Green square in top-right corner  
    let greenSquare = graphics.createSprite(at: (720, 80), size: (60, 60), color: Color.green)
    graphics.addUIElement(greenSquare)
    
    // White square in bottom-left corner (moved further down)
    let whiteSquare = graphics.createSprite(at: (80, 520), size: (60, 60), color: Color.white)
    graphics.addUIElement(whiteSquare)
    
    print("✅ UI elements created: \(graphics.uiElementCount) elements")
    
    // Now that textures are loaded, create Vulkan textures
    graphics.createTexturesFromResourceManager()
} else {
    print("Failed to load model!")
}

// Initialize camera for rendering - position camera to view entire model
// Model bounding sphere: center=(0,0,9.5), radius=14.9, extends from Z≈-5.4 to Z≈24.4

// Try different camera positions:
// Front view: position: Vector3(0.0, 0.0, -35.0)
// Back view: position: Vector3(0.0, 0.0, 35.0) 
// Side view: position: Vector3(35.0, 0.0, 9.5)
// Angled view: position: Vector3(20.0, 15.0, -20.0)

@MainActor
func updateCamera() {
    // Convert spherical coordinates to cartesian
    let x = cos(cameraAngleX) * sin(cameraAngleY) * cameraDistance
    let y = sin(cameraAngleX) * cameraDistance + cameraTarget.y
    let z = cos(cameraAngleX) * cos(cameraAngleY) * cameraDistance
    
    // Get correct aspect ratio from graphics system
    let aspectRatio = graphics.getAspectRatio()
    
    let camera = Camera(
        position: Vector3(x, y, z),
        target: cameraTarget,
        up: Vector3(0.0, 1.0, 0.0),
        fovY: 45.0,
        fovX: 0.0,  // Will be calculated from aspect ratio
        aspect: aspectRatio,  // Use actual window aspect ratio
        nearZ: 1.0,   // Use default near plane to avoid clipping issues
        farZ: 1000.0  // Large far plane to see distant objects
    )
    graphics.setCamera(camera)
}

// Initialize camera with better view
cameraDistance = 15.0  // Much further back
cameraAngleY = 0.0     // Look straight at model
cameraAngleX = 0.2     // Slight downward angle
updateCamera()
print("Camera orbit controls: WASD to rotate, QE to zoom, R to reset")
print("Current angle Y: \(cameraAngleY), angle X: \(cameraAngleX), distance: \(cameraDistance)")

//----------------------------------------GAME LOOP-----------------------------------------------------
while !quit {
    eventManager.pollEvents(shouldQuit: &quit)
    
    // Camera controls
    guard let keyboardState = SDL_GetKeyboardState(nil) else { continue }
    var cameraChanged = false
    
    if keyboardState[Int(SDL_SCANCODE_A.rawValue)] {
        cameraAngleY -= 0.005  // Rotate left (much slower)
        cameraChanged = true
    }
    if keyboardState[Int(SDL_SCANCODE_D.rawValue)] {
        cameraAngleY += 0.005  // Rotate right (much slower)
        cameraChanged = true
    }
    if keyboardState[Int(SDL_SCANCODE_W.rawValue)] {
        cameraAngleX += 0.005  // Rotate up (much slower)
        // Clamp vertical angle to prevent weird stretching
        if cameraAngleX > 1.4 { cameraAngleX = 1.4 }  // About 80 degrees max
        cameraChanged = true
    }
    if keyboardState[Int(SDL_SCANCODE_S.rawValue)] {
        cameraAngleX -= 0.005  // Rotate down (much slower)
        // Clamp vertical angle to prevent weird stretching
        if cameraAngleX < -1.4 { cameraAngleX = -1.4 }  // About -80 degrees min
        cameraChanged = true
    }
    if keyboardState[Int(SDL_SCANCODE_Q.rawValue)] {
        cameraDistance -= 0.1  // Zoom in (much slower)
        if cameraDistance < 5.0 { cameraDistance = 5.0 }
        cameraChanged = true
    }
    if keyboardState[Int(SDL_SCANCODE_E.rawValue)] {
        cameraDistance += 0.1  // Zoom out (much slower)
        cameraChanged = true
    }
    if keyboardState[Int(SDL_SCANCODE_R.rawValue)] {
        // Reset camera
        cameraAngleY = 0.0
        cameraAngleX = 0.0
        cameraDistance = 10.0
        cameraChanged = true
        print("Camera reset")
    }
    
    if cameraChanged {
        updateCamera()
        
        // Debug: Show camera position when it changes
        let x = cos(cameraAngleX) * sin(cameraAngleY) * cameraDistance
        let y = sin(cameraAngleX) * cameraDistance + cameraTarget.y
        let z = cos(cameraAngleX) * cos(cameraAngleY) * cameraDistance
        print("Camera moved to: (\(x), \(y), \(z)), looking at: \(cameraTarget), distance: \(cameraDistance)")
    }
    
    // Use the new input-latency optimized frame management
    if graphics.createFrame() {
        // Frame is ready for rendering
        
        // TODO: Add proper input polling here for minimal input lag
        // For now, input is already processed above
        
        // Present the frame
        graphics.presentFrame()
    }
}

// Cleanup after main loop
print("🧹 Starting cleanup...")
graphics.cleanup()
print("✅ Cleanup completed")