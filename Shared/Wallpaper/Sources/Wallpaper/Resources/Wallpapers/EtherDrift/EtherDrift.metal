//
//  EtherDrift.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 1/13/26.
//  Translated from WebGL shader (volumetric cloud raymarcher)
//

#include <metal_stdlib>
using namespace metal;
#include <SwiftUI/SwiftUI_Metal.h>

// === MTKView Support ===
struct Uniforms {
    float2 resolution;
    float time;
    float lod;  // 0.0 to 1.0: scales iteration counts for thermal throttling
};

// Parameters passed in buffer 1
struct Parameters {
    float brightness;
    float colorBase;
    float colorSpeed;
    float waveFreq;
    float waveAmp;
    float passthrough;
    float fov;
    float pad;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Constants for wave computation
constant float3 RGB_PHASE = float3(0.0f, 1.0f, 2.0f);
constant float3 COLOR_DOT = float3(1.0f, -1.0f, 0.0f);
constant float3 WAVE_VELOCITY = float3(0.2f, 0.2f, 0.2f);
constant float WAVE_EXP = 1.8f;
constant float SOFTNESS = 0.005f;
constant float SKY = 10.0f;
constant float COLOR_WAVE = 14.0f;
constant float WAVE_STEPS = 8.0f;

// Core implementation (called by both stitchable and fragment versions)
static half4 etherDriftImpl(float2 position, float width, float height, float time,
                            float brightness, float colorBase, float colorSpeed,
                            float waveFreq, float waveAmp, float passthrough,
                            float fov, float lod) {
    float2 iResolution = float2(width, height);

    // Wrap time to prevent floating-point precision loss
    constexpr float timePeriod = 65536.0f * 2.0f * M_PI_F;
    float wrappedTime = fmod(time, timePeriod);

    // Ray direction - looking into the screen
    float3 dir = normalize(float3(2.0f * position - iResolution, -fov * iResolution.y));

    // Output color accumulator
    float3 col = float3(0.0f);

    // Raymarch depth
    float z = 0.0f;

    // LOD-scaled iteration counts
    // Steps: 40 at LOD 0.0, 100 at LOD 1.0
    int maxSteps = int(mix(40.0f, 100.0f, lod));
    // Wave steps: 4 at LOD 0.0, 8 at LOD 1.0
    int maxWaveSteps = int(mix(4.0f, WAVE_STEPS, lod));

    // Raymarch loop
    for (int i = 0; i < 100; i++) {
        if (i >= maxSteps) break;

        // Compute raymarch sample point
        float3 p = z * dir;

        // Turbulence loop - apply wave distortion
        float f = waveFreq;
        for (int j = 0; j < 8; j++) {
            if (j >= maxWaveSteps) break;
            p += waveAmp * sin(p * f - WAVE_VELOCITY * wrappedTime).yzx / f;
            f *= WAVE_EXP;
        }

        // Compute signed distance to horizontal planes
        float s = 0.3f - abs(p.y);

        // Soften and scale inside the clouds
        float d = SOFTNESS + max(s, -s * passthrough) / 4.0f;

        // Step forward
        z += d;

        // Coloring with signed distance, position and cycle time
        float phase = COLOR_WAVE * s + dot(p, COLOR_DOT) + colorSpeed * wrappedTime;

        // Apply RGB phase shifts, add base brightness and correct for sky
        col += (cos(phase - RGB_PHASE) + colorBase) * exp(s * SKY) / d;
    }

    // Tanh tonemapping
    col *= SOFTNESS / 100.0f * brightness;
    col = tanh(col * col);

    return half4(half3(col), 1.0h);
}

[[ stitchable ]]
half4 etherDrift(float2 position,
                 half4 inColor,
                 float width,
                 float height,
                 float time,
                 float brightness,
                 float colorBase,
                 float colorSpeed,
                 float waveFreq,
                 float waveAmp,
                 float passthrough,
                 float fov)
{
    return etherDriftImpl(position, width, height, time, brightness, colorBase,
                          colorSpeed, waveFreq, waveAmp, passthrough, fov, 1.0f);
}

// Fragment wrapper for MTKView rendering
fragment half4 etherDriftFrag(
    VertexOut in [[stage_in]],
    constant Uniforms& u [[buffer(0)]],
    constant Parameters& p [[buffer(1)]]
) {
    float2 pos = in.uv * u.resolution;
    return etherDriftImpl(pos, u.resolution.x, u.resolution.y, u.time,
                          p.brightness, p.colorBase, p.colorSpeed,
                          p.waveFreq, p.waveAmp, p.passthrough, p.fov, u.lod);
}
