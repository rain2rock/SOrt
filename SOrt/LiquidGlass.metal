//
// LiquidGlass.metal (Legacy/Fallback version)
// Simple liquid glass effect - not used in current implementation
// Kept for reference or fallback on older devices
//

#include <metal_stdlib>
using namespace metal;

struct LegacyVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex LegacyVertexOut legacyLiquidGlassVertex(uint vertexID [[vertex_id]]) {
    // Полноэкранный квад
    float2 positions[4] = {
        float2(-1, -1),
        float2( 1, -1),
        float2(-1,  1),
        float2( 1,  1)
    };
    
    LegacyVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = positions[vertexID] * 0.5 + 0.5;
    return out;
}

// Noise функция для процедурной генерации
float legacyNoise(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

float legacySmoothNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = legacyNoise(i);
    float b = legacyNoise(i + float2(1.0, 0.0));
    float c = legacyNoise(i + float2(0.0, 1.0));
    float d = legacyNoise(i + float2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Legacy liquid glass эффект (simplified version)
fragment float4 legacyLiquidGlassFragment(LegacyVertexOut in [[stage_in]],
                                          constant float *uniforms [[buffer(0)]]) {
    float time = uniforms[0];
    float4 baseColor = float4(uniforms[1], uniforms[2], uniforms[3], uniforms[4]);
    float2 resolution = float2(uniforms[5], uniforms[6]);
    
    float2 uv = in.texCoord;
    float2 p = (in.position.xy / resolution.xy) * 2.0 - 1.0;
    p.x *= resolution.x / resolution.y;
    
    // Базовый размытый цвет
    float4 color = baseColor;
    
    // Refraction эффект (волнообразное искажение)
    float2 distortion = float2(
        legacySmoothNoise(uv * 3.0 + time * 0.1),
        legacySmoothNoise(uv * 3.0 + time * 0.15 + 100.0)
    );
    distortion = (distortion - 0.5) * 0.05;
    
    // Frost эффект (матовость)
    float frost = legacySmoothNoise(uv * 15.0 + distortion * 2.0);
    frost = pow(frost, 0.7);
    color.rgb += frost * 0.15;
    
    // Градиент глубины (от светлого к темному)
    float depth = length(p) * 0.5;
    float depthGradient = smoothstep(0.0, 1.0, depth);
    color.rgb = mix(color.rgb + 0.25, color.rgb - 0.1, depthGradient);
    
    // Световой блик под углом -45° 
    float2 lightDir = normalize(float2(-1.0, -1.0));
    float highlight = dot(normalize(p), lightDir);
    highlight = smoothstep(-0.2, 0.5, highlight);
    highlight *= (1.0 - depthGradient) * 0.35;
    color.rgb += highlight;
    
    // Chromatic dispersion (цветная дисперсия на краях)
    float edge = 1.0 - smoothstep(0.3, 1.0, length(p));
    float dispersion = edge * 0.05;
    
    // Красный канал смещен влево-вверх
    float r = color.r + dispersion * legacySmoothNoise(uv * 5.0) * 0.03;
    // Синий канал смещен вправо-вниз
    float b = color.b + dispersion * legacySmoothNoise(uv * 5.0 + 50.0) * 0.05;
    
    color.r = mix(color.r, r, edge);
    color.b = mix(color.b, b, edge);
    
    // Внутреннее свечение (radial glow)
    float glow = 1.0 - length(p * 0.8);
    glow = smoothstep(0.2, 0.8, glow);
    color.rgb += glow * 0.15;
    
    // Subtle caustics (легкие каустики)
    float caustic = legacySmoothNoise(uv * 8.0 + time * 0.2);
    caustic = pow(caustic, 3.0);
    color.rgb += caustic * 0.08 * (1.0 - depthGradient);
    
    // Сохраняем альфа канал
    color.a = baseColor.a;
    
    return color;
}

