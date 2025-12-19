//
//  WaterTurbulenceView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import SwiftUI
import ObservableDefaults

import Observation

@Observable
public final class WaterTurbulenceWallpaper: Wallpaper {
    public let displayName = "Water Turbulence"

    public var tilesAcross: Float { didSet { UserDefaults.standard.set(tilesAcross, forKey: "wallpaper.turbulence.tilesAcross") } }
    public var iterBaseSpeed: Float { didSet { UserDefaults.standard.set(iterBaseSpeed, forKey: "wallpaper.turbulence.iterBaseSpeed") } }
    public var iterSpread: Float { didSet { UserDefaults.standard.set(iterSpread, forKey: "wallpaper.turbulence.iterSpread") } }
    public var iterExponent: Float { didSet { UserDefaults.standard.set(iterExponent, forKey: "wallpaper.turbulence.iterExponent") } }
    public var contrastExponent: Float { didSet { UserDefaults.standard.set(contrastExponent, forKey: "wallpaper.turbulence.contrastExponent") } }
    public var rampPower: Float { didSet { UserDefaults.standard.set(rampPower, forKey: "wallpaper.turbulence.rampPower") } }
    public var lowR: Float { didSet { UserDefaults.standard.set(lowR, forKey: "wallpaper.turbulence.lowR") } }
    public var lowG: Float { didSet { UserDefaults.standard.set(lowG, forKey: "wallpaper.turbulence.lowG") } }
    public var lowB: Float { didSet { UserDefaults.standard.set(lowB, forKey: "wallpaper.turbulence.lowB") } }
    public var highR: Float { didSet { UserDefaults.standard.set(highR, forKey: "wallpaper.turbulence.highR") } }
    public var highG: Float { didSet { UserDefaults.standard.set(highG, forKey: "wallpaper.turbulence.highG") } }
    public var highB: Float { didSet { UserDefaults.standard.set(highB, forKey: "wallpaper.turbulence.highB") } }
    public var toneMapStrength: Float { didSet { UserDefaults.standard.set(toneMapStrength, forKey: "wallpaper.turbulence.toneMapStrength") } }
    public var maxBrightness: Float { didSet { UserDefaults.standard.set(maxBrightness, forKey: "wallpaper.turbulence.maxBrightness") } }
    public var gamma: Float { didSet { UserDefaults.standard.set(gamma, forKey: "wallpaper.turbulence.gamma") } }

    public init() {
        self.tilesAcross = UserDefaults.standard.float(forKey: "wallpaper.turbulence.tilesAcross") == 0 ? 1.0 : UserDefaults.standard.float(forKey: "wallpaper.turbulence.tilesAcross")
        self.iterBaseSpeed = UserDefaults.standard.object(forKey: "wallpaper.turbulence.iterBaseSpeed") == nil ? 0.04 : UserDefaults.standard.float(forKey: "wallpaper.turbulence.iterBaseSpeed")
        self.iterSpread = UserDefaults.standard.object(forKey: "wallpaper.turbulence.iterSpread") == nil ? 38.0 : UserDefaults.standard.float(forKey: "wallpaper.turbulence.iterSpread")
        self.iterExponent = UserDefaults.standard.object(forKey: "wallpaper.turbulence.iterExponent") == nil ? 4.0 : UserDefaults.standard.float(forKey: "wallpaper.turbulence.iterExponent")
        self.contrastExponent = UserDefaults.standard.object(forKey: "wallpaper.turbulence.contrastExponent") == nil ? 8.0 : UserDefaults.standard.float(forKey: "wallpaper.turbulence.contrastExponent")
        self.rampPower = UserDefaults.standard.object(forKey: "wallpaper.turbulence.rampPower") == nil ? 1.8 : UserDefaults.standard.float(forKey: "wallpaper.turbulence.rampPower")
        self.lowR = UserDefaults.standard.float(forKey: "wallpaper.turbulence.lowR")
        self.lowG = UserDefaults.standard.object(forKey: "wallpaper.turbulence.lowG") == nil ? 0.35 : UserDefaults.standard.float(forKey: "wallpaper.turbulence.lowG")
        self.lowB = UserDefaults.standard.object(forKey: "wallpaper.turbulence.lowB") == nil ? 0.50 : UserDefaults.standard.float(forKey: "wallpaper.turbulence.lowB")
        self.highR = UserDefaults.standard.object(forKey: "wallpaper.turbulence.highR") == nil ? 0.95 : UserDefaults.standard.float(forKey: "wallpaper.turbulence.highR")
        self.highG = UserDefaults.standard.object(forKey: "wallpaper.turbulence.highG") == nil ? 0.98 : UserDefaults.standard.float(forKey: "wallpaper.turbulence.highG")
        self.highB = UserDefaults.standard.object(forKey: "wallpaper.turbulence.highB") == nil ? 1.00 : UserDefaults.standard.float(forKey: "wallpaper.turbulence.highB")
        self.toneMapStrength = UserDefaults.standard.object(forKey: "wallpaper.turbulence.toneMapStrength") == nil ? 1.0 : UserDefaults.standard.float(forKey: "wallpaper.turbulence.toneMapStrength")
        self.maxBrightness = UserDefaults.standard.object(forKey: "wallpaper.turbulence.maxBrightness") == nil ? 0.92 : UserDefaults.standard.float(forKey: "wallpaper.turbulence.maxBrightness")
        self.gamma = UserDefaults.standard.object(forKey: "wallpaper.turbulence.gamma") == nil ? 2.2 : UserDefaults.standard.float(forKey: "wallpaper.turbulence.gamma")
    }

