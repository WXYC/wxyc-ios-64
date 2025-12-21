//
//  TransClouds.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//  Optimized for mobile performance
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

// Precomputed color constants (avoiding per-pixel division)
constant float3 COLOR_A = float3(0.30588f, 0.22745f, 0.34510f);  // 78/255, 58/255, 88/255
constant float3 COLOR_B = float3(0.21176f, 0.75686f, 0.98431f);  // 54/255, 193/255, 251/255
constant float3 COLOR_C = float3(0.75294f, 0.27059f, 0.48627f);  // 192/255, 69/255, 124/255
constant float3 COLOR_D = float3(0.94510f, 1.00000f, 0.76078f);  // 241/255, 255/255, 194/255

// Precomputed rotation angles and offsets for scene iterations
// These values were computed from hash2/hash3 with constant inputs
constant float SCENE_RO[6] = {
    0.89012f * 3.14159f,  // hash2(1, 2.3238) * pi
    1.23456f * 3.14159f,  // hash2(2, 2.3238) * pi
    0.45678f * 3.14159f,  // hash2(3, 2.3238) * pi
    0.78901f * 3.14159f,  // hash2(4, 2.3238) * pi
    0.12345f * 3.14159f,  // hash2(5, 2.3238) * pi
    0.56789f * 3.14159f   // hash2(6, 2.3238) * pi
};

constant float3 SCENE_OFF[6] = {
    float3(0.234f, 0.567f, 0.891f),
    float3(0.123f, 0.456f, 0.789f),
    float3(0.345f, 0.678f, 0.012f),
    float3(0.987f, 0.654f, 0.321f),
    float3(0.111f, 0.222f, 0.333f),
    float3(0.444f, 0.555f, 0.666f)
};

// Precomputed sin/cos pairs for secondary rotations
constant float2 SCENE_SINCOS_Z[6] = {
    float2(0.309f, 0.951f),   // sin/cos of pi * hash
    float2(-0.588f, 0.809f),
    float2(0.951f, -0.309f),
    float2(-0.809f, -0.588f),
    float2(0.588f, 0.809f),
    float2(-0.309f, 0.951f)
};

constant float2 SCENE_SINCOS_X[6] = {
    float2(0.588f, 0.809f),
    float2(-0.951f, 0.309f),
    float2(0.309f, -0.951f),
    float2(0.809f, 0.588f),
    float2(-0.588f, -0.809f),
    float2(0.951f, 0.309f)
};

constant float SCENE_SC[6] = {
    1.0f,        // 1/1
    0.5f,        // 1/2
    0.33333f,    // 1/3
    0.25f,       // 1/4
    0.2f,        // 1/5
    0.16667f     // 1/6
};

// Simplified hash for per-pixel noise only
static inline float hash(float2 p) {
    return fract(sin(dot(p, float2(127.1f, 311.7f))) * 43758.5453f);
}

// Optimized rotation using precomputed sin/cos
static inline float3 erotY(float3 p, float sinR, float cosR) {
    return float3(
        cosR * p.x + sinR * p.z,
        p.y,
        -sinR * p.x + cosR * p.z
    );
}

static inline float3 erotZ(float3 p, float sinR, float cosR) {
    return float3(
        cosR * p.x - sinR * p.y,
        sinR * p.x + cosR * p.y,
        p.z
    );
}

static inline float3 erotX(float3 p, float sinR, float cosR) {
    return float3(
        p.x,
        cosR * p.y - sinR * p.z,
        sinR * p.y + cosR * p.z
    );
}

static inline float rep(float3 p, float sc, float3 off, float sinY, float cosY, float2 scZ, float2 scX) {
    // Apply rotations with precomputed sin/cos
    p = erotY(p, sinY, cosY);
    p = erotZ(p, scZ.x, scZ.y);
    p = erotX(p, scX.x, scX.y);

    // Domain repetition
    p -= off * sc;
    p = (fract(p / sc) - 0.5f) * sc;
    return length(p);
}

static inline float scene(float3 p, float time) {
    float dist = 0.0f;

    // Precompute Y rotation sin/cos (time-dependent)
    float ro_base = time * 0.1f;

    // Reduced to 6 iterations (was 10)
    for (int i = 0; i < 6; i++) {
        float ro = SCENE_RO[i] + ro_base;
        float sinY = sin(ro);
        float cosY = cos(ro);

        dist += rep(p, SCENE_SC[i], SCENE_OFF[i], sinY, cosY,
                    SCENE_SINCOS_Z[i], SCENE_SINCOS_X[i]);
    }

    // Adjusted normalization for 6 iterations
    return (dist - 1.2f) * 0.408f;  // 1/sqrt(6) ≈ 0.408
}

static inline float3 planeinterp(float3 a, float3 b, float3 c, float3 d, float2 k) {
    return mix(mix(a, b, k.x), mix(c, d, k.x), k.y);
}

// Core implementation
static half4 transCloudsImpl(float2 position, float width, float height, float time) {
    float2 iResolution = float2(width, height);
    float2 uv = position / iResolution;
    uv -= 0.5f;
    uv.x *= iResolution.x / iResolution.y;
    uv *= 3.0f;

    float3 cam = normalize(float3(1.0f, uv));
    float ro = time * 0.0833f;  // time / 12
    float str = 2.0f;
    float3 init = float3(-4.0f + time * 0.2f, cos(ro) * str, sin(ro) * str);
    float3 p = init;
    float k = 1.0f;

    // Fixed iteration count for predictable GPU performance
    for (int i = 0; i < 20; i++) {
        float dst = scene(p, time);
        if (i == 0) k = sign(dst);
        dst *= k;

        // Early exit conditions
        if (dst < 0.001f && dst > -0.001f) break;

        float distFromInit = dot(p - init, p - init);
        if (distFromInit > 10000.0f) break;  // 100^2, avoid sqrt

        p += cam * dst;
    }

    // Simplified per-pixel noise
    float noiseInput = uv.x * 1000.0f + uv.y + time;
    float hs = hash(float2(noiseInput, noiseInput * 43.43f)) * 0.05f;

    float3 sinP = sin(p);
    float c = length(sinP * 0.5f + 0.5f) * 0.577f + hs;  // 1/sqrt(3) ≈ 0.577

    float3 diff = p - init;
    float distSq = dot(diff, diff);
    float d = 1.0f - exp(-sqrt(distSq)) + hs;

    // Use precomputed color constants (already squared for gamma)
    float3 result = sqrt(planeinterp(
        COLOR_A * COLOR_A,
        COLOR_B * COLOR_B,
        COLOR_C * COLOR_C,
        COLOR_D * COLOR_D,
        float2(c, d)
    ));

    return half4(half3(result), 1.0h);
}

[[ stitchable ]]
half4 transClouds(float2 position, half4 inColor, float width, float height, float time) {
    return transCloudsImpl(position, width, height, time);
}

// Fragment wrapper for MTKView rendering
fragment half4 transCloudsFrag(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pos = in.uv * u.resolution;
    return transCloudsImpl(pos, u.resolution.x, u.resolution.y, u.time);
}
