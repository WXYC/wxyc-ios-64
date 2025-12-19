//
//  NoiseOverlayView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import SwiftUI
import ObservableDefaults

import Observation

@Observable
public final class WXYCGradientWithNoiseWallpaper: Wallpaper {
    public let displayName = "WXYC Gradient + Noise"
    
    private let intensityKey = "wallpaper.noise.intensity"
    private let frequencyKey = "wallpaper.noise.frequency"

    public var intensity: Float {
        didSet {
            UserDefaults.standard.set(intensity, forKey: intensityKey)
        }
    }

    public var frequency: Float {
        didSet {
            UserDefaults.standard.set(frequency, forKey: frequencyKey)
        }
    }
    
    public init() {
        self.intensity = UserDefaults.standard.float(forKey: "wallpaper.noise.intensity") == 0 ? 0.5 : UserDefaults.standard.float(forKey: "wallpaper.noise.intensity")
        self.frequency = UserDefaults.standard.float(forKey: "wallpaper.noise.frequency") == 0 ? 10.0 : UserDefaults.standard.float(forKey: "wallpaper.noise.frequency")
        
        // Handle the case where 0.0 is the actual stored value by specifically checking if key exists
        if UserDefaults.standard.object(forKey: intensityKey) == nil { self.intensity = 0.5 }
        if UserDefaults.standard.object(forKey: frequencyKey) == nil { self.frequency = 10.0 }
    }
    
    public func makeView() -> some View {
        WXYCGradientWithNoiseView(configuration: self)
    }
    
    public func makeDebugControls() -> WXYCGradientWithNoiseDebugControls? {
        WXYCGradientWithNoiseDebugControls(configuration: self)
    }
    
    public func reset() {
        intensity = 0.5
        frequency = 10.0
    }
}

public struct WXYCGradientWithNoiseView: View {
    @Bindable var configuration: WXYCGradientWithNoiseWallpaper

    public var body: some View {
        ZStack {
            Rectangle().fill(WXYCGradientWallpaper())
            NoiseOverlayView(
                intensity: configuration.intensity,
                frequency: configuration.frequency
            )
        }
        .ignoresSafeArea()
    }
}

public struct WXYCGradientWithNoiseDebugControls: View {
    @Bindable var configuration: WXYCGradientWithNoiseWallpaper

    public var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Intensity")
                    Spacer()
                    Text(String(format: "%.2f", configuration.intensity))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $configuration.intensity, in: 0.0...10.0)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Frequency")
                    Spacer()
                    Text(String(format: "%.2f", configuration.frequency))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $configuration.frequency, in: 0.0...100.0)
            }
        }
    }
}

/// Animated noise overlay effect
public struct NoiseOverlayView: View {
    @State private var startTime = Date()
    public let intensity: Float
    public let frequency: Float

    public init(intensity: Float = 0.5, frequency: Float = 10.0) {
        self.intensity = intensity
        self.frequency = frequency
    }

    public var body: some View {
        TimelineView(.animation) { timelineContext -> Canvas<EmptyView> in
            let time = Float(timelineContext.date.timeIntervalSince(startTime))

            Canvas { graphicsContext, size in
                graphicsContext.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .shader(ShaderLibrary.bundle(.module).noiseFragment(
                        .float(time),
                        .float(intensity),
                        .float(frequency)
                    ))
                )
            }
        }
        .allowsHitTesting(false)
    }
}
