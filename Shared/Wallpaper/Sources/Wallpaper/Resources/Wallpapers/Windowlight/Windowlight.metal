//
//  Windowlight.metal
//  Wallpaper
//
//  Rain on window effect - translated from Shadertoy.
//

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 resolution;
    float time;
    float pad;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Precomputed constants
constant float SIN_1_75_HALF = 0.4794255386;  // sin(1.75) * 0.5
constant float3 COLOR_SHIFT = float3(0.8, 0.9, 1.3);
constant float3 COLOR_SHIFT_MIXED = mix(float3(1.0), COLOR_SHIFT, SIN_1_75_HALF);

// Grid constants for DropLayer2
constant float2 DROP_GRID = float2(12.0, 2.0);  // a * 2.0 where a = (6, 1)
constant float2 DROP_A_YX = float2(1.0, 6.0);   // a.yx

// Since rainAmount = 1.0, these are all constants:
constant float STATIC_DROPS_MULT = 2.0;   // S(-0.5, 1.0, 1.0) * 2.0
constant float LAYER1_MULT = 1.0;         // S(0.25, 0.75, 1.0)
constant float LAYER2_MULT = 1.0;         // S(0.0, 0.5, 1.0)
constant float MAX_BLUR = 6.0;            // mix(3.0, 6.0, 1.0)
constant float MIN_BLUR = 2.0;

// Precomputed light positions for background (static bokeh lights)
constant float2 LIGHT_POS_0 = float2(0.2867965, 0.06442177);
constant float2 LIGHT_POS_1 = float2(-0.5765986, 0.07629883);
constant float2 LIGHT_POS_2 = float2(0.1372661, 0.5765202);
constant float2 LIGHT_POS_3 = float2(0.5765986, 0.2291831);
constant float2 LIGHT_POS_4 = float2(-0.2456529, -0.04193793);
constant float LIGHT_INTENSITY_0 = 0.3;
constant float LIGHT_INTENSITY_1 = 0.4755283;
constant float LIGHT_INTENSITY_2 = 0.3489372;
constant float LIGHT_INTENSITY_3 = 0.1244717;
constant float LIGHT_INTENSITY_4 = 0.4510628;

// Smoothstep shorthand
static inline float S(float a, float b, float t) {
    return smoothstep(a, b, t);
}

