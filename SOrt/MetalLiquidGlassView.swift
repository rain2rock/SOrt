//
//  MetalLiquidGlassView.swift
//  Metal-based Liquid Glass Implementation
//

import SwiftUI
import Metal
import MetalKit
import CoreMotion
import simd

// MARK: - Metal Liquid Glass View

struct MetalLiquidGlassView: UIViewRepresentable {
    let baseColor: Color
    let cornerRadius: CGFloat
    
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.isOpaque = false
        view.layer.cornerRadius = cornerRadius
        view.layer.masksToBounds = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        
        context.coordinator.setupMetal(view: view, baseColor: baseColor)
        return view
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.updateBaseColor(baseColor)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, MTKViewDelegate {
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var pipelineState: MTLRenderPipelineState!
        var vertexBuffer: MTLBuffer!
        var uniformBuffer: MTLBuffer!
        
        var startTime: CFTimeInterval = CACurrentMediaTime()
        var baseColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 0.15)
        
        // Motion manager for accelerometer
        let motionManager = CMMotionManager()
        var lightDirection: SIMD3<Float> = SIMD3<Float>(0, 0, 1)
        
        // Render target texture
        var backgroundTexture: MTLTexture?
        
        func setupMetal(view: MTKView, baseColor: Color) {
            guard let device = view.device else { return }
            self.device = device
            
            // Convert SwiftUI Color to SIMD4
            let uiColor = UIColor(baseColor)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            self.baseColor = SIMD4<Float>(
                Float(red),
                Float(green),
                Float(blue),
                Float(alpha)
            )
            
            // Create command queue
            commandQueue = device.makeCommandQueue()
            
            // Setup vertex buffer (full screen quad)
            let vertices: [LiquidGlassVertex] = [
                LiquidGlassVertex(position: SIMD2<Float>(-1, -1), texCoord: SIMD2<Float>(0, 1)),
                LiquidGlassVertex(position: SIMD2<Float>( 1, -1), texCoord: SIMD2<Float>(1, 1)),
                LiquidGlassVertex(position: SIMD2<Float>(-1,  1), texCoord: SIMD2<Float>(0, 0)),
                LiquidGlassVertex(position: SIMD2<Float>( 1,  1), texCoord: SIMD2<Float>(1, 0))
            ]
            vertexBuffer = device.makeBuffer(
                bytes: vertices,
                length: MemoryLayout<LiquidGlassVertex>.stride * vertices.count,
                options: []
            )
            
            // Create uniform buffer
            uniformBuffer = device.makeBuffer(
                length: MemoryLayout<LiquidGlassUniforms>.stride,
                options: [MTLResourceOptions.storageModeShared]
            )
            
            // Setup pipeline
            setupPipeline(view: view)
            
            // Setup accelerometer
            setupAccelerometer()
            
            // Create background texture
            createBackgroundTexture(view: view)
        }
        
        func setupPipeline(view: MTKView) {
            guard let library = device.makeDefaultLibrary() else {
                print("Failed to create Metal library")
                return
            }
            
            let vertexFunction = library.makeFunction(name: "liquidGlassVertex")
            let fragmentFunction = library.makeFunction(name: "liquidGlassFragment")
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            
            // Enable blending for transparency
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            
            do {
                pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            } catch {
                print("Failed to create pipeline state: \(error)")
            }
        }
        
        func setupAccelerometer() {
            guard motionManager.isAccelerometerAvailable else { return }
            
            motionManager.accelerometerUpdateInterval = 1.0 / 60.0
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
                guard let data = data else { return }
                
                // Convert accelerometer data to light direction
                let x = Float(data.acceleration.x)
                let y = Float(data.acceleration.y)
                let z = Float(data.acceleration.z)
                
                // Normalize and invert for natural lighting
                let vector = SIMD3<Float>(-x, -y, z)
                let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
                if length > 0 {
                    self?.lightDirection = vector / length
                }
            }
        }
        
        func createBackgroundTexture(view: MTKView) {
            let width = Int(view.drawableSize.width)
            let height = Int(view.drawableSize.height)
            
            guard width > 0, height > 0 else { return }
            
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            textureDescriptor.usage = [.shaderRead, .renderTarget]
            
            backgroundTexture = device.makeTexture(descriptor: textureDescriptor)
            
            // Fill with captured background (for now, transparent)
            // In production, you would capture the actual background here
        }
        
        func updateBaseColor(_ color: Color) {
            let uiColor = UIColor(color)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            self.baseColor = SIMD4<Float>(
                Float(red),
                Float(green),
                Float(blue),
                Float(alpha)
            )
        }
        
        // MARK: - MTKViewDelegate
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            createBackgroundTexture(view: view)
        }
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let pipelineState = pipelineState,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let renderPassDescriptor = view.currentRenderPassDescriptor else {
                return
            }
            
            // Update uniforms
            let currentTime = Float(CACurrentMediaTime() - startTime)
            var uniforms = LiquidGlassUniforms(
                time: currentTime,
                resolution: SIMD2<Float>(Float(view.drawableSize.width), 
                                        Float(view.drawableSize.height)),
                lightDirection: lightDirection,
                baseColor: baseColor,
                refractionStrength: 100.0,  // Full refraction
                depthStrength: 41.0,        // Moderate depth
                dispersionStrength: 55.0,   // Moderate dispersion
                frostStrength: 43.0         // Moderate frost
            )
            
            let uniformBufferPointer = uniformBuffer.contents()
            uniformBufferPointer.copyMemory(from: &uniforms, byteCount: MemoryLayout<LiquidGlassUniforms>.stride)
            
            // Setup render pass
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
                red: 0, green: 0, blue: 0, alpha: 0
            )
            
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor
            ) else { return }
            
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
            
            // Set background texture
            if let backgroundTexture = backgroundTexture {
                renderEncoder.setFragmentTexture(backgroundTexture, index: 0)
            }
            
            // Draw full screen quad
            renderEncoder.drawPrimitives(type: MTLPrimitiveType.triangleStrip, vertexStart: 0, vertexCount: 4)
            renderEncoder.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        
        deinit {
            motionManager.stopAccelerometerUpdates()
        }
    }
}

