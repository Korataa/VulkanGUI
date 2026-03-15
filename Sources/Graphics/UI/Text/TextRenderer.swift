import Core
import Math

public struct TextRenderer {
	public let atlas: FontAtlas

	public init(atlas: FontAtlas) {
		self.atlas = atlas
	}

	/// Generate one renderable per glyph so each character can use atlas UV coordinates.
	public func measureTextWidth(_ text: String, scale: Float = 1.0) -> Float {
		var width: Float = 0.0
		for character in text {
			if character == "\n" { break }
			if let glyph = atlas.glyphs[character] {
				width += glyph.advance * scale
			} else {
				width += atlas.fontSize * 0.5 * scale
			}
		}
		return width
	}

	/// `topLeft.y` is treated as the baseline Y for glyph layout.
	public func buildGlyphRenderables(
		text: String,
		topLeft: SIMD2<Float>,
		color: Color,
		textureID: UInt32,
		scale: Float = 1.0,
		lineSpacing: Float = 1.0
	) -> [Renderable2D] {
		guard !text.isEmpty else { return [] }

		let scaledFontSize = atlas.fontSize * scale
		let lineAdvance = scaledFontSize * max(0.1, lineSpacing)

		var penX = topLeft.x
		var penY = topLeft.y
		var renderables: [Renderable2D] = []
		renderables.reserveCapacity(text.count)

		for character in text {
			if character == "\n" {
				penX = topLeft.x
				penY += lineAdvance
				continue
			}

			guard let glyph = atlas.glyphs[character] else {
				// Fallback advance for characters outside the atlas range.
				penX += atlas.fontSize * 0.5 * scale
				continue
			}

			if glyph.size.x <= 0 || glyph.size.y <= 0 {
				penX += glyph.advance * scale
				continue
			}

			let x0 = (penX + glyph.bearing.x * scale).rounded()
			let y0 = (penY + glyph.bearing.y * scale).rounded()
			let width = glyph.size.x * scale
			let height = glyph.size.y * scale
			let x1 = (x0 + width).rounded()
			let y1 = (y0 + height).rounded()

			let u0 = glyph.uvRect.position.x
			let v0 = glyph.uvRect.position.y
			let u1 = u0 + glyph.uvRect.width
			let v1 = v0 + glyph.uvRect.height

			let vertices = [
				Vertex2D(position: SIMD2(x0, y0), texCoord: SIMD2(u0, v0), color: color),
				Vertex2D(position: SIMD2(x1, y0), texCoord: SIMD2(u1, v0), color: color),
				Vertex2D(position: SIMD2(x1, y1), texCoord: SIMD2(u1, v1), color: color),
				Vertex2D(position: SIMD2(x0, y1), texCoord: SIMD2(u0, v1), color: color)
			]

			let center = SIMD2((x0 + x1) * 0.5, (y0 + y1) * 0.5)
			let size = SIMD2(width, height)
					let renderable = Renderable2D(
				position: center,
				size: size,
				color: color,
				textureID: textureID,
				usesSDF: true,
				vertices: vertices,
				indices: [0, 1, 2, 0, 2, 3]
			)
			renderables.append(renderable)

			penX += glyph.advance * scale
		}

		return renderables
	}
}

