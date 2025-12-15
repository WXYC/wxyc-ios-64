#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Random function
static inline float noise_rand(float2 co) {
    return fract(sin(dot(co, float2(12.9898, 78.233))) * 43758.5453123);
}

[[ stitchable ]] half4 noiseFragment(float2 position, float time, float noiseIntensity, float frequency) {
    // Calculate time steps for interpolation
    float t = time * frequency;
    float t1 = floor(t);
    float t2 = t1 + 1.0;
    
    // Generate noise for current and next step
    float n1 = noise_rand(position + float2(t1 * 12.9898)); // Multiply to ensure different seeds
    float n2 = noise_rand(position + float2(t2 * 12.9898));
    
    // Smooth interpolation
    float f = fract(t);
    
    // Center noise around 0 (ranges from -0.5 to +0.5 instead of 0 to 1)
    // This prevents the noise from adding overall brightness
    float n = mix(n1, n2, f) - 0.5;
    half value = half(n * noiseIntensity);
    
    // Return premultiplied alpha for correct blending in SwiftUI
    // Use abs(value) for alpha to avoid negative alpha causing flicker
    return half4(value, value, value, abs(value));
}
