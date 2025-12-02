[videoURL]: https://www.youtube.com/watch?v=8kX1CX-ujlA

# SwiftChartsAudioVisualizer

A Swift Package for creating real-time audio visualizers using Swift Charts. Stream audio from URLs and display FFT-based visualizations with an LCD-style bar chart interface.

[<img src="./videoLink.png" alt="Audio Visualizer with Swift Charts?" width="480"/>][videoURL]  
Check the video on [YouTube][videoURL]

## Installation

### Swift Package Manager

Add this package to your Xcode project:

1. File → Add Package Dependencies...
2. Enter the repository URL: `https://github.com/your-username/PlayerHeaderView`
3. Select your version requirements

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-username/PlayerHeaderView", from: "1.0.0")
]
```

## Usage

### Basic Example

```swift
import SwiftUI
import PlayerHeaderView

struct ContentView: View {
    var body: some View {
        PlayerHeaderView(
            streamURL: URL(string: "https://your-stream-url.mp3")!
        )
        .padding()
        .background(WXYCBackground())
    }
}
```

### Custom Integration

For more control, use the `StreamingAudioProcessor` directly:

```swift
import PlayerHeaderView

let processor = StreamingAudioProcessor.shared

// Start playback
processor.play(url: streamURL)

// Access FFT data for custom visualization
let magnitudes = processor.fftMagnitudes
let rmsPerBar = processor.rmsPerBar

// Control signal boost (1.0 = normal, up to 10.0)
processor.signalBoost = 2.0
```

## Features

- 🎵 Stream audio from any URL (MP3, AAC, etc.)
- 📊 Real-time FFT visualization using Swift Charts
- 🎚️ LCD-style segmented bar display
- 📱 iOS background audio and remote control support
- 🎛️ Configurable signal boost and smoothing

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 5.9+
- Xcode 15.0+

---

This WWDC, Apple introduced Swift Charts, a convenient way to add charts to your app with SwiftUI. But can it handle data that changes several times per second?  
This is a little experiment to test it, making an audio visualizer using the BarMark. And it actually runs a lot better than I would expect.

Reference Links:
- [But what is the Fourier Transform? A visual introduction](https://www.youtube.com/watch?v=spUNpyF58BY)
- [Audio Visualization in Swift Using Metal and Accelerate](https://betterprogramming.pub/audio-visualization-in-swift-using-metal-accelerate-part-1-390965c095d7)
- [Light Entertainment - Rack-mountable Spectrum Analyser & DB Meter](https://www.youtube.com/watch?v=CKvP4GjoLZc)
- [Paul Pitman - Moonlight Sonata Op. 27 No. 2 - III. Presto](https://musopen.org/music/2547-piano-sonata-no-14-in-c-sharp-minor-moonlight-sonata-op-27-no-2/)