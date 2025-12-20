//
//  WaterTurbulence.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

#include <metal_stdlib>
using namespace metal;

#define TAU 6.28318530718
#define MAX_ITER 5

static inline float safeDiv(float a, float b) {
    float bb = (fabs(b) < 1e-6) ? (b < 0.0 ? -1e-6 : 1e-6) : b;
    return a / bb;
}

static inline float luminance(float3 c) {
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

static inline float3 reinhard(float3 x) {
    return x / (1.0 + x);
}

// Energy-conserving ramp: ramp color is scaled so its luminance equals 'intensity'.
static inline float3 energyConservingRamp(float intensity,
                                          float3 rampLow,
                                          float3 rampHigh,
                                          float rampPower)
{
    float t = pow(clamp(intensity, 0.0, 1.0), max(rampPower, 1e-3));
    float3 ramp = mix(rampLow, rampHigh, t);

    float l = max(luminance(ramp), 1e-4);
    float3 scaled = ramp * (intensity / l);

    return max(scaled, float3(0.0));
}

[[stitchable]]
half4 waterTurbulence(float2 position,
                      half4 currentColor,
                      float time,
                      float2 viewSizePoints,
                      float scale,
                      float tilesAcross,       // 1.0 = one tile across width
                      float contrastExponent,  // intensity shaping
                      float rampPower,         // ramp curve
                      float3 rampLow,          // ramp low RGB
                      float3 rampHigh,         // ramp high RGB
                      float toneMapStrength,   // 0..1
                      float maxBrightness,     // 0..1 hard ceiling
                      float gamma,             // e.g. 2.2
                      float iterBaseSpeed,     // new: base iteration speed
                      float iterSpread,        // new: speed divergence
                      float iterExponent)      // new: divergence curve
{
    // Keep time in a sane range.
    time = fmod(time, 1000.0);

    float2 fragCoord = position * scale;
    float2 iResolution = max(viewSizePoints * scale, float2(1.0));

    // 0..1 over whole view
    float2 uvView = fragCoord / iResolution;

    // Aspect-correct tiling: square tiles
    float aspect = iResolution.y / iResolution.x;
    float ta = max(tilesAcross, 1e-3);
    float2 uvTileSpace = float2(uvView.x * ta,
                                uvView.y * ta * aspect);

    // Repeat to fill view
    float2 uv = fract(uvTileSpace);

    // --- Core turbulence math ---
    float t0 = time * 0.5 + 23.0;

    float2 p = fmod(uv * TAU, TAU) - 250.0;
    float2 i = p;

    float c = 1.0;
    float inten = 0.005;

    float base = max(iterBaseSpeed, 0.0);
    float spread = max(iterSpread, 0.0);
    float expo = max(iterExponent, 1e-3);

    for (int n = 0; n < MAX_ITER; n++) {
        // New: per-iteration speed curve (0..1 across iterations)
        float u = (MAX_ITER > 1) ? (float(n) / float(MAX_ITER - 1)) : 0.0;
        float speed = base * (1.0 + spread * pow(u, expo));

        // Use the shaped speed here
        float t = t0 * speed;

        i = p + float2(cos(t - i.x) + sin(t + i.y),
                       sin(t - i.y) + cos(t + i.x));

        float sx = sin(i.x + t) / inten;
        float cy = cos(i.y + t) / inten;

        float2 v = float2(safeDiv(p.x, sx), safeDiv(p.y, cy));
        float lenv = max(length(v), 1e-6);
        c += 1.0 / lenv;
    }

    c /= float(MAX_ITER);
    c = 1.17 - pow(c, 1.4);

    // Contrast shaping
    float intensity = pow(fabs(c), max(contrastExponent, 1e-3));
    intensity = clamp(intensity, 0.0, 1.0);

    // Energy-conserving color ramp
    float3 colour = energyConservingRamp(intensity, rampLow, rampHigh, rampPower);

    // Soft tone mapping (blend)
    float tms = clamp(toneMapStrength, 0.0, 1.0);
    float3 tm = reinhard(colour);
    colour = mix(colour, tm, tms);

    // Explicit brightness cap
    float cap = clamp(maxBrightness, 0.0, 1.0);
    colour = min(colour, float3(cap));

    // Gamma correction
    float g = max(gamma, 1e-3);
    colour = pow(max(colour, float3(0.0)), float3(1.0 / g));

    // Final clamp
    colour = clamp(colour, 0.0, 1.0);

    return half4(half(colour.r), half(colour.g), half(colour.b), half(1.0));
}
