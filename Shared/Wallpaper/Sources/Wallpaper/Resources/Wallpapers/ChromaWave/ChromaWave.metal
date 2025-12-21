//
//  ChromaWave.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

#include <metal_stdlib>
using namespace metal;
#include <SwiftUI/SwiftUI_Metal.h>

// === MTKView Support ===
struct Uniforms {
    float2 resolution;
    float time;
    float displayScale;
    float audioLevel;
    float audioBass;
    float audioMid;
    float audioHigh;
    float audioBeat;
    float pad;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Core implementation (called by both stitchable and fragment versions)
static half4 chromaWaveImpl(float2 position, float width, float height, float time) {
    float2 iResolution = float2(width, height);
    float t = time / 32.0f;
    float3 col = float3(0.0f);

    // Process each color channel separately
    for (int c = 0; c < 3; c++) {
        float2 uv = (position * 20.0f - iResolution) / iResolution.y;

        // Iterative wave distortion
        for (int i = 1; i < 7; i++) {
            uv /= 1.70f;
            uv += ceil(col.yx);
            uv += float(i) + (cos(uv.x) * cos(uv.y) + sin(uv.y) * cos(t) + cos(t) * cos(uv.x));
        }

        col[c] = fract(uv.x + uv.y + t);
    }

    // Apply slight color enhancement
    col += 0.2f * clamp(col, 0.0f, 0.5f);
    // Gamma correction
    col = pow(col, float3(1.0f / 2.2f));

    return half4(half3(col), 1.0h);
}

[[ stitchable ]]
half4 chromaWave(float2 position,
                 half4 inColor,
                 float width,
                 float height,
                 float time)
{
    return chromaWaveImpl(position, width, height, time);
}

// Fragment wrapper for MTKView rendering
fragment half4 chromaWaveFrag(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pos = in.uv * u.resolution;
    return chromaWaveImpl(pos, u.resolution.x, u.resolution.y, u.time);
}
