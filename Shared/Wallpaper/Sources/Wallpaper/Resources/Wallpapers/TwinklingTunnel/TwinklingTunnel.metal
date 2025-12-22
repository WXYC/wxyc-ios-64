//
//  TwinklingTunnel.metal
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
    float pad;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Fast tanh approximation
static inline float fast_tanh(float x) {
    return x / (1.0f + abs(x));
}

// Gyroid-based distance field using fast trig
static inline float gyroid(float4 p, float s) {
    float4 ps = p * s;
    float4 sinPs = fast::sin(ps);
    float4 cosPs = fast::cos(ps);
    float4 cosSwizzle = float4(cosPs.z, cosPs.x, cosPs.w, cosPs.y);
    return abs(dot(sinPs, cosSwizzle) - 1.0f) / s;
}

// Core implementation
static half4 twinklingTunnelImpl(float2 position, float width, float height, float time) {
    float2 iResolution = float2(width, height);
    float2 C = position;
    float T = time;

    float4 U = float4(2.0f, 1.0f, 0.0f, 3.0f);
    float4 o = float4(0.0f);

    float d = 0.0f;
    float z = 0.0f;

    // Hoist ray direction outside loop - it's constant per pixel
    float3 rayDir = fast::normalize(float3(C - 0.5f * iResolution, iResolution.y));
    float timeOffset = T / 30.0f;

    // Reduced iterations: 50 instead of 79
    for (int i = 0; i < 50; i++) {
        float4 q = float4(rayDir * z, 0.2f);
        q.z += timeOffset;

        // Save sign before mirroring
        float s = q.y + 0.1f;

        // Creates the water reflection effect
        q.y = abs(s);

        float4 p = q;
        p.y -= 0.11f;

        // Twist cave walls based on depth using fast trig
        float angle = 2.0f * p.z;
        float cosA = fast::cos(angle);
        float sinA = fast::sin(angle);
        p.xy = float2(
            p.x * cosA - p.y * sinA,
            p.x * sinA + p.y * cosA - 0.2f
        );

        // Combine gyroid fields at two scales
        d = abs(gyroid(p, 8.0f) - gyroid(p, 24.0f)) * 0.25f;

        // Base glow color varies with distance from center
        float4 glowColor = 1.0f + fast::cos(0.7f * U + 5.0f * q.z);

        // Branchless accumulation using select
        float above = step(0.0f, s);  // 1.0 if s >= 0, else 0.0
        float dPow = mix(d * d * d, d, above);  // d^3 below, d above
        float intensity = mix(0.1f, 1.0f, above);  // 0.1 below, 1.0 above
        float denom = max(dPow, 5e-4f);
        o += intensity * glowColor.w * glowColor / denom;

        // Advance along ray
        z += d + 5e-4f;
    }

    // Add pulsing glow for the "tunnelwisp"
    float4 q = float4(rayDir * z, 0.2f);
    float pulse = 1.4f + fast::sin(T) * fast::sin(1.7f * T) * fast::sin(2.3f * T);
    o += pulse * 1e3f * U * fast::rsqrt(dot(q.xy, q.xy) + 1e-6f);

    // Apply fast tanh for tone mapping (adjusted divisor for fewer iterations)
    float3 result = float3(
        fast_tanh(o.x / 6e4f),
        fast_tanh(o.y / 6e4f),
        fast_tanh(o.z / 6e4f)
    );

    return half4(half3(result), 1.0h);
}

[[ stitchable ]]
half4 twinklingTunnel(float2 position, half4 inColor, float width, float height, float time) {
    return twinklingTunnelImpl(position, width, height, time);
}

// Fragment wrapper for MTKView rendering
fragment half4 twinklingTunnelFrag(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pos = in.uv * u.resolution;
    return twinklingTunnelImpl(pos, u.resolution.x, u.resolution.y, u.time);
}
