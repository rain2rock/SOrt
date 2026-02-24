//
//  LiquidGlassExamples.swift
//  Usage Examples for Liquid Glass Shader
//

import SwiftUI

// MARK: - Example 1: Basic Liquid Glass Card

struct BasicLiquidGlassCard: View {
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [.blue, .purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Glass card
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundColor(.white)
                
                Text("Liquid Glass")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Physical glass simulation")
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(32)
            .background(
                MetalLiquidGlass(
                    baseColor: Color.white.opacity(0.15),
                    cornerRadius: 24
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }
}

// MARK: - Example 2: Glass Button

struct LiquidGlassButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    MetalLiquidGlass(
                        baseColor: Color.blue.opacity(0.2),
                        cornerRadius: 16
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Example 3: Glass Navigation Bar

struct LiquidGlassNavigationBar: View {
    var body: some View {
        HStack {
            Button(action: {}) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            
            Spacer()
            
            Text("Title")
                .font(.headline)
                .foregroundColor(.white)
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            MetalLiquidGlass(
                baseColor: Color.white.opacity(0.1),
                cornerRadius: 0
            )
        )
    }
}

// MARK: - Example 4: Glass Modal Sheet

struct LiquidGlassModal: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            // Modal content
            VStack(spacing: 24) {
                // Handle
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 6)
                
                Text("Glass Modal")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text("This modal uses the liquid glass shader for a premium iOS aesthetic.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal)
                
                Button("Close") {
                    isPresented = false
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(
                    MetalLiquidGlass(
                        baseColor: Color.white.opacity(0.2),
                        cornerRadius: 20
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .foregroundColor(.white)
            }
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
            .background(
                MetalLiquidGlass(
                    baseColor: Color.white.opacity(0.15),
                    cornerRadius: 24
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Example 5: Glass Control Panel

struct LiquidGlassControlPanel: View {
    @State private var volume: Double = 50
    @State private var brightness: Double = 75
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Controls")
                .font(.headline)
                .foregroundColor(.white)
            
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "speaker.wave.2")
                        .foregroundColor(.white)
                    Slider(value: $volume, in: 0...100)
                        .accentColor(.white)
                }
                
                HStack {
                    Image(systemName: "sun.max")
                        .foregroundColor(.white)
                    Slider(value: $brightness, in: 0...100)
                        .accentColor(.white)
                }
            }
        }
        .padding(24)
        .background(
            MetalLiquidGlass(
                baseColor: Color.white.opacity(0.12),
                cornerRadius: 20
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Example 6: Glass Tag/Badge

struct LiquidGlassBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                MetalLiquidGlass(
                    baseColor: color.opacity(0.3),
                    cornerRadius: 12
                )
            )
            .clipShape(Capsule())
    }
}

// MARK: - Example 7: Full Demo View

struct LiquidGlassDemoView: View {
    @State private var showModal = false
    
    var body: some View {
        ZStack {
            // Animated background
            AnimatedGradientBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    Text("Liquid Glass Showcase")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.top, 40)
                    
                    // Cards
                    BasicLiquidGlassCard()
                        .frame(height: 200)
                    
                    // Buttons
                    HStack(spacing: 12) {
                        LiquidGlassButton(title: "Primary") {}
                        LiquidGlassButton(title: "Secondary") {}
                    }
                    
                    // Control Panel
                    LiquidGlassControlPanel()
                    
                    // Badges
                    HStack(spacing: 8) {
                        LiquidGlassBadge(text: "New", color: .blue)
                        LiquidGlassBadge(text: "Featured", color: .purple)
                        LiquidGlassBadge(text: "Premium", color: .orange)
                    }
                    
                    // Show Modal Button
                    Button("Show Modal") {
                        withAnimation(.spring()) {
                            showModal = true
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 32)
                    .background(
                        MetalLiquidGlass(
                            baseColor: Color.green.opacity(0.2),
                            cornerRadius: 20
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
            }
            
            // Modal overlay
            if showModal {
                LiquidGlassModal(isPresented: $showModal)
            }
        }
    }
}

// MARK: - Animated Background Helper

struct AnimatedGradientBackground: View {
    @State private var animateGradient = false
    
    var body: some View {
        LinearGradient(
            colors: [
                animateGradient ? .blue : .purple,
                animateGradient ? .purple : .pink,
                animateGradient ? .pink : .blue
            ],
            startPoint: animateGradient ? .topLeading : .bottomTrailing,
            endPoint: animateGradient ? .bottomTrailing : .topLeading
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                animateGradient = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    LiquidGlassDemoView()
}
