# Wallpaper

A data-driven, manifest-based system for rendering animated Metal shader wallpapers in SwiftUI.

## Overview

The Wallpaper package provides a flexible architecture for displaying GPU-accelerated animated backgrounds. Wallpapers are defined by JSON manifests that specify rendering configuration, parameters, and shader arguments. The system supports multiple renderer types and includes a built-in picker UI for wallpaper selection.

## Architecture Evolution

The current architecture emerged through several iterations:

1. **Initial modularization** - Separated wallpaper rendering into its own Swift package
2. **Manifest-based architecture** - Replaced hardcoded wallpaper classes with JSON manifests (`wallpaper.json`) that declaratively configure each wallpaper
3. **Auto-discovery** - Wallpapers are automatically discovered by scanning the bundle for valid manifest files
4. **Unified Metal renderer** - Consolidated multiple renderer implementations into a single `MetalWallpaperRenderer` that handles both stitchable and raw Metal modes
5. **Runtime shader compilation** - Added support for runtime compilation with toggleable `#define` directives for debug controls
6. **Wallpaper picker** - Added a carousel-based picker UI with snapshot previews and gesture-based activation

## Package Structure

```
Sources/Wallpaper/
├── Core/
│   ├── WallpaperManifest.swift      # JSON manifest model
│   ├── WallpaperRegistry.swift      # Wallpaper discovery and loading
│   ├── ParameterStore.swift         # Runtime parameter state
│   ├── ShaderDirectiveStore.swift   # Runtime directive toggles
│   └── RuntimeShaderCompiler.swift  # On-device shader compilation
├── Renderers/
│   ├── WallpaperRendererFactory.swift   # Routes to appropriate renderer
│   ├── MetalWallpaperRenderer.swift     # MTKView-based Metal rendering
│   ├── MetalWallpaperView.swift         # SwiftUI wrapper for Metal
│   ├── StitchableWallpaperView.swift    # SwiftUI shader modifier rendering
│   ├── CompositeWallpaperView.swift     # Multi-layer composition
│   └── SwiftUIWallpaperView.swift       # Pure SwiftUI rendering
├── Picker/
│   ├── WallpaperPickerContainer.swift   # Picker mode container
│   ├── WallpaperCarouselView.swift      # Horizontal wallpaper carousel
│   ├── WallpaperCardView.swift          # Individual wallpaper card
│   └── WallpaperSnapshotService.swift   # Generates static previews
├── Resources/
│   ├── Shaders/
│   │   └── FullscreenVertex.metal       # Shared vertex shader
│   └── Wallpapers/
│       └── <WallpaperName>/
│           ├── wallpaper.json           # Manifest
│           └── <WallpaperName>.metal    # Shader code
├── WallpaperView.swift              # Main entry point view
├── WallpaperConfiguration.swift     # Persisted selection state
└── WallpaperPickerState.swift       # Picker UI state
```

## Renderer Types

The `WallpaperRendererFactory` routes wallpapers to the appropriate renderer based on their manifest:

| Type | Description | Use Case |
|------|-------------|----------|
| `stitchable` | SwiftUI's `[[ stitchable ]]` shader system | Simple shaders using SwiftUI's built-in shader support |
| `rawMetal` | Direct MTKView rendering with runtime compilation | Complex shaders needing noise textures or directive toggles |
| `composite` | Multi-layer composition | Layering effects (e.g., gradient + shader overlay) |
| `swiftUI` | Pure SwiftUI views | Non-shader backgrounds |

For `stitchable` type wallpapers, if a `fragmentFunction` is specified in the manifest, the system uses MTKView-based rendering instead of SwiftUI's shader modifier (eliminating CPU overhead).

## Creating a Wallpaper

### 1. Create the manifest (`wallpaper.json`)

```json
{
  "id": "my_wallpaper",
  "displayName": "My Wallpaper",
  "version": "1.0.0",
  "renderer": {
    "type": "stitchable",
    "shaderFile": "MyWallpaper.metal",
    "functionName": "myWallpaper",
    "fragmentFunction": "myWallpaperFrag"
  },
  "parameters": [],
  "shaderArguments": [
    { "source": "viewWidth" },
    { "source": "viewHeight" },
    { "source": "time" }
  ]
}
```

