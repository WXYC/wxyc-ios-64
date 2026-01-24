# App Store Asset Pipeline

Tools for processing screen recordings and screenshots into Apple App Store formats, with API upload support.

## Quick Start

### App Previews (Videos)

```bash
# Process a recording for the required iPhone size (6.9")
./process-preview.sh -d iphone-6.9 -p recording.mov

# Generate all required sizes (6.9" iPhone + 13" iPad)
./process-preview.sh -a recording.mov
```

### Screenshots

```bash
# Process a screenshot for iPhone 6.9"
./process-screenshot.sh -d iphone-6.9 -p screenshot.png

# Generate all required sizes
./process-screenshot.sh -a screenshot.png

# Process for Apple Watch
./process-screenshot.sh -d watch-ultra3 watch_screenshot.png
```

### Upload to App Store Connect

```bash
# Build the upload tool (one time)
./build-upload-tool.sh

# Upload
./upload-preview \
    --key-id YOUR_KEY_ID \
    --issuer-id YOUR_ISSUER_ID \
    --private-key ~/AuthKey.p8 \
    --preview-set-id PREVIEW_SET_ID \
    preview_iphone-6.9_portrait.mp4
```

## Apple App Store Preview Specifications

### Video Format Requirements

| Setting | H.264 | ProRes 422 HQ |
|---------|-------|---------------|
| Bit rate | 10-12 Mbps | ~220 Mbps VBR |
| Profile | High Profile Level 4.0 | Progressive |
| Max frame rate | 30 fps | 30 fps |
| File formats | .mov, .m4v, .mp4 | .mov |

### Audio Requirements

- Codec: AAC (256 kbps) or PCM
- Sample rate: 44.1 kHz or 48 kHz
- Channels: Stereo

### Duration & Size

- Minimum: 15 seconds
- Maximum: 30 seconds
- Max file size: 500 MB

### Required Device Resolutions

As of 2025, App Store Connect requires these two sizes (others are scaled automatically):

| Device | Portrait | Landscape |
|--------|----------|-----------|
| **6.9" iPhone** (required) | 886 x 1920 | 1920 x 886 |
| **13" iPad** (required) | 1200 x 1600 | 1600 x 1200 |

### All Supported Resolutions

#### iPhone

| Display | Portrait | Landscape |
|---------|----------|-----------|
| 6.9" | 886 x 1920 | 1920 x 886 |
| 6.5" | 886 x 1920 | 1920 x 886 |
| 6.3" | 886 x 1920 | 1920 x 886 |
| 6.1" | 886 x 1920 | 1920 x 886 |
| 5.5" | 1080 x 1920 | 1920 x 1080 |
| 4.7" | 750 x 1334 | 1334 x 750 |

#### iPad

| Display | Portrait | Landscape |
|---------|----------|-----------|
| 13" | 1200 x 1600 | 1600 x 1200 |
| 11" | 1200 x 1600 | 1600 x 1200 |
| 10.5" | 1200 x 1600 | 1600 x 1200 |
| 9.7" | 900 x 1200 | 1200 x 900 |

#### Other Platforms

| Platform | Resolution |
|----------|------------|
| Apple TV | 1920 x 1080 (landscape only) |
| Mac | 1920 x 1080 (landscape only) |
| Apple Vision Pro | 3840 x 2160 (landscape only) |

## Processing Script (`process-preview.sh`)

### Usage

```bash
./process-preview.sh [OPTIONS] <input-video>
```

### Options

| Option | Description |
|--------|-------------|
| `-d, --device <device>` | Target device (e.g., `iphone-6.9`, `ipad-13`) |
| `-o, --output <path>` | Output file path |
| `-O, --output-dir <dir>` | Output directory |
| `-a, --all` | Generate all required sizes |
| `-p, --portrait` | Force portrait orientation |
| `-l, --landscape` | Force landscape orientation |
| `-t, --trim <start:end>` | Trim video (e.g., `0:25` for first 25 seconds) |
| `-s, --scale <mode>` | Scale mode: `fit`, `fill`, `crop` |
| `--prores` | Output ProRes 422 HQ instead of H.264 |
| `--dry-run` | Show commands without executing |
| `-v, --verbose` | Verbose output |

### Scale Modes

- **fit** (default): Scale to fit within bounds, add letterbox/pillarbox if needed
- **fill**: Scale to fill bounds, crop excess
- **crop**: Center crop to exact size

### Examples

```bash
# Process for 6.9" iPhone portrait
./process-preview.sh -d iphone-6.9 -p my_recording.mov

# Process for iPad landscape with fill scaling
./process-preview.sh -d ipad-13 -l -s fill my_recording.mov

# Trim to 25 seconds and generate all required sizes
./process-preview.sh -a -t 0:25 my_recording.mov

# Output ProRes for further editing
./process-preview.sh -d iphone-6.9 --prores my_recording.mov

# Preview what would happen without processing
./process-preview.sh -a --dry-run my_recording.mov
```

## Screenshot Script (`process-screenshot.sh`)

Processes screenshots into App Store required formats using macOS's native `sips` tool.

### Usage

```bash
./process-screenshot.sh [OPTIONS] <input-image>
```

### Options

