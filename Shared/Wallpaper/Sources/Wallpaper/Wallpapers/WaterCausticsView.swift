//
//  WaterCausticsView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import SwiftUI
import Observation

@Observable
public final class WaterCausticsWallpaper: Wallpaper {
    public let displayName = "Water Caustics"
    
    public var offsetX: Float { didSet { UserDefaults.standard.set(offsetX, forKey: "wallpaper.caustics.offsetX") } }
    public var offsetY: Float { didSet { UserDefaults.standard.set(offsetY, forKey: "wallpaper.caustics.offsetY") } }

    public init() {
        self.offsetX = UserDefaults.standard.object(forKey: "wallpaper.caustics.offsetX") == nil ? 0.5 : UserDefaults.standard.float(forKey: "wallpaper.caustics.offsetX")
        self.offsetY = UserDefaults.standard.object(forKey: "wallpaper.caustics.offsetY") == nil ? 0.5 : UserDefaults.standard.float(forKey: "wallpaper.caustics.offsetY")
    }
    
    public func makeView() -> WaterCausticsView {
        WaterCausticsView(configuration: self)
    }
    
    public func makeDebugControls() -> WaterCausticsDebugControls? {
        WaterCausticsDebugControls(configuration: self)
    }
    
    public func reset() {
        offsetX = 0.5
        offsetY = 0.5
    }
}

/// Water caustics shader effect
public struct WaterCausticsView: View {
    @Environment(\.displayScale) private var displayScale
    @State private var start = Date()
    @Bindable var configuration: WaterCausticsWallpaper

    public var body: some View {
        TimelineView(.animation) { ctx in
            GeometryReader { proxy in
                let wPx = Float(proxy.size.width * displayScale)
                let hPx = Float(proxy.size.height * displayScale)
                let t = Float(ctx.date.timeIntervalSince(start)) / 3.0

                Rectangle()
                    .fill(.white)
                    .colorEffect(
                        ShaderLibrary.bundle(.module).waterCaustics(
                            .float2(wPx, hPx),
                            .float(t),
                            .float2(configuration.offsetX, configuration.offsetY)
                        )
                    )
                    .ignoresSafeArea()
            }
        }
    }
}

public struct WaterCausticsDebugControls: View {
    @Bindable var configuration: WaterCausticsWallpaper

    public var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("X Offset")
                    Spacer()
                    Text(String(format: "%.2f", configuration.offsetX))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $configuration.offsetX, in: 0.0...1.0)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Y Offset")
                    Spacer()
                    Text(String(format: "%.2f", configuration.offsetY))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $configuration.offsetY, in: 0.0...1.0)
            }
        }
    }
}
