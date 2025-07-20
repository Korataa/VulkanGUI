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

let graphics = Graphics(sdlContext: sdlContext)
let eventManager = EventManager(sdlContext)
let assetLoader = AssetLoader(resourceManager: graphics.resourceManager)

graphics.initialize()
if let loadedModel = assetLoader.loadModel(at: "Assets/Models/girl/scene.gltf") {
    let model = assetLoader.createModel(from: loadedModel)
    graphics.addModel(model: model)
    print("Model loaded successfully!")
} else {
    print("Failed to load model!")

//----------------------------------------GAME LOOP-----------------------------------------------------
while !quit {
    eventManager.pollEvents(shouldQuit: &quit)
    graphics.update()
}
}