### 2. Create the Metal shader

Shaders should define both a stitchable function (for SwiftUI) and a fragment function (for MTKView):

```metal
#include <metal_stdlib>
using namespace metal;
#include <SwiftUI/SwiftUI_Metal.h>

// Uniforms for MTKView rendering
struct Uniforms {
    float2 resolution;
    float time;
    float pad;  // or displayScale for stitchable mode
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Core implementation
static half4 myWallpaperImpl(float2 position, float width, float height, float time) {
    // Shader logic here
    return half4(1.0h);
}

// SwiftUI stitchable entry point
[[ stitchable ]]
half4 myWallpaper(float2 position, half4 color, float width, float height, float time) {
    return myWallpaperImpl(position, width, height, time);
}

// MTKView fragment entry point
fragment half4 myWallpaperFrag(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pos = in.uv * u.resolution;
    return myWallpaperImpl(pos, u.resolution.x, u.resolution.y, u.time);
}
```

### 3. Place in Resources

Create a folder under `Resources/Wallpapers/<WallpaperName>/` containing both the manifest and shader file.

## Raw Metal Mode

For shaders requiring noise textures or runtime directive toggles, use `rawMetal` renderer type:

```json
{
  "renderer": {
    "type": "rawMetal",
    "shaderFile": "MyShader.metal",
    "vertexFunction": "fullscreenVertex",
    "fragmentFunction": "myFragment",
    "timeScale": 0.5
  }
}
```

Raw Metal mode provides:
- **Noise texture** at fragment texture index 0
- **Sampler** with linear filtering and repeat addressing
- **Runtime compilation** if the `.metal` source file is bundled
- **Directive toggles** for `#define` statements in the shader

## Usage

### Basic Usage

```swift
import Wallpaper

struct ContentView: View {
    @State private var configuration = WallpaperConfiguration()

    var body: some View {
        ZStack {
            WallpaperView(configuration: configuration)
            // Your content here
        }
    }
}
```

### With Wallpaper Picker

```swift
import Wallpaper

struct ContentView: View {
    @State private var configuration = WallpaperConfiguration()
    @State private var pickerState = WallpaperPickerState()

    var body: some View {
        WallpaperPickerContainer(
            configuration: configuration,
            pickerState: pickerState
        ) {
            // Your content here
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    pickerState.enter(currentWallpaperID: configuration.selectedWallpaperID)
                }
        )
    }
}
```

### Environment Key

The picker provides an environment value to let content adjust its layout when the picker is active:

```swift
@Environment(\.isWallpaperPickerActive) private var isPickerActive
```

## Available Wallpapers

The package includes several built-in wallpapers:

- **ChromaWave** - Colorful wave patterns
- **Lamp4D** - 4D lamp projection effect
- **LavaLite** - Lava lamp simulation (rawMetal with noise)
- **NeonTopology** - Perlin noise topology with neon edges (multiple variants)
- **Plasma** - Classic plasma effect
- **PoolTilesGradient** - Pool tiles with gradient overlay
- **RefractNoise** - Refracted noise patterns
- **Turbulence** - Fluid turbulence simulation
- **TwinklingTunnel** - Animated tunnel with gyroid distance fields
- **WaterCaustics** - Underwater caustic lighting
- **WaterTurbulence** - Water surface turbulence
- **Windowlight** - Window light simulation
- **WXYCGradient** - WXYC branded mesh gradient (SwiftUI)

## Performance Considerations

- Shaders use `fast::` math functions where possible
- Iteration counts are tuned for 60fps on typical devices
- `fast_tanh()` approximations replace expensive tone mapping
- Snapshot service generates half-resolution previews for the picker
- Only the centered wallpaper renders live in the picker carousel

## Dependencies

- [ObservableDefaults](https://github.com/fatbobman/ObservableDefaults) - For persisting configuration to UserDefaults
