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
    
    float n = mix(n1, n2, f);
    half alpha = half(n * noiseIntensity);
    
    // Return premultiplied alpha for correct blending in SwiftUI
    return half4(alpha, alpha, alpha, alpha);
}