// Hash functions for procedural noise
static inline float3 N13(float p) {
    float3 p3 = fract(float3(p) * float3(0.1031, 0.11369, 0.13787));
    p3 += dot(p3, p3.yzx + 19.19);
    return fract(float3((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y, (p3.y + p3.z) * p3.x));
}

static inline float N(float t) {
    return fract(fast::sin(t * 12345.564) * 7658.76);
}

// Sawtooth function
static inline float Saw(float b, float t) {
    return S(0.0, b, t) * S(1.0, b, t);
}

// Animated raindrop layer
static inline float2 DropLayer2(float2 uv, float t) {
    float2 UV = uv;

    uv.y += t * 0.75;
    float2 id = floor(uv * DROP_GRID);

    float colShift = N(id.x);
    uv.y += colShift;

    id = floor(uv * DROP_GRID);
    float3 n = N13(id.x * 35.2 + id.y * 2376.1);
    float2 st = fract(uv * DROP_GRID) - float2(0.5, 0.0);

    float x = n.x - 0.5;

    float y = UV.y * 20.0;
    float wiggle = fast::sin(y + fast::sin(y));
    x += wiggle * (0.5 - abs(x)) * (n.z - 0.5);
    x *= 0.7;
    float ti = fract(t + n.z);
    y = (Saw(0.85, ti) - 0.5) * 0.9 + 0.5;
    float2 p = float2(x, y);

    float d = length((st - p) * DROP_A_YX);

    float mainDrop = S(0.4, 0.0, d);

    float r = fast::sqrt(S(1.0, y, st.y));
    float cd = abs(st.x - x);
    float trail = S(0.23 * r, 0.15 * r * r, cd);
    float trailFront = S(-0.02, 0.02, st.y - y);
    trail *= trailFront * r * r;

    y = UV.y;
    float trail2 = S(0.2 * r, 0.0, cd);
    float droplets = max(0.0, (fast::sin(y * (1.0 - y) * 120.0) - st.y)) * trail2 * trailFront * n.z;
    y = fract(y * 10.0) + (st.y - 0.5);
    float dd = length(st - float2(x, y));
    droplets = S(0.3, 0.0, dd);
    float m = mainDrop + droplets * r * trailFront;

    return float2(m, trail);
}

// Static raindrops
static inline float StaticDrops(float2 uv, float t) {
    uv *= 40.0;

    float2 id = floor(uv);
    uv = fract(uv) - 0.5;
    float3 n = N13(id.x * 107.45 + id.y * 3543.654);
    float2 p = (n.xy - 0.5) * 0.7;
    float d = length(uv - p);

    float fade = Saw(0.025, fract(t + n.z));
    float c = S(0.3, 0.0, d) * fract(n.z * 10.0) * fade;
    return c;
}

// Combined drop layers
static inline float2 Drops(float2 uv, float t, float l0, float l1, float l2) {
    float s = StaticDrops(uv, t) * l0;
    float2 m1 = DropLayer2(uv, t) * l1;
    float2 m2 = DropLayer2(uv * 1.85, t) * l2;

    float c = s + m1.x + m2.x;
    c = S(0.3, 1.0, c);

    return float2(c, max(m1.y * l0, m2.y * l1));
}

// Procedural window light background - unrolled loop with precomputed positions
static inline float3 windowBackground(float2 uv, float time) {
    // Warm ambient light gradient (simulating city lights through rainy window)
    constant float3 warmLight = float3(1.0, 0.85, 0.6);
    constant float3 coolShadow = float3(0.15, 0.2, 0.35);

    // Vertical gradient - lighter at top (sky/lights)
    float grad = smoothstep(-0.3, 0.8, uv.y);

    // Unrolled light calculations with precomputed positions
    float lights = smoothstep(0.5, 0.0, fast::length(uv - LIGHT_POS_0)) * LIGHT_INTENSITY_0
                 + smoothstep(0.5, 0.0, fast::length(uv - LIGHT_POS_1)) * LIGHT_INTENSITY_1
                 + smoothstep(0.5, 0.0, fast::length(uv - LIGHT_POS_2)) * LIGHT_INTENSITY_2
                 + smoothstep(0.5, 0.0, fast::length(uv - LIGHT_POS_3)) * LIGHT_INTENSITY_3
                 + smoothstep(0.5, 0.0, fast::length(uv - LIGHT_POS_4)) * LIGHT_INTENSITY_4;

    // Soft bokeh-like glow
    float3 col = mix(coolShadow, warmLight, grad * 0.7 + lights * 0.5);

    // Add subtle color variation
    col += float3(0.1, 0.05, 0.0) * fast::sin(time * 0.1) * 0.5;

    return col;
}

// Sample background with blur (simulated with fewer samples - background is already soft)
static inline float3 sampleBlurred(float2 uv, float blur, float time) {
    float3 col = windowBackground(uv, time);

    // Reduced blur simulation - 5 samples instead of 9
    float blurAmount = blur * 0.02;

    float3 blurred = col
        + windowBackground(uv + float2(blurAmount, 0.0), time)
        + windowBackground(uv + float2(-blurAmount, 0.0), time)
        + windowBackground(uv + float2(0.0, blurAmount), time)
        + windowBackground(uv + float2(0.0, -blurAmount), time);
    blurred *= 0.2;  // 1/5

    return mix(col, blurred, saturate(blur * 0.2));
}

fragment float4 windowlightFragment(
    VertexOut in [[stage_in]],
    constant Uniforms& u [[buffer(0)]]
) {
    // Normalized coordinates
    float2 uv = (in.uv - 0.5) * float2(u.resolution.x / u.resolution.y, 1.0) * 0.7;

    float T = u.time;
    float t = T * 0.2;

    // Use precomputed constants (rainAmount = 1.0)
    float2 c = Drops(uv, t, STATIC_DROPS_MULT, LAYER1_MULT, LAYER2_MULT);

    // Cheap normals using derivatives
    float2 n = float2(dfdx(c.x), dfdy(c.x));

    float focus = mix(MAX_BLUR - c.y, MIN_BLUR, S(0.1, 0.2, c.x));

    // Sample procedural background with refraction and blur
    float3 col = sampleBlurred(in.uv + n, focus, T);

    // Apply precomputed color shift
    col *= COLOR_SHIFT_MIXED;

    return float4(col, 1.0);
}
