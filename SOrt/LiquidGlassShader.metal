//
//  LiquidGlassShader.metal
//  Liquid Glass Effect
//
//  Physically-plausible liquid glass shader for iOS
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct Uniforms {
    float time;
    float2 resolution;
    float3 lightDirection;  // From accelerometer
    float4 baseColor;
    float refractionStrength;  // 0-100
    float depthStrength;       // 0-100
    float dispersionStrength;  // 0-100
    float frostStrength;       // 0-100
};

// MARK: - Vertex Shader

vertex VertexOut liquidGlassVertex(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

// MARK: - Utility Functions

// Smooth noise function for surface variation
float hash(float2 p) {
    float h = dot(p, float2(127.1, 311.7));
    return fract(sin(h) * 43758.5453);
}

float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Surface normal estimation for refraction
float3 computeSurfaceNormal(float2 uv, float time) {
    // Create subtle surface variation
    float scale = 8.0;
    float n1 = noise(uv * scale + float2(time * 0.1, 0.0));
    float n2 = noise(uv * scale + float2(0.0, time * 0.1));
    
    // Compute gradient
    float epsilon = 0.01;
    float dx = noise((uv + float2(epsilon, 0.0)) * scale) - n1;
    float dy = noise((uv + float2(0.0, epsilon)) * scale) - n2;
    
    // Build normal (subtle variation)
    float3 normal = normalize(float3(dx * 0.3, dy * 0.3, 1.0));
    return normal;
}

// Distance from center (0 at center, 1 at edges)
float distanceFromCenter(float2 uv) {
    float2 centered = uv - 0.5;
    return length(centered) * 2.0;
}

// Edge falloff with smoothstep
float edgeFalloff(float2 uv) {
    float dist = distanceFromCenter(uv);
    return smoothstep(0.0, 1.0, 1.0 - dist);
}

// MARK: - Refraction (Strength: 100)

float2 applyRefraction(float2 uv, float3 normal, float2 resolution, float strength) {
    // Normalize strength (100 = full effect)
    float normalizedStrength = strength / 100.0;
    
    // Radial distortion from center
    float2 centered = uv - 0.5;
    float radialDist = length(centered);
    
    // Non-linear falloff
    float falloff = smoothstep(0.0, 0.8, radialDist);
    
    // UV displacement based on surface normal
    float2 displacement = normal.xy * 0.015 * normalizedStrength;
    
    // Add radial component
    float2 radialDisplacement = normalize(centered) * radialDist * 0.008 * normalizedStrength;
    
    // Combine with falloff
    float2 totalDisplacement = (displacement + radialDisplacement) * falloff;
    
    // Edge blending with smoothstep
    float edgeBlend = smoothstep(0.95, 1.0, radialDist);
    totalDisplacement *= (1.0 - edgeBlend);
    
    return uv + totalDisplacement;
}

// MARK: - Depth/Parallax (Strength: 41)

float2 applyDepth(float2 uv, float3 normal, float3 viewDir, float strength) {
    // Normalize strength (41 = moderate depth)
    float normalizedStrength = strength / 100.0;
    
    // Simulate glass thickness
    float thickness = 0.12 * normalizedStrength;
    
    // Parallax offset based on view angle and normal
    float2 parallaxOffset = normal.xy * thickness * 0.1;
    
    // Add slight vertical bias (light passing through volume)
    parallaxOffset.y += thickness * 0.05;
    
    // Distance-based scaling
    float centerDist = distanceFromCenter(uv);
    float depthScale = 1.0 - centerDist * 0.3;
    
    return uv + parallaxOffset * depthScale;
}

// MARK: - Chromatic Dispersion (Strength: 55)

float4 applyDispersion(texture2d<float> backgroundTexture,
                       sampler texSampler,
                       float2 uv,
                       float strength) {
    // Normalize strength (55 = moderate dispersion)
    float normalizedStrength = strength / 100.0;
    
    // Distance from center affects dispersion
    float centerDist = distanceFromCenter(uv);
    float dispersionAmount = centerDist * 0.003 * normalizedStrength;
    
    // Sample RGB channels at slightly different offsets
    float2 centered = uv - 0.5;
    float2 direction = normalize(centered);
    
    // Red channel - slightly outward
    float2 uvR = uv + direction * dispersionAmount * 1.1;
    // Green channel - neutral
    float2 uvG = uv;
    // Blue channel - slightly inward
    float2 uvB = uv - direction * dispersionAmount * 0.9;
    
    // Clamp UVs to valid range
    uvR = clamp(uvR, 0.0, 1.0);
    uvG = clamp(uvG, 0.0, 1.0);
    uvB = clamp(uvB, 0.0, 1.0);
    
    // Sample each channel
    float r = backgroundTexture.sample(texSampler, uvR).r;
    float g = backgroundTexture.sample(texSampler, uvG).g;
    float b = backgroundTexture.sample(texSampler, uvB).b;
    float a = backgroundTexture.sample(texSampler, uvG).a;
    
    return float4(r, g, b, a);
}

// MARK: - Frost Effect (Strength: 43)

float4 applyFrost(texture2d<float> backgroundTexture,
                  sampler texSampler,
                  float2 uv,
                  float3 normal,
                  float strength,
                  float time) {
    // Normalize strength (43 = moderate frost)
    float normalizedStrength = strength / 100.0;
    
    // Surface curvature affects frost intensity
    float curvature = abs(normal.x) + abs(normal.y);
    float frostIntensity = curvature * normalizedStrength;
    
    // Micro surface roughness using multiple noise samples
    float roughness = 0.0;
    roughness += noise(uv * 40.0 + time * 0.05) * 0.5;
    roughness += noise(uv * 80.0) * 0.3;
    roughness += noise(uv * 160.0) * 0.2;
    roughness /= 3.0;
    
    // Blur amount based on frost and roughness
    float blurAmount = frostIntensity * roughness * 0.003;
    
    // Simple gaussian-like blur using 5 samples
    float4 color = float4(0.0);
    float totalWeight = 0.0;
    
    const int samples = 5;
    const float2 offsets[5] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(-1.0, 0.0),
        float2(0.0, 1.0),
        float2(0.0, -1.0)
    };
    const float weights[5] = { 0.4, 0.15, 0.15, 0.15, 0.15 };
    
    for (int i = 0; i < samples; i++) {
        float2 sampleUV = uv + offsets[i] * blurAmount;
        sampleUV = clamp(sampleUV, 0.0, 1.0);
        color += backgroundTexture.sample(texSampler, sampleUV) * weights[i];
        totalWeight += weights[i];
    }
    
    return color / totalWeight;
}

