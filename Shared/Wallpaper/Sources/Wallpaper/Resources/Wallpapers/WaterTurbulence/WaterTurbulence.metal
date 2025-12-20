//
//  WaterTurbulence.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

#include <metal_stdlib>
using namespace metal;

#define TAU 6.28318530718
#define MAX_ITER 3  // Reduced from 5 for performance

// Branchless safe division
static inline float safeDiv(float a, float b) {
    return a / (abs(b) + 1e-6);
}

static inline float luminance(float3 c) {
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

static inline float3 reinhard(float3 x) {
    return x / (1.0 + x);
}

static inline float3 energyConservingRamp(float intensity,
                                          float3 rampLow,
                                          float3 rampHigh,
                                          float rampPower)
{
    float t = powr(saturate(intensity), rampPower);
    float3 ramp = mix(rampLow, rampHigh, t);
    float l = fmax(luminance(ramp), 1e-4);
    return fmax(ramp * (intensity / l), float3(0.0));
}

[[stitchable]]
half4 waterTurbulence(float2 position,
                      half4 currentColor,
                      float time,
                      float2 viewSizePoints,
                      float scale,
                      float tilesAcross,
                      float contrastExponent,
                      float rampPower,
                      float3 rampLow,
                      float3 rampHigh,
                      float toneMapStrength,
                      float maxBrightness,
                      float gamma,
                      float iterBaseSpeed,
                      float iterSpread,
                      float iterExponent)
{
    // Use fmod with smaller range to avoid precision issues
    float t0 = fmod(time, 100.0) * 0.5 + 23.0;

    float2 fragCoord = position * scale;
    float2 iResolution = fmax(viewSizePoints * scale, float2(1.0));

    float2 uvView = fragCoord / iResolution;
    float aspect = iResolution.y / iResolution.x;
    float ta = fmax(tilesAcross, 1e-3);
    float2 uv = fract(float2(uvView.x * ta, uvView.y * ta * aspect));

    float2 p = fmod(uv * TAU, TAU) - 250.0;
    float2 i = p;

    float c = 1.0;
    constexpr float inten = 0.005;

    // Precompute iteration constants
    float base = fmax(iterBaseSpeed, 0.0);
    float spread = fmax(iterSpread, 0.0);
    constexpr float iterStep = 1.0 / float(MAX_ITER - 1);

    // Loop with fast trig
    for (int n = 0; n < MAX_ITER; n++) {
        float u = float(n) * iterStep;
        float speed = base * (1.0 + spread * powr(u, iterExponent));
        float t = t0 * speed;

        // Use fast:: versions for approximate but faster trig
        i = p + float2(fast::cos(t - i.x) + fast::sin(t + i.y),
                       fast::sin(t - i.y) + fast::cos(t + i.x));

        float sx = fast::sin(i.x + t) / inten;
        float cy = fast::cos(i.y + t) / inten;

        float2 v = float2(safeDiv(p.x, sx), safeDiv(p.y, cy));
        c += fast::rsqrt(dot(v, v) + 1e-6);  // rsqrt is faster than 1/length
    }

    c /= float(MAX_ITER);
    c = 1.17 - powr(fabs(c), 1.4);

    float intensity = saturate(powr(fabs(c), contrastExponent));
    float3 colour = energyConservingRamp(intensity, rampLow, rampHigh, rampPower);

    // Tone mapping
    colour = mix(colour, reinhard(colour), saturate(toneMapStrength));
    colour = fmin(colour, float3(saturate(maxBrightness)));

    // Gamma - use powr for positive values
    colour = powr(fmax(colour, float3(0.0)), float3(1.0 / fmax(gamma, 1.0)));

    return half4(half3(saturate(colour)), 1.0h);
}