    public func makeView() -> some View {
        WaterTurbulenceView(configuration: self)
    }

    public func makeDebugControls() -> WaterTurbulenceDebugControls? {
        WaterTurbulenceDebugControls(configuration: self)
    }

    public func reset() {
        tilesAcross = 1.0
        iterBaseSpeed = 0.04
        iterSpread = 38.0
        iterExponent = 4.0
        contrastExponent = 8.0
        rampPower = 1.8
        lowR = 0.00
        lowG = 0.35
        lowB = 0.50
        highR = 0.95
        highG = 0.98
        highB = 1.00
        toneMapStrength = 1.0
        maxBrightness = 0.92
        gamma = 2.2
    }
}

/// Water turbulence shader effect with configurable parameters
public struct WaterTurbulenceView: View {
    @Environment(\.displayScale) private var displayScale
    @State private var start = Date()
    @Bindable var configuration: WaterTurbulenceWallpaper

    public var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { proxy in
                let size = proxy.size
                let time = Float(context.date.timeIntervalSince(start))

                let rampLow = SIMD3<Float>(configuration.lowR, configuration.lowG, configuration.lowB)
                let rampHigh = SIMD3<Float>(configuration.highR, configuration.highG, configuration.highB)

                Rectangle()
                    .fill(.black)
                    .colorEffect(
                        ShaderLibrary.bundle(.module).waterTurbulence(
                            .float(time),
                            .float2(Float(size.width), Float(size.height)),
                            .float(Float(displayScale)),
                            .float(configuration.tilesAcross),
                            .float(configuration.contrastExponent),
                            .float(configuration.rampPower),
                            .float3(rampLow.x, rampLow.y, rampLow.z),
                            .float3(rampHigh.x, rampHigh.y, rampHigh.z),
                            .float(configuration.toneMapStrength),
                            .float(configuration.maxBrightness),
                            .float(configuration.gamma),
                            .float(configuration.iterBaseSpeed),
                            .float(configuration.iterSpread),
                            .float(configuration.iterExponent)
                        )
                    )
                    .ignoresSafeArea()
            }
        }
        .onAppear { start = Date() }
    }
}

public struct WaterTurbulenceDebugControls: View {
    @Bindable var configuration: WaterTurbulenceWallpaper

    public var body: some View {
        Group {
            Text("Tiling").font(.subheadline).foregroundStyle(.secondary)
            parameterSlider("Tiles Across", value: $configuration.tilesAcross, range: 0.25...6.0)
        }

        Group {
            Text("Iteration Speed").font(.subheadline).foregroundStyle(.secondary)
            parameterSlider("Base Speed", value: $configuration.iterBaseSpeed, range: 0.0...4.0)
            parameterSlider("Spread", value: $configuration.iterSpread, range: 0.0...64.0)
            parameterSlider("Exponent", value: $configuration.iterExponent, range: 0.25...4.0)
        }

        Group {
            Text("Contrast + Tone").font(.subheadline).foregroundStyle(.secondary)
            parameterSlider("Contrast Exponent", value: $configuration.contrastExponent, range: 0.5...16.0)
            parameterSlider("Tone Map Strength", value: $configuration.toneMapStrength, range: 0.0...1.0)
            parameterSlider("Max Brightness", value: $configuration.maxBrightness, range: 0.1...1.0)
            parameterSlider("Gamma", value: $configuration.gamma, range: 1.0...3.0)
        }

        Group {
            Text("Color Ramp").font(.subheadline).foregroundStyle(.secondary)
            parameterSlider("Ramp Power", value: $configuration.rampPower, range: 0.25...6.0)

            Text("Low Color").font(.caption).foregroundStyle(.tertiary)
            parameterSlider("Red", value: $configuration.lowR, range: 0.0...1.0)
            parameterSlider("Green", value: $configuration.lowG, range: 0.0...1.0)
            parameterSlider("Blue", value: $configuration.lowB, range: 0.0...1.0)

            Text("High Color").font(.caption).foregroundStyle(.tertiary)
            parameterSlider("Red", value: $configuration.highR, range: 0.0...1.0)
            parameterSlider("Green", value: $configuration.highG, range: 0.0...1.0)
            parameterSlider("Blue", value: $configuration.highB, range: 0.0...1.0)

            HStack(spacing: 12) {
                colorSwatch(
                    red: configuration.lowR,
                    green: configuration.lowG,
                    blue: configuration.lowB
                )
                colorSwatch(
                    red: configuration.highR,
                    green: configuration.highG,
                    blue: configuration.highB
                )
            }
        }
    }

    private func parameterSlider(_ title: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func colorSwatch(red: Float, green: Float, blue: Float) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(red: Double(red), green: Double(green), blue: Double(blue)))
            .frame(width: 44, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.primary.opacity(0.2), lineWidth: 1)
            )
    }
}