// MARK: - Lighting (Accelerometer-based)

float3 computeLighting(float3 normal, float3 lightDir, float4 baseColor) {
    // Normalize light direction
    float3 L = normalize(lightDir);
    
    // Diffuse lighting
    float NdotL = max(dot(normal, L), 0.0);
    float3 diffuse = float3(NdotL * 0.3);
    
    // Specular highlight (glass reflection)
    float3 viewDir = float3(0.0, 0.0, 1.0);
    float3 halfDir = normalize(L + viewDir);
    float spec = pow(max(dot(normal, halfDir), 0.0), 32.0);
    float3 specular = float3(spec * 0.5);
    
    // Rim lighting for glass edge
    float rim = 1.0 - max(dot(normal, viewDir), 0.0);
    rim = pow(rim, 3.0) * 0.3;
    
    // Combine lighting components
    float3 lighting = diffuse + specular + rim;
    
    // Tint with base color
    lighting = mix(lighting, lighting * baseColor.rgb, baseColor.a);
    
    return lighting;
}

// MARK: - Fragment Shader

fragment float4 liquidGlassFragment(
    VertexOut in [[stage_in]],
    texture2d<float> backgroundTexture [[texture(0)]],
    constant Uniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler texSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge
    );
    
    float2 uv = in.texCoord;
    
    // Compute surface normal with subtle variation
    float3 normal = computeSurfaceNormal(uv, uniforms.time);
    
    // Apply refraction (strength: 100)
    float2 refractedUV = applyRefraction(uv, normal, uniforms.resolution, 
                                         uniforms.refractionStrength);
    
    // Apply depth/parallax (strength: 41)
    float3 viewDir = float3(0.0, 0.0, 1.0);
    refractedUV = applyDepth(refractedUV, normal, viewDir, uniforms.depthStrength);
    
    // Apply chromatic dispersion (strength: 55)
    float4 refractedColor = applyDispersion(backgroundTexture, texSampler, 
                                           refractedUV, uniforms.dispersionStrength);
    
    // Apply frost effect (strength: 43)
    float4 frostedColor = applyFrost(backgroundTexture, texSampler, 
                                    refractedUV, normal, uniforms.frostStrength,
                                    uniforms.time);
    
    // Blend refracted and frosted
    float frostBlend = uniforms.frostStrength / 100.0 * 0.5;
    float4 glassColor = mix(refractedColor, frostedColor, frostBlend);
    
    // Apply lighting based on accelerometer
    float3 lighting = computeLighting(normal, uniforms.lightDirection, uniforms.baseColor);
    
    // Combine with subtle lighting
    glassColor.rgb += lighting * 0.15;
    
    // Glass tint from base color
    glassColor.rgb = mix(glassColor.rgb, glassColor.rgb * uniforms.baseColor.rgb, 
                        uniforms.baseColor.a * 0.3);
    
    // Edge darkening for depth perception
    float edgeDarkening = edgeFalloff(uv);
    glassColor.rgb *= mix(0.85, 1.0, edgeDarkening);
    
    // Premium iOS glass: subtle, clean
    glassColor = clamp(glassColor, 0.0, 1.0);
    
    // Output premultiplied alpha
    glassColor.rgb *= glassColor.a;
    
    return glassColor;
}