| Option | Description |
|--------|-------------|
| `-d, --device <device>` | Target device |
| `-o, --output <path>` | Output file path |
| `-O, --output-dir <dir>` | Output directory |
| `-a, --all` | Generate all required sizes |
| `-p, --portrait` | Force portrait orientation |
| `-l, --landscape` | Force landscape orientation |
| `-f, --format <fmt>` | Output format: `png`, `jpg` (default: png) |
| `-q, --quality <1-100>` | JPEG quality (default: 95) |
| `-s, --scale <mode>` | Scale mode: `fit`, `fill`, `crop` (default: fill) |
| `-b, --background <color>` | Background color for letterboxing (hex, default: FFFFFF) |
| `--dry-run` | Show what would be done |
| `-v, --verbose` | Verbose output |

### Supported Devices

**iPhone**: `iphone-6.9`, `iphone-6.5`, `iphone-6.3`, `iphone-6.1`, `iphone-5.5`, `iphone-4.7`

**iPad**: `ipad-13`, `ipad-12.9`, `ipad-11`, `ipad-10.5`, `ipad-9.7`

**Mac**: `mac-16x10`, `mac-16x10-small`

**Apple TV**: `appletv-4k`, `appletv-hd`

**Apple Vision Pro**: `visionpro`

**Apple Watch**: `watch-ultra3`, `watch-ultra`, `watch-series10`, `watch-series9`, `watch-series6`, `watch-series3`

### Screenshot Dimensions

| Device | Portrait | Landscape |
|--------|----------|-----------|
| **iPhone 6.9"** (required) | 1320 x 2868 | 2868 x 1320 |
| **iPad 13"** (required) | 2064 x 2752 | 2752 x 2064 |
| **Mac** (required) | - | 2880 x 1800 |
| **Apple TV** (required) | - | 1920 x 1080 |
| **Vision Pro** (required) | - | 3840 x 2160 |
| **Watch Ultra 3** (required) | 422 x 514 | - |

### Examples

```bash
# Process for iPhone with fill scaling (crops to fit)
./process-screenshot.sh -d iphone-6.9 -p screenshot.png

# Process with fit scaling (adds letterbox)
./process-screenshot.sh -d ipad-13 -s fit -b 000000 screenshot.png

# Output as JPEG with 90% quality
./process-screenshot.sh -d iphone-6.9 -f jpg -q 90 screenshot.png

# Process Apple Watch screenshot
./process-screenshot.sh -d watch-ultra3 watch.png
```

## Upload Script (`upload-preview`)

### Building

The upload tool must be compiled before first use:

```bash
./build-upload-tool.sh
```

This creates the `upload-preview` binary.

### Prerequisites

1. Create an API key in [App Store Connect](https://appstoreconnect.apple.com/access/integrations/api)
2. Download the `.p8` private key file
3. Note your Key ID and Issuer ID

### Finding Your Preview Set ID

You can find the Preview Set ID by:

1. Using the App Store Connect API to list your app's versions and localizations
2. Inspecting network requests in the App Store Connect web interface
3. Using a tool like [Fastlane](https://fastlane.tools) which can discover these IDs

### Usage

```bash
./upload-preview \
    --key-id <key-id> \
    --issuer-id <issuer-id> \
    --private-key <path-to-p8-file> \
    --preview-set-id <preview-set-id> \
    <video-file>
```

### API Workflow

The script performs these steps:

1. **Reservation**: Creates an upload reservation with file metadata
2. **Chunked Upload**: Splits and uploads the file in parallel chunks
3. **Checksum**: Calculates MD5 checksum for verification
4. **Commit**: Commits the upload with the checksum
5. **Polling**: Waits for App Store Connect to process the video

## Recording Tips

### iOS Simulator

```bash
# Start recording
xcrun simctl io booted recordVideo preview.mov

# Stop with Ctrl+C
```

### Physical Device

Use QuickTime Player:
1. Connect your device
2. File > New Movie Recording
3. Click the dropdown next to record button
4. Select your device

### Screen Capture (macOS)

```bash
# Record entire screen
screencapture -v preview.mov

# Or use Command+Shift+5
```

## Dependencies

- **ffmpeg**: Video processing (`brew install ffmpeg`)
- **Swift 5.9+**: For the upload script (included with Xcode)

## Troubleshooting

### Video rejected for wrong dimensions

Make sure you're using the exact required dimensions. The script uses `fit` mode by default which may add letterboxing. Try `fill` or `crop` mode if your source has different aspect ratio:

```bash
./process-preview.sh -d iphone-6.9 -s fill recording.mov
```

### Video too long

Use the trim option to cut to 30 seconds or less:

```bash
./process-preview.sh -d iphone-6.9 -t 0:30 recording.mov
```

### Upload authentication fails

Verify your API credentials:
- Key ID matches the downloaded `.p8` file name
- Issuer ID is correct (found on API Keys page)
- Private key file path is correct and readable

### Processing takes too long

Large ProRes files can take time. After committing, App Store Connect may take up to 24 hours to fully process the preview.

## Sources

- [Apple App Preview Specifications](https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications/)
- [Uploading App Previews API](https://developer.apple.com/documentation/appstoreconnectapi/app_store/app_metadata/uploading_app_previews)
- [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi/)
