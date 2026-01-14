//
//  SteelCubeIdolatry.metal
//  Wallpaper
//
//  Voronoi reflections with procedural neon environment.
//  Ported from Shadertoy, cube map replaced with procedural neon lights.
//
//  Created by Jake Bromberg on 12/30/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 resolution;
    float time;
    float lod;  // 0.0 to 1.0: scales neon tube count for thermal throttling
};

// Custom parameters passed from debug UI
// Order must match JSON parameter order:
// [0] yellowIntensity, [1] magentaIntensity, [2] cyanIntensity,
// [3] blueIntensity, [4] ambientLevel, [5] glowAmount,
// [6] voronoiScale, [7] cellAnimSpeed
struct Parameters {
    float values[8];
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

constant float PI = 3.141592;

// 2D random
static inline float2 r2D(float2 p) {
    return float2(fract(fast::sin(dot(p, float2(92.51, 65.19))) * 4981.32),
                  fract(fast::sin(dot(p, float2(23.34, 15.28))) * 6981.32));
}

// Polygon distance (rounded polygon shape)
static inline float polygon(float2 p, float s) {
    float a = ceil(s * (fast::atan2(-p.y, -p.x) / PI + 1.0) * 0.5);
    float n = 2.0 * PI / s;
    float t = n * a - n * 0.5;
    return mix(dot(p, float2(fast::cos(t), fast::sin(t))), length(p), 0.3);
}

// Voronoi pattern with animated cells (optimized 2x2 neighborhood)
static inline float voronoi(float2 p, float s, float time, float cellAnimSpeed) {
    float2 i = floor(p * s);
    float2 f = fract(p * s);
    float2 current = i + f;
    float min_dist = 1.0;

    // Use 2x2 neighborhood based on fractional position
    int x0 = (f.x < 0.5) ? -1 : 0;
    int y0 = (f.y < 0.5) ? -1 : 0;

    for (int y = y0; y <= y0 + 1; y++) {
        for (int x = x0; x <= x0 + 1; x++) {
            float2 neighbor = i + float2(x, y);
            float2 point = r2D(neighbor);
            point = 0.5 + 0.5 * fast::sin(time * cellAnimSpeed + 6.0 * point);
            float dist = polygon(neighbor + point - current, 3.0);
            min_dist = min(min_dist, dist);
        }
    }
    return min_dist;
}

// Procedural neon environment inspired by Dan Flavin light sculptures
// Creates colorful neon tube gradients based on reflection direction
static inline float3 neonEnvironment(float3 dir,
                                      float yellowInt,
                                      float magentaInt,
                                      float cyanInt,
                                      float blueInt,
                                      float ambientLevel,
                                      float glowAmount,
                                      float lod) {
    float3 d = fast::normalize(dir);

    // Base colors for neon tubes
    float3 yellow = float3(1.0, 0.95, 0.2);
    float3 magenta = float3(1.0, 0.15, 0.6);
    float3 cyan = float3(0.1, 0.85, 1.0);
    float3 blue = float3(0.2, 0.3, 1.0);

    // Corner room ambient
    float3 ambient = float3(0.15, 0.12, 0.25) * ambientLevel;

    // Vertical tube (yellow) - along Y axis (always evaluated)
    float verticalTube = smoothstep(0.3, 0.0, abs(d.x)) * smoothstep(-0.2, 0.5, d.y);
    float3 col = ambient + yellow * verticalTube * yellowInt;

    // Left side magenta/pink glow (always evaluated)
    float leftGlow = smoothstep(0.5, -0.3, d.x) * smoothstep(-0.5, 0.3, d.y);
    col += magenta * leftGlow * magentaInt;

    // LOD >= 0.5: evaluate remaining tubes
    if (lod >= 0.5f) {
        // Horizontal tube (yellow) - along X axis at top
        float horizontalTube = smoothstep(0.3, 0.0, abs(d.y - 0.4)) * smoothstep(0.0, 0.3, abs(d.x));
        col += yellow * horizontalTube * yellowInt * 0.67;

        // Right side cyan glow
        float rightGlow = smoothstep(-0.5, 0.3, d.x) * smoothstep(-0.5, 0.3, d.y);
        col += cyan * rightGlow * cyanInt;

        // Center blue accent
        float centerGlow = smoothstep(0.4, 0.0, length(d.xy));
        col += blue * centerGlow * blueInt;
    }

    // Add some variation based on z for depth
    col *= 0.8 + 0.2 * smoothstep(-1.0, 1.0, d.z);

    // Bloom/glow effect
    col = col + col * col * glowAmount;

    return saturate(col);
}

fragment float4 steelCubeIdolatryFragment(
    VertexOut in [[stage_in]],
    constant Uniforms& u [[buffer(0)]],
    constant Parameters& p [[buffer(1)]]
) {
    // Read parameters with defaults
    float yellowInt = p.values[0];
    float magentaInt = p.values[1];
    float cyanInt = p.values[2];
    float blueInt = p.values[3];
    float ambientLevel = p.values[4];
    float glowAmount = p.values[5];
    float voronoiScale = p.values[6];
    float cellAnimSpeed = p.values[7];

    // Flip Y for Shadertoy convention
    float2 fragCoord = float2(in.uv.x, 1.0 - in.uv.y) * u.resolution;

    // Normalized coordinates (Shadertoy style: divide by height, center)
    float2 uv = fragCoord / u.resolution.y * 2.0 - 1.0;
    // Adjust for aspect ratio
    uv.x -= (u.resolution.x / u.resolution.y - 1.0);

    float2 e = float2(0.01, 0.0);

    float t = u.time / 3.0;

    // Voronoi and derivatives for normal calculation
    float vor = 1.0 - voronoi(uv, voronoiScale, t, cellAnimSpeed);
    float dx = 1.0 - voronoi(uv - e.xy, voronoiScale, t, cellAnimSpeed);
    float dy = 1.0 - voronoi(uv - e.yx, voronoiScale, t, cellAnimSpeed);
    dx = (dx - vor) / e.x;
    dy = (dy - vor) / e.x;

    // Surface normal from height field
    float3 n = fast::normalize(float3(dx, dy, 1.0));

    // Animated light position
    float3 lp = float3(fast::cos(t), fast::sin(t), 0.5) * 2.0;
    float3 ld = fast::normalize(lp - float3(uv, 0.0));
    float3 ed = fast::normalize(float3(0.0, 0.0, 1.0) - float3(uv, 0.0));
    float3 hd = fast::normalize(ld + ed);

    // Lighting calculations
    float spec = max(dot(hd, n), 0.0);
    float sl = spec * spec * spec * spec;  // Specular (x^4)
    float oc = saturate(vor * vor);         // Occlusion (x^2)
    float amb = (1.0 - vor) * 0.5;              // Ambient
    float diff = max(dot(n, ld), 0.0) * 0.75;   // Diffuse
    float l = oc * diff + amb + sl;

    // Reflection direction for environment sampling
    float3 viewDir = float3(0.0, 0.0, 1.0);
    float3 reflectDir = fast::normalize(reflect(viewDir, n));

    // Sample procedural neon environment with tunable parameters
    float3 envColor = neonEnvironment(reflectDir, yellowInt, magentaInt, cyanInt,
                                       blueInt, ambientLevel, glowAmount, u.lod);

    // Final color: lighting * environment
    float3 col = l * envColor;

    return float4(col, 1.0);
}
