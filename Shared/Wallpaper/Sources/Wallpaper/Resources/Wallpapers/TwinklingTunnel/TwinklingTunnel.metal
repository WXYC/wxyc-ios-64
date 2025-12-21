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

// Gyroid-based distance field
static inline float gyroid(float4 p, float s) {
    float4 ps = p * s;
    float4 sinPs = sin(ps);
    float4 cosPs = cos(ps);
    // dot(sin(p*s), cos(p.zxwy*s))
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

    float i = 0.0f;
    float d = 0.0f;
    float z = 0.0f;
    float s = 0.0f;

    for (; i < 79.0f; i += 1.0f) {
        // Compute ray direction, scaled by distance
        float3 rayDir = normalize(float3(C - 0.5f * iResolution, iResolution.y));
        float4 q = float4(rayDir * z, 0.2f);

        // Traverse through the cave
        q.z += T / 30.0f;

        // Save sign before mirroring
        s = q.y + 0.1f;

        // Creates the water reflection effect
        q.y = abs(s);

        float4 p = q;
        p.y -= 0.11f;

        // Twist cave walls based on depth
        float angle = 2.0f * p.z;
        float cosA = cos(angle);
        float sinA = sin(angle);
        float2 twisted = float2(
            p.x * cosA - p.y * sinA,
            p.x * sinA + p.y * cosA
        );
        p.x = twisted.x;
        p.y = twisted.y - 0.2f;

        // Combine gyroid fields at two scales for more detail
        d = abs(gyroid(p, 8.0f) - gyroid(p, 24.0f)) / 4.0f;

        // Base glow color varies with distance from center
        float4 glowColor = 1.0f + cos(0.7f * U + 5.0f * q.z);

        // Accumulate glow — brighter and sharper if not mirrored (above axis)
        float denom = max(s > 0.0f ? d : d * d * d, 5e-4f);
        o += (s > 0.0f ? 1.0f : 0.1f) * glowColor.w * glowColor / denom;

        // Advance along the ray by current distance estimate (+ epsilon)
        z += d + 5e-4f;
    }

    // Add pulsing glow for the "tunnelwisp"
    float4 q = float4(normalize(float3(C - 0.5f * iResolution, iResolution.y)) * z, 0.2f);
    float pulse = 1.4f + sin(T) * sin(1.7f * T) * sin(2.3f * T);
    o += pulse * 1e3f * U / length(q.xy);

    // Apply tanh for soft tone mapping
    float4 result = tanh(o / 1e5f);

    return half4(half3(result.xyz), 1.0h);
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
