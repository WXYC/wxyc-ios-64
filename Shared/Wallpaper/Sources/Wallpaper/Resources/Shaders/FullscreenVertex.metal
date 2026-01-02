#include <metal_stdlib>
using namespace metal;

// === Shared MTKView Support for Stitchable Shaders ===
// This file provides the common vertex shader and data structures
// used by all stitchable shader fragment wrappers.

struct Uniforms {
    float2 resolution;
    float time;
    float displayScale;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Fullscreen triangle - 3 vertices cover entire screen
// Uses clever bit manipulation: vid 0 -> (0,0), vid 1 -> (2,0), vid 2 -> (0,2)
vertex VertexOut fullscreenVertex(uint vid [[vertex_id]]) {
    VertexOut out;
    out.uv = float2((vid << 1) & 2, vid & 2);
    out.position = float4(out.uv * 2.0 - 1.0, 0.0, 1.0);
    out.uv.y = 1.0 - out.uv.y;  // Flip Y for Metal coordinates
    return out;
}

// Simple texture blit for upscaling during thermal throttling
fragment half4 blitFragment(VertexOut in [[stage_in]],
                            texture2d<half> tex [[texture(0)]],
                            sampler samp [[sampler(0)]]) {
    return tex.sample(samp, in.uv);
}
