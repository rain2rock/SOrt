//
//  LiquidGlassShaderTypes.swift
//  Shared types for Liquid Glass Metal Shader
//

import Foundation
import simd

// MARK: - Shared Metal Types

struct LiquidGlassVertex {
    var position: SIMD2<Float>
    var texCoord: SIMD2<Float>
}

struct LiquidGlassUniforms {
    var time: Float
    var resolution: SIMD2<Float>
    var lightDirection: SIMD3<Float>
    var baseColor: SIMD4<Float>
    var refractionStrength: Float
    var depthStrength: Float
    var dispersionStrength: Float
    var frostStrength: Float
}
