# Box Suite Wallpaper Variant

Create a new "Box Suite" wallpaper variant with a low-poly water surface aesthetic using single-octave 2D Perlin noise with linear interpolation, pink tiles, white grout, and configurable grid size.

## Proposed Changes

### BoxSuite Theme

#### [NEW] [BoxSuite.metal](file:///Users/jake/Developer/wxyc-ios-64-copy/Shared/Wallpaper/Sources/Wallpaper/Resources/Wallpapers/BoxSuite/BoxSuite.metal)

Metal shader based on PoolSuite with the following key changes:

1. **Replace smoothstep with linear interpolation** in `noise3D()`:
   ```diff
   -f = f * f * (3.0f - 2.0f * f);  // smoothstep
   +// f = fract(x) - use linear interpolation directly
   ```

2. **Single-octave noise** instead of multi-octave fBm:
   - Bypass the octave loop, use just one noise sample
   - Add `noiseScale` parameter to control the facet size

3. **New fragment function** `boxSuiteFrag` to avoid conflicts

---

#### [NEW] [box_suite.json](file:///Users/jake/Developer/wxyc-ios-64-copy/Shared/Wallpaper/Sources/Wallpaper/Resources/Wallpapers/BoxSuite/box_suite.json)

Theme manifest with:
- **Pink tiles** (default RGB: ~0.95, 0.5, 0.6)
- **White grout** (hardcoded in shader: 0.95, 0.96, 0.95)
- **New `noiseScale` parameter** for grid/facet size control
  - Range: 0.1 to 2.0, default: 0.5
  - Lower = larger facets, higher = smaller facets

Parameters:
| Parameter | Default | Range | Purpose |
|-----------|---------|-------|---------|
| tileColorR | 0.95 | 0-1 | Pink tile red |
| tileColorG | 0.5 | 0-1 | Pink tile green |
| tileColorB | 0.6 | 0-1 | Pink tile blue |
| noiseScale | 0.5 | 0.1-2.0 | Grid/facet size |
| refractIndex | 0.8 | 0.5-1.0 | Refraction amount |
| cubeTintR/G/B | 0.9/0.6/0.7 | 0-1 | Pink cube tint |
| noiseStrength | 0.15 | 0.05-0.3 | Surface displacement |

## Verification Plan

### Automated Tests

Run the existing Wallpaper package tests to ensure the new theme is properly discovered:

```bash
swift test --package-path Shared/Wallpaper --filter ThemeManifestTests
```

The "All registered themes have valid material properties" test will validate that `box_suite` is loaded and has valid configuration.

### Manual Verification

1. Build the iOS app and navigate to the theme picker
2. Verify "Box Suite" appears in the carousel
3. Confirm the shader renders with:
   - Visible faceted/low-poly water surface
   - Pink tiles with white grout lines
4. Adjust the `noiseScale` parameter in debug overlay to confirm grid size changes
