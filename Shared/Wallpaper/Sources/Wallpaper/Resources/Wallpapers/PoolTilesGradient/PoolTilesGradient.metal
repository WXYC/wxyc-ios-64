//
//  PoolTilesGradient.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/21/25.
//
//  Complex version with true gradient-based refraction.
//  Computes caustic intensity at multiple points to derive surface normal.
//

#include <metal_stdlib>
using namespace metal;

#define TAU 6.28318530718
#define MAX_ITER 3

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

// Compute caustic intensity at a given UV position
// Factored out so we can sample at multiple points for gradient
static inline float computeCausticIntensity(float2 uvView,
                                            float aspect,
                                            float tilesAcross,
                                            float t0,
                                            float iterBaseSpeed,
                                            float iterSpread,
                                            float iterExponent,
                                            float contrastExponent)
{
    float ta = fmax(tilesAcross, 1e-3);
    float2 uv = fract(float2(uvView.x * ta, uvView.y * ta * aspect));

    float2 p = fmod(uv * TAU, TAU) - 250.0;
    float2 i = p;

    float c = 1.0;
    constexpr float inten = 0.005;

    float base = fmax(iterBaseSpeed, 0.0);
    float spread = fmax(iterSpread, 0.0);
    constexpr float iterStep = 1.0 / float(MAX_ITER - 1);

    for (int n = 0; n < MAX_ITER; n++) {
        float u = float(n) * iterStep;
        float speed = base * (1.0 + spread * powr(u, iterExponent));
        float t = t0 * speed;

        i = p + float2(fast::cos(t - i.x) + fast::sin(t + i.y),
                       fast::sin(t - i.y) + fast::cos(t + i.x));

        float sx = fast::sin(i.x + t) / inten;
        float cy = fast::cos(i.y + t) / inten;

        float2 v = float2(safeDiv(p.x, sx), safeDiv(p.y, cy));
        c += fast::rsqrt(dot(v, v) + 1e-6);
    }

    c /= float(MAX_ITER);
    c = 1.17 - powr(fabs(c), 1.4);

    return saturate(powr(fabs(c), contrastExponent));
}

[[stitchable]]
half4 poolTilesGradient(float2 position,
                        half4 currentColor,
                        float time,
                        float2 viewSizePoints,
                        float displayScale,
                        float tilesAcross,
                        float contrastExponent,
                        float refractionStrength,
                        float gridTiles,
                        float lineWidth,
                        float3 tileColor,
                        float3 groutColor,
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

    // === Compute gradient by sampling intensity at 3 points ===

    // Delta for gradient computation (in UV space)
    float delta = 0.002;

    // Sample intensity at center, +x, and +y
    float intensityCenter = computeCausticIntensity(
        uvView, aspect, tilesAcross, t0,
        iterBaseSpeed, iterSpread, iterExponent, contrastExponent);

    float intensityX = computeCausticIntensity(
        uvView + float2(delta, 0.0), aspect, tilesAcross, t0,
        iterBaseSpeed, iterSpread, iterExponent, contrastExponent);

    float intensityY = computeCausticIntensity(
        uvView + float2(0.0, delta), aspect, tilesAcross, t0,
        iterBaseSpeed, iterSpread, iterExponent, contrastExponent);

    // Compute gradient (rate of change of intensity)
    float2 gradient = float2(
        (intensityX - intensityCenter) / delta,
        (intensityY - intensityCenter) / delta
    );

    // === Pool tile grid with gradient-based refraction ===

    // Compute grid UV with aspect correction
    float2 gridUV = float2(uvView.x, uvView.y * aspect);

    // Apply refraction: offset UV by gradient
    // The gradient points in the direction of increasing intensity,
    // which corresponds to the "slope" of the wave surface
    float2 distortedGridUV = gridUV + gradient * refractionStrength;

    // Sample the grid pattern at distorted coordinates
    float gridLine = poolGrid(distortedGridUV, gridTiles, lineWidth);

    // Blend tile and grout
    float3 poolBase = mix(tileColor, groutColor, gridLine);

    // Apply caustic lighting from wave calculation
    float causticLight = mix(0.6, 1.4, intensityCenter);
    float3 colour = poolBase * causticLight;

    // Add subtle highlight on caustic peaks
    colour += float3(0.1, 0.15, 0.2) * intensityCenter * intensityCenter;

    // Simple tone mapping
    colour = colour / (1.0 + colour);

    return half4(half3(saturate(colour)), 1.0h);
}
