//
//  LiquidGlassBackgroundCapture.swift
//  Background Capture for Liquid Glass Effect
//

import SwiftUI
import UIKit
import Metal
import MetalKit
import CoreMotion
import simd

// MARK: - Background Capture Modifier

struct LiquidGlassBackgroundModifier: ViewModifier {
    let baseColor: Color
    let cornerRadius: CGFloat
    
    @State private var backgroundImage: UIImage?
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            captureBackground(size: geometry.size)
                        }
                }
            )
            .overlay(
                MetalLiquidGlassWithBackground(
                    baseColor: baseColor,
                    cornerRadius: cornerRadius,
                    backgroundImage: backgroundImage
                )
            )
    }
    
    private func captureBackground(size: CGSize) {
        // Capture will happen in next frame
        DispatchQueue.main.async {
            if let window = UIApplication.shared.windows.first {
                UIGraphicsBeginImageContextWithOptions(size, false, 0)
                window.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
                backgroundImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
            }
        }
    }
}

extension View {
    func liquidGlassEffect(baseColor: Color, cornerRadius: CGFloat = 24) -> some View {
        modifier(LiquidGlassBackgroundModifier(baseColor: baseColor, cornerRadius: cornerRadius))
    }
}

// MARK: - Metal View with Background Image

struct MetalLiquidGlassWithBackground: View {
    let baseColor: Color
    let cornerRadius: CGFloat
    let backgroundImage: UIImage?
    
    var body: some View {
        if let backgroundImage = backgroundImage {
            MetalLiquidGlassViewWithTexture(
                baseColor: baseColor,
                cornerRadius: cornerRadius,
                backgroundImage: backgroundImage
            )
        } else {
            // Fallback while capturing
            LiquidGlassBackground(baseColor: baseColor)
        }
    }
}

// MARK: - Enhanced Metal View with Texture Support

struct MetalLiquidGlassViewWithTexture: UIViewRepresentable {
    let baseColor: Color
    let cornerRadius: CGFloat
    let backgroundImage: UIImage
    
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
        
        context.coordinator.setupMetal(view: view, baseColor: baseColor, backgroundImage: backgroundImage)
        return view
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.updateBaseColor(baseColor)
        context.coordinator.updateBackgroundImage(backgroundImage)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var pipelineState: MTLRenderPipelineState!
        var vertexBuffer: MTLBuffer!
        var uniformBuffer: MTLBuffer!
        
        var startTime: CFTimeInterval = CACurrentMediaTime()
        var baseColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 0.15)
        
        let motionManager = CMMotionManager()
        var lightDirection: SIMD3<Float> = SIMD3<Float>(0, 0, 1)
        
        var backgroundTexture: MTLTexture?
        var textureLoader: MTKTextureLoader?
        
        func setupMetal(view: MTKView, baseColor: Color, backgroundImage: UIImage) {
            guard let device = view.device else { return }
            self.device = device
            
            // Convert color
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
            
            commandQueue = device.makeCommandQueue()
            textureLoader = MTKTextureLoader(device: device)
            
            // Setup vertex buffer
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
            
            uniformBuffer = device.makeBuffer(
                length: MemoryLayout<LiquidGlassUniforms>.stride,
                options: [MTLResourceOptions.storageModeShared]
            )
            
            setupPipeline(view: view)
            setupAccelerometer()
            loadBackgroundTexture(backgroundImage)
        }
        
        func setupPipeline(view: MTKView) {
            guard let library = device.makeDefaultLibrary() else { return }
            
            let vertexFunction = library.makeFunction(name: "liquidGlassVertex")
            let fragmentFunction = library.makeFunction(name: "liquidGlassFragment")
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
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
                print("Pipeline error: \(error)")
            }
        }
        
        func setupAccelerometer() {
            guard motionManager.isAccelerometerAvailable else { return }
            
            motionManager.accelerometerUpdateInterval = 1.0 / 60.0
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let data = data else { return }
                let x = Float(data.acceleration.x)
                let y = Float(data.acceleration.y)
                let z = Float(data.acceleration.z)
                let vector = SIMD3<Float>(-x, -y, z)
                let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
                if length > 0 {
                    self?.lightDirection = vector / length
                }
            }
        }
        
        func loadBackgroundTexture(_ image: UIImage) {
            guard let cgImage = image.cgImage else { return }
            
            do {
                backgroundTexture = try textureLoader?.newTexture(cgImage: cgImage, options: [
                    MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                    MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue)
                ])
            } catch {
                print("Texture loading error: \(error)")
            }
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
        
        func updateBackgroundImage(_ image: UIImage) {
            loadBackgroundTexture(image)
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let pipelineState = pipelineState,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let renderPassDescriptor = view.currentRenderPassDescriptor else {
                return
            }
            
            let currentTime = Float(CACurrentMediaTime() - startTime)
            var uniforms = LiquidGlassUniforms(
                time: currentTime,
                resolution: SIMD2<Float>(Float(view.drawableSize.width), 
                                        Float(view.drawableSize.height)),
                lightDirection: lightDirection,
                baseColor: baseColor,
                refractionStrength: 100.0,
                depthStrength: 41.0,
                dispersionStrength: 55.0,
                frostStrength: 43.0
            )
            
            let uniformBufferPointer = uniformBuffer.contents()
            uniformBufferPointer.copyMemory(from: &uniforms, byteCount: MemoryLayout<LiquidGlassUniforms>.stride)
            
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
                red: 0, green: 0, blue: 0, alpha: 0
            )
            
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor
            ) else { return }
            
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
            
            if let backgroundTexture = backgroundTexture {
                renderEncoder.setFragmentTexture(backgroundTexture, index: 0)
            }
            
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
