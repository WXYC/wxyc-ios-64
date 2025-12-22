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

// Generate pool tile grid pattern
// Returns 1.0 for grout lines, 0.0 for tile surface
static inline float poolGrid(float2 uv, float gridSize, float lineWidth) {
    float2 tileUV = fract(uv * gridSize);
    float halfLine = lineWidth * 0.5;

    // Distance from edge of tile (grout lines at edges)
    float2 distFromEdge = min(tileUV, 1.0 - tileUV);
    float minDist = min(distFromEdge.x, distFromEdge.y);

    // Smooth antialiased line
    return 1.0 - smoothstep(0.0, halfLine, minDist);
}

[[stitchable]]
half4 waterTurbulence(float2 position,
                      half4 currentColor,
                      float time,
                      float2 viewSizePoints,
                      float displayScale,
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

    float2 fragCoord = position * displayScale;
    float2 iResolution = fmax(viewSizePoints * displayScale, float2(1.0));

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

    // === Pool tile grid with refraction ===

    // Grid parameters
    float gridTiles = 8.0;      // Number of tiles across screen
    float lineWidth = 0.04;     // Line thickness relative to tile size

    // Compute grid UV with aspect correction
    float2 gridUV = float2(uvView.x, uvView.y * aspect);

    // Simple approximation: use a wave function in grid space that roughly
    // matches the caustic frequency. This won't be perfect but will correlate.
    float waveFreq = ta * TAU;  // Match the caustic tiling frequency
    float2 wavePos = gridUV * waveFreq;
    float2 simpleRefraction = float2(
        fast::sin(wavePos.x + t0 * 0.7) * fast::cos(wavePos.y + t0 * 0.5),
        fast::cos(wavePos.x + t0 * 0.6) * fast::sin(wavePos.y + t0 * 0.8)
    );

    // Modulate refraction strength by caustic intensity for correlation
    float refractionStrength = 0.015 * (0.5 + intensity * 0.5);
    float2 distortedGridUV = gridUV + simpleRefraction * refractionStrength;

    // Sample the grid pattern at distorted coordinates
    float gridLine = poolGrid(distortedGridUV, gridTiles, lineWidth);

    // Pool tile colors
    float3 tileColor = float3(0.15, 0.55, 0.75);   // Light pool blue
    float3 groutColor = float3(0.85, 0.85, 0.82);  // Off-white grout

    // Blend tile and grout
    float3 poolBase = mix(tileColor, groutColor, gridLine);

    // Apply caustic lighting from wave calculation
    // Brighter caustics add light, darker areas are shadowed
    float causticLight = mix(0.6, 1.4, intensity);
    float3 colour = poolBase * causticLight;

    // Add subtle color variation from ramp for caustic highlights
    float3 causticTint = mix(rampLow, rampHigh, intensity);
    colour = mix(colour, colour + causticTint * 0.3, intensity);

    // Tone mapping
    colour = mix(colour, colour / (1.0 + colour), saturate(toneMapStrength));
    colour = fmin(colour, float3(saturate(maxBrightness)));

    // Gamma - use powr for positive values
    colour = powr(fmax(colour, float3(0.0)), float3(1.0 / fmax(gamma, 1.0)));

    return half4(half3(saturate(colour)), 1.0h);
}
