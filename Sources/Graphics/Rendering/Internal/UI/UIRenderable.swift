import Platform
import Core
import Foundation

import Core

/// Compatibility alias for older code that referenced `UIRenderable`.
///
/// Contract / lifecycle:
/// - `Renderable2D` is the canonical CPU-side renderable type. It stores per-element
///   vertex/index arrays, SDF/material parameters, and upload state.
/// - When a `Renderable2D` is uploaded to GPU buffers the renderer calls
///   `markUploaded(vertexOffset:indexOffset:)` to record buffer offsets. At that point
///   a `Mesh2D` may be constructed from the renderable for drawing.
/// - If 2D buffers are reset (e.g. on device/allocator reset), call `markNotUploaded()`
///   so the element is re-uploaded. Accessing GPU offsets before upload is invalid.
public typealias UIRenderable = Renderable2D