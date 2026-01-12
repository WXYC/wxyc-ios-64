//
//  RefractNoise.metal
//  Wallpaper
//
//  Ray-marched refractive SDF shapes with subtle FBM displacement.
//  Ported from a Shadertoy snippet (environment-map sampling replaced with a procedural sky).
//

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 resolution;
    float time;
    float lod;  // 0.0 = minimum quality, 1.0 = full quality
};

// Parameters passed in buffer 1 (up to 8 floats)
struct Parameters {
    float tileColorR;
    float tileColorG;
    float tileColorB;
    float refractIndex;
    float cubeTintR;
    float cubeTintG;
    float cubeTintB;
    float noiseStrength;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// === Noise (3D from 2D noise texture) ===
constant float INV_256 = 0.00390625f;          // 1.0 / 256.0
constant float2 NOISE_OFFSET = float2(37.0f, 17.0f);
constant float2 NOISE_OFFSET2 = float2(-36.5f, -16.5f);  // -37+0.5, -17+0.5

static inline float noise3D(float3 x, texture2d<float> noiseTex, sampler s) {
    float3 p = floor(x);
    float3 f = x - p;
    // Smoothstep
    f = f * f * (3.0f - 2.0f * f);

    float2 uv = p.xy + NOISE_OFFSET * p.z + f.xy;

    // Sample noise texture at two positions for z interpolation.
    float a = noiseTex.sample(s, (uv + 0.5f) * INV_256).x;
    float b = noiseTex.sample(s, (uv + NOISE_OFFSET2) * INV_256).x;
    return mix(b, a, f.z) * 2.0f - 1.0f; // center to [-1, 1]
}

static inline float fbm(float3 pos, int octaves, float persistence, texture2d<float> noiseTex, sampler s) {
    float total = 0.0f;
    float frequency = 1.0f;
    float amplitude = 1.0f;
    float maxValue = 0.0f;
    for (int i = 0; i < octaves; ++i) {
        total += noise3D(pos * frequency, noiseTex, s) * amplitude;
        maxValue += amplitude;
        amplitude *= persistence;
        frequency *= 2.0f;
    }
    return total / max(maxValue, 1e-5f);
}

static inline float getNoise(float3 p, float time, float noiseStrength, int octaves, texture2d<float> noiseTex, sampler s) {
    return noiseStrength * fbm(p + 0.3f * time, octaves, 0.3f, noiseTex, s);
}

// === Camera ===
static inline float3x3 lookAt(float3 eye, float3 center, float3 up) {
    float3 f = normalize(center - eye);
    float3 s = normalize(cross(f, up));
    float3 u = cross(s, f);
    // GLSL mat3(s,u,-f) uses column vectors; Metal is column-major too.
    return float3x3(s, u, -f);
}

// === Distance Functions ===
static inline float sdSphere(float3 pos, float radius) { return length(pos) - radius; }

static inline float sdBox(float3 pos, float3 size) {
    float3 d = abs(pos) - size;
    return min(max(d.x, max(d.y, d.z)), 0.0f) + length(max(d, 0.0f));
}

static inline float sdPlaneY(float3 pos, float y) {
    // Positive above the plane, negative below.
    return pos.y - y;
}

static inline float sdPlaneZ(float3 pos, float z) {
    // Positive in front of the plane, negative behind.
    return pos.z - z;
}

// === Distance Ops / Scene ===
static inline float2 opU(float2 a, float2 b) { return (a.x < b.x) ? a : b; } // union

static inline float2 mapScene(
    float3 pos,
    float cubeHalfSize,
    float floorZ,
    float time,
    float noiseStrength,
    int octaves,
    texture2d<float> noiseTex,
    sampler s
) {
    // Shape 0: cube (slightly noisy surface)
    float dCube = sdBox(pos, float3(cubeHalfSize));
    dCube += getNoise(pos, time, noiseStrength, octaves, noiseTex, s);
    float2 res = float2(dCube, 0.0f);

    // Shape 1: backdrop plane (perpendicular to camera, behind the cube)
    float dFloor = sdPlaneZ(pos, floorZ);
    res = opU(res, float2(dFloor, 1.0f));

    return res;
}

static inline float sdScene(float3 pos, float cubeHalfSize, float floorZ, float time, float noiseStrength, int octaves, texture2d<float> noiseTex, sampler s) {
    return mapScene(pos, cubeHalfSize, floorZ, time, noiseStrength, octaves, noiseTex, s).x;
}

static inline float3 calculateNormal(float3 p, float cubeHalfSize, float floorZ, float time, float noiseStrength, int octaves, texture2d<float> noiseTex, sampler s) {
    const float eps = 0.01f;
    float3 ex = float3(eps, 0.0f, 0.0f);
    float3 ey = float3(0.0f, eps, 0.0f);
    float3 ez = float3(0.0f, 0.0f, eps);

    float gradX = sdScene(p + ex, cubeHalfSize, floorZ, time, noiseStrength, octaves, noiseTex, s) - sdScene(p - ex, cubeHalfSize, floorZ, time, noiseStrength, octaves, noiseTex, s);
    float gradY = sdScene(p + ey, cubeHalfSize, floorZ, time, noiseStrength, octaves, noiseTex, s) - sdScene(p - ey, cubeHalfSize, floorZ, time, noiseStrength, octaves, noiseTex, s);
    float gradZ = sdScene(p + ez, cubeHalfSize, floorZ, time, noiseStrength, octaves, noiseTex, s) - sdScene(p - ez, cubeHalfSize, floorZ, time, noiseStrength, octaves, noiseTex, s);

    return normalize(float3(gradX, gradY, gradZ));
}

// Returns (distance, shapeIndex)
static inline float2 rayMarch(float3 rayOri, float3 rayDir, float cubeHalfSize, float floorZ, float time, float noiseStrength, int octaves, int maxSteps, texture2d<float> noiseTex, sampler s) {
    const float MAX_TRACE_DISTANCE = 20.0f;

    float totalDistance = 0.0f;
    float shapeIndex = -1.0f;

    for (int i = 0; i < maxSteps; ++i) {
        float2 res = mapScene(rayOri + totalDistance * rayDir, cubeHalfSize, floorZ, time, noiseStrength, octaves, noiseTex, s);
        float minHitDistance = max(0.0005f * totalDistance, 0.0005f);

        if (res.x < minHitDistance) {
            shapeIndex = res.y;
            break;
        }
        if (totalDistance > MAX_TRACE_DISTANCE) break;
        totalDistance += res.x;
    }

    return float2(totalDistance, shapeIndex);
}

// === Pool floor (procedural aqua tiles + white grout) ===
static inline float groutMask(float2 uv, float tilesPerUnit, float lineWidth) {
    // Returns 1.0 for grout, 0.0 for tile.
    float2 tileUV = fract(uv * tilesPerUnit);
    float2 distFromEdge = min(tileUV, 1.0f - tileUV);
    float minDist = min(distFromEdge.x, distFromEdge.y);
    float halfLine = lineWidth * 0.5f;
    // Cheap anti-alias: widen edge slightly with a constant. (We can switch to fwidth later if needed.)
    return 1.0f - smoothstep(0.0f, halfLine + 0.002f, minDist);
}

static inline float3 poolFloorBaseColor(float3 worldPos, float time, float3 tileColor, texture2d<float> noiseTex, sampler s) {
    // World-space XY tiling (backdrop plane faces camera).
    float2 uv = worldPos.xy;

    // Tile frequency and grout thickness in tile UV space.
    constexpr float tilesPerUnit = 0.75f;
    constexpr float lineWidth = 0.07f;

    float g = groutMask(uv, tilesPerUnit, lineWidth);

    // Grout color remains white
    float3 groutColor = float3(0.95f, 0.96f, 0.95f);

    // Slight per-tile variation so it doesn't read perfectly flat.
    float2 tileID = floor(uv * tilesPerUnit);
    float v = noise3D(float3(tileID * 0.25f, 0.0f) + float3(0.0f, 0.0f, time * 0.03f), noiseTex, s);
    float3 variedTileColor = tileColor * (0.92f + 0.08f * v);

    float3 base = mix(variedTileColor, groutColor, g);

    // Subtle caustic-ish modulation (kept gentle).
    float c = 0.5f + 0.5f * noise3D(float3(uv * 0.8f, time * 0.1f), noiseTex, s);
    base *= mix(0.92f, 1.12f, c);

    return clamp(base, 0.0f, 1.0f);
}

// Simple procedural environment "sky" in sRGB-ish space.
static inline float3 skyColor(float3 dir, float time, texture2d<float> noiseTex, sampler s) {
    float3 d = normalize(dir);
    float t = clamp(0.5f * (d.y + 1.0f), 0.0f, 1.0f);

    float3 horizon = float3(0.85f, 0.92f, 1.0f);
    float3 zenith  = float3(0.08f, 0.12f, 0.22f);
    float3 col = mix(horizon, zenith, powr(t, 1.2f));

    // Very subtle "cloud" modulation from the noise texture (kept small to avoid banding).
    float n = noise3D(d * 4.0f + float3(0.0f, 0.0f, time * 0.05f), noiseTex, s);
    col += 0.04f * n;

    return clamp(col, 0.0f, 1.0f);
}

static inline float3 render(float3 rayOri, float3 rayDir, float cubeHalfSize, float floorZ, float time,
                            float3 tileColor, float refractIndex, float3 cubeTint, float noiseStrength,
                            int octaves, int maxSteps, texture2d<float> noiseTex, sampler s) {
    time /= 2.0;

    // Match Shadertoy's "sample then pow(2.2)" workflow (treat skyColor as sRGB-ish).
    float3 color = powr(skyColor(rayDir, time, noiseTex, s), float3(2.2f));

    float2 res = rayMarch(rayOri, rayDir, cubeHalfSize, floorZ, time, noiseStrength, octaves, maxSteps, noiseTex, s);
    int shapeIndex = int(res.y);

    if (shapeIndex >= 0) {
        float3 pos = rayOri + rayDir * res.x;
        if (shapeIndex == 1) {
            // Backdrop plane: diffuse tile shading
            float3 base = powr(poolFloorBaseColor(pos, time, tileColor, noiseTex, s), float3(2.2f));
            // Plane normal points toward camera (+Z direction)
            float3 n = float3(0.0f, 0.0f, 1.0f);
            float3 l = normalize(float3(0.35f, 1.0f, 0.8f));
            float ndl = clamp(dot(n, l), 0.0f, 1.0f);
            float ambient = 0.55f;
            float3 lit = base * (ambient + 0.85f * ndl);
            // Slight sheen
            float3 h = normalize(l - rayDir);
            float spec = powr(clamp(dot(n, h), 0.0f, 1.0f), 32.0f) * 0.12f;
            color = lit + spec;
        } else {
            // Cube: refractive
            float3 normal = calculateNormal(pos, cubeHalfSize, floorZ, time, noiseStrength, octaves, noiseTex, s);
            float3 refractDir = refract(rayDir, normal, refractIndex);

            // If refracted ray goes backward (-Z), intersect the backdrop plane analytically and sample tiles.
            float3 refractedSample = skyColor(refractDir, time, noiseTex, s);
            if (refractDir.z < -1e-3f) {
                float tPlane = (floorZ - pos.z) / refractDir.z;
                if (tPlane > 0.0f && tPlane < 50.0f) {
                    float3 hit = pos + refractDir * tPlane;
                    refractedSample = poolFloorBaseColor(hit, time, tileColor, noiseTex, s);
                }
            }

            color = powr(refractedSample, float3(2.2f)) * 0.9f;
            color *= cubeTint;
        }
    }

    return color;
}

// === Fragment ===
#define AA 1

fragment half4 refractNoiseFrag(
    VertexOut in [[stage_in]],
    constant Uniforms& u [[buffer(0)]],
    constant Parameters& p [[buffer(1)]],
    texture2d<float> noiseTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    // Compute dynamic quality settings from LOD
    // LOD 1.0 = 4 octaves, 64 steps (full quality)
    // LOD 0.0 = 1 octave, 16 steps (minimum quality)
    float lod = clamp(u.lod, 0.0f, 1.0f);
    int octaves = int(mix(1.0f, 4.0f, lod) + 0.5f);
    int maxSteps = int(mix(16.0f, 64.0f, lod) + 0.5f);

    // Extract parameters
    float3 tileColor = float3(p.tileColorR, p.tileColorG, p.tileColorB);
    float3 cubeTint = float3(p.cubeTintR, p.cubeTintG, p.cubeTintB);

    float2 fragCoord = in.uv * u.resolution;
    float3 totalColor = float3(0.0f);

    // Camera directly in front, looking straight at origin.
    float camDist = 12.0f;
    float3 rayOri = float3(0.0f, 0.0f, camDist);
    float3 rayTgt = float3(0.0f);

    float3x3 viewMat = lookAt(rayOri, rayTgt, float3(0.0f, 1.0f, 0.0f));

    // Size the cube so it fills the viewport.
    // Ray at screen edge (uv = 0.5 or aspect/2) should just touch the cube corner.
    // With focal length 1.0, tan(halfFOV) = uvMax. For the near face at distance (D - S) from camera,
    // screen edge maps to x = (D - S) * uvMax. For cube edge: S = (D - S) * uvMax  =>  S = D * uvMax / (1 + uvMax).
    float aspect = u.resolution.y / max(u.resolution.x, 1.0f);
    float uvMax = max(0.5f, 0.5f * aspect);  // whichever axis is larger in UV space
    float cubeHalfSize = (camDist * uvMax) / (1.0f + uvMax);
    cubeHalfSize += 0.15f; // Add margin for max noise displacement
    cubeHalfSize = min(cubeHalfSize, camDist * 0.95f);
    // Backdrop plane behind the cube (negative Z, facing camera)
    float floorZ = -cubeHalfSize - 0.02f;

    for (int i = 0; i < AA; ++i)
    for (int k = 0; k < AA; ++k) {
        float2 offset = (float2(float(i) + 0.5f, float(k) + 0.5f) / float(AA)) - 0.5f;
        float2 uv = (fragCoord + offset - u.resolution * 0.5f) / u.resolution.x;
        float3 rayDir = normalize(viewMat * float3(uv, -1.0f));
        totalColor += render(rayOri, rayDir, cubeHalfSize, floorZ, u.time,
                             tileColor, p.refractIndex, cubeTint, p.noiseStrength,
                             octaves, maxSteps, noiseTex, s);
    }

    totalColor /= float(AA * AA);
    totalColor = powr(totalColor, float3(0.45f)); // gamma-ish to output
    return half4(half3(totalColor), 1.0h);
}
