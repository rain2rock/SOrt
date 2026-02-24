# Liquid Glass Metal Shader

Physically-plausible liquid glass shader for iOS using Metal.

## Features

### 1. **Refraction (Strength: 100)** 🔮
- Strong UV displacement based on surface normal
- Radial distortion from center
- Non-linear falloff using smoothstep
- Edge blending for seamless integration

### 2. **Depth/Parallax (Strength: 41)** 📏
- Simulates glass thickness (0.12 units)
- Background offset proportional to virtual thickness
- Subtle vertical bias for light volume simulation
- Distance-based depth scaling

### 3. **Chromatic Dispersion (Strength: 55)** 🌈
- RGB channels sampled at different UV offsets
- Dispersion increases toward edges
- Subtle effect (not glitch-like)
- Radial direction for natural look

### 4. **Frost Effect (Strength: 43)** ❄️
- Micro-surface roughness simulation
- Multi-octave noise for realistic texture
- Gaussian-like blur (5 samples)
- Modulated by surface curvature

### 5. **Dynamic Lighting** 💡
- Accelerometer-based light direction
- Diffuse + Specular + Rim lighting
- Premium iOS glass aesthetic
- Real-time response to device orientation

## Technical Details

### Performance
- **Fragment shader only** - No vertex manipulation
- **Optimized for iOS GPU** - Uses float precision
- **Minimal branching** - Conditional logic avoided
- **60 FPS target** - Efficient sampling strategies

### Shader Parameters

```swift
struct Uniforms {
    var time: Float                    // Animation time
    var resolution: SIMD2<Float>       // Screen resolution
    var lightDirection: SIMD3<Float>   // From accelerometer
    var baseColor: SIMD4<Float>        // Glass tint
    var refractionStrength: Float      // 0-100 (default: 100)
    var depthStrength: Float           // 0-100 (default: 41)
    var dispersionStrength: Float      // 0-100 (default: 55)
    var frostStrength: Float           // 0-100 (default: 43)
}
```

### Optical Properties

#### Refraction Index
- Simulates optical glass (n ≈ 1.5)
- Stronger at edges, subtle at center
- Smooth transitions with smoothstep

#### Depth Simulation
- Virtual thickness: 0.12 units
- Parallax offset scales with viewing angle
- Natural vertical bias for realism

#### Chromatic Aberration
- Red: +10% offset (outward)
- Green: neutral reference
- Blue: -10% offset (inward)

#### Surface Roughness
- Multi-scale noise (40×, 80×, 160× frequency)
- Gaussian blur approximation
- Curvature-dependent intensity

## Usage

### Basic Implementation

```swift
import SwiftUI

struct MyView: View {
    var body: some View {
        ZStack {
            // Your content
            Text("Hello")
            
            // Liquid glass overlay
            MetalLiquidGlass(
                baseColor: Color.white.opacity(0.15),
                cornerRadius: 24
            )
        }
    }
}
```

### Custom Strengths

To modify effect strengths, edit `MetalLiquidGlassView.swift`:

```swift
var uniforms = Uniforms(
    time: currentTime,
    resolution: resolution,
    lightDirection: lightDirection,
    baseColor: baseColor,
    refractionStrength: 80.0,   // Less refraction
    depthStrength: 60.0,        // More depth
    dispersionStrength: 30.0,   // Less dispersion
    frostStrength: 50.0         // More frost
)
```

## Integration with Existing Code

The shader integrates seamlessly with your ContentView:

1. **Date Header** - Glass background with subtle refraction
2. **Action Buttons** - Premium glass panel effect
3. **Swipe Tags** - Colored glass badges

All components now use the Metal shader for consistent, high-quality glass effects.

## Requirements

- **iOS 14.0+** - Metal framework
- **Metal-capable device** - A7 chip or later
- **Core Motion** - For accelerometer-based lighting

## Performance Considerations

### Memory
- Single texture allocation for background
- Reusable uniform buffer
- No per-frame allocations

### GPU Usage
- Lightweight fragment shader
- ~5 texture samples per pixel (with frost)
- No complex math operations

### Battery Impact
- 60 FPS rendering only when visible
- Pauses when off-screen
- Efficient Metal command encoding

## Design Philosophy

### Premium iOS Aesthetic
- ✅ Subtle, not exaggerated
- ✅ Clean edges, no heavy glow
- ✅ Physically accurate
- ✅ Responds to device motion

### Glass Properties
- 🔮 **Translucent** - Light passes through
- 💎 **Refractive** - Bends background content
- 🌈 **Dispersive** - Splits light into colors
- ❄️ **Frosted** - Micro-surface texture
- 💫 **Dynamic** - Reacts to environment

## Troubleshooting

### Issue: Black screen
**Solution:** Check Metal device availability
```swift
guard MTLCreateSystemDefaultDevice() != nil else {
    // Fallback to SwiftUI version
    return LiquidGlassBackground(baseColor: baseColor)
}
```

### Issue: No lighting response
**Solution:** Ensure Info.plist has motion permission
```xml
<key>NSMotionUsageDescription</key>
<string>Used for realistic glass lighting effects</string>
```

### Issue: Poor performance
**Solution:** Reduce effect strengths or resolution
```swift
// Lower quality for older devices
if ProcessInfo.processInfo.isLowPowerModeEnabled {
    uniforms.frostStrength = 0.0  // Disable expensive blur
}
```

## Future Enhancements

- [ ] Background texture capture from SwiftUI
- [ ] Interactive touch ripples
- [ ] Multiple light sources
- [ ] HDR rendering support
- [ ] visionOS adaptation

## Credits

Created for premium iOS photo management app.
Based on physical optics principles and Apple's design language.

## License

Proprietary - Part of photo sorting application.

---

**Last Updated:** February 23, 2026
**Metal Shader Version:** 1.0
**iOS Target:** 14.0+
