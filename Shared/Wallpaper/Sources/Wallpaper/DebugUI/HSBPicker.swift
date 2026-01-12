//
//  HSBPicker.swift
//  Wallpaper
//
//  HSB color picker with gradient sliders for debug UI.
//

import SwiftUI

// MARK: - HSB Picker

/// A picker for adjusting Hue, Saturation, and Brightness values.
struct HSBPicker: View {
    @Binding var hueDegrees: Double     // 0...360
    @Binding var saturation: Double     // 0...1
    @Binding var brightness: Double     // 0...1

    var body: some View {
        VStack(spacing: 12) {
            HSBSliderRow(label: "H") {
                GradientSlider(
                    value: Binding(
                        get: { hueDegrees / 360.0 },
                        set: { hueDegrees = min(max($0, 0), 1) * 360.0 }
                    ),
                    gradient: hueGradient(sat: saturation, bri: brightness),
                    accessibilityValueText: { "\(Int(round($0 * 360))) degrees" }
                )
            }

            HSBSliderRow(label: "S") {
                GradientSlider(
                    value: $saturation,
                    gradient: saturationGradient(hue: hueDegrees / 360.0, bri: brightness),
                    accessibilityValueText: { "\(Int(round($0 * 100))) percent" }
                )
            }

            HSBSliderRow(label: "B") {
                GradientSlider(
                    value: $brightness,
                    gradient: brightnessGradient(hue: hueDegrees / 360.0, sat: saturation),
                    accessibilityValueText: { "\(Int(round($0 * 100))) percent" }
                )
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Reactive gradients

    private func hueGradient(sat: Double, bri: Double) -> LinearGradient {
        // More stops = smoother banding on wide tracks.
        let stops: [Gradient.Stop] = stride(from: 0.0, through: 1.0, by: 1.0/24.0).map { t in
            .init(color: Color(hue: t, saturation: sat, brightness: bri), location: t)
        }
        return LinearGradient(gradient: Gradient(stops: stops), startPoint: .leading, endPoint: .trailing)
    }

    private func saturationGradient(hue: Double, bri: Double) -> LinearGradient {
        let left = Color(hue: hue, saturation: 0.0, brightness: bri)
        let right = Color(hue: hue, saturation: 1.0, brightness: bri)
        return LinearGradient(colors: [left, right], startPoint: .leading, endPoint: .trailing)
    }

    private func brightnessGradient(hue: Double, sat: Double) -> LinearGradient {
        let left = Color.black
        let right = Color(hue: hue, saturation: sat, brightness: 1.0)
        return LinearGradient(colors: [left, right], startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - HSB Offset Picker

/// A picker for adjusting HSB offset values (can be negative or positive).
struct HSBOffsetPicker: View {
    @Binding var hueOffset: Double        // -180...180 degrees
    @Binding var saturationOffset: Double // -1...1
    @Binding var brightnessOffset: Double // -1...1

    /// The base HSB values to show the resulting color preview
    let baseHue: Double        // 0...360
    let baseSaturation: Double // 0...1
    let baseBrightness: Double // 0...1

    var body: some View {
        VStack(spacing: 12) {
            HSBSliderRow(label: "H") {
                GradientSlider(
                    value: Binding(
                        get: { (hueOffset + 180) / 360.0 },
                        set: { hueOffset = $0 * 360.0 - 180 }
                    ),
                    gradient: hueOffsetGradient(),
                    accessibilityValueText: { "\(Int(round($0 * 360 - 180))) degrees offset" }
                )
            }

            HSBSliderRow(label: "S") {
                GradientSlider(
                    value: Binding(
                        get: { (saturationOffset + 1) / 2.0 },
                        set: { saturationOffset = $0 * 2.0 - 1 }
                    ),
                    gradient: saturationOffsetGradient(),
                    accessibilityValueText: { "\(Int(round(($0 * 2.0 - 1) * 100))) percent offset" }
                )
            }

            HSBSliderRow(label: "B") {
                GradientSlider(
                    value: Binding(
                        get: { (brightnessOffset + 1) / 2.0 },
                        set: { brightnessOffset = $0 * 2.0 - 1 }
                    ),
                    gradient: brightnessOffsetGradient(),
                    accessibilityValueText: { "\(Int(round(($0 * 2.0 - 1) * 100))) percent offset" }
                )
            }
        }
        .padding(.vertical, 8)
    }

    private func hueOffsetGradient() -> LinearGradient {
        // Show full hue spectrum for offset selection
        let stops: [Gradient.Stop] = stride(from: 0.0, through: 1.0, by: 1.0/24.0).map { t in
            .init(color: Color(hue: t, saturation: 0.8, brightness: 0.9), location: t)
        }
        return LinearGradient(gradient: Gradient(stops: stops), startPoint: .leading, endPoint: .trailing)
    }

    private func saturationOffsetGradient() -> LinearGradient {
        // Show desaturated to saturated based on current hue
        let resultHue = (baseHue + hueOffset).truncatingRemainder(dividingBy: 360) / 360.0
        let left = Color(hue: resultHue, saturation: 0.0, brightness: 0.7)
        let right = Color(hue: resultHue, saturation: 1.0, brightness: 0.9)
        return LinearGradient(colors: [left, right], startPoint: .leading, endPoint: .trailing)
    }

    private func brightnessOffsetGradient() -> LinearGradient {
        let resultHue = (baseHue + hueOffset).truncatingRemainder(dividingBy: 360) / 360.0
        let resultSat = max(0, min(1, baseSaturation + saturationOffset))
        let left = Color.black
        let right = Color(hue: resultHue, saturation: resultSat, brightness: 1.0)
        return LinearGradient(colors: [left, right], startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Row layout

private struct HSBSliderRow<SliderContent: View>: View {
    let label: String
    @ViewBuilder var slider: () -> SliderContent

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)

            slider()
                .frame(height: 28)
        }
    }
}

// MARK: - GradientSlider (track + thumb)

struct GradientSlider: View {
    @Binding var value: Double      // 0...1
    var gradient: LinearGradient
    var accessibilityValueText: (Double) -> String = { "\(Int(round($0 * 100))) percent" }

    // Tuned to feel like system control sizing
    private let trackHeight: CGFloat = 8
    private let thumbDiameter: CGFloat = 18
    private let horizontalHitSlop: CGFloat = 12
    private let verticalHitHeight: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let x = CGFloat(value.clamped01()) * w

            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
                    .fill(gradient)
                    .frame(height: trackHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
                            .strokeBorder(.primary.opacity(0.14), lineWidth: 1)
                    )

                // Thumb (system-ish: background fill + subtle border)
                Circle()
                    .fill(.background)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .overlay(Circle().strokeBorder(.primary.opacity(0.22), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.20), radius: 2, x: 0, y: 1)
                    .offset(x: x - thumbDiameter / 2)
            }
            .frame(height: max(verticalHitHeight, thumbDiameter))
            .contentShape(Rectangle().inset(by: -horizontalHitSlop))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let t = (g.location.x / w).clamped01()
                        value = Double(t)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(Text("Slider"))
            .accessibilityValue(Text(accessibilityValueText(value)))
            .accessibilityAdjustableAction { direction in
                let step = 0.01
                switch direction {
                case .increment: value = min(value + step, 1)
                case .decrement: value = max(value - step, 0)
                default: break
                }
            }
        }
    }
}

// MARK: - Helpers

private extension FloatingPoint {
    func clamped(to r: ClosedRange<Self>) -> Self {
        min(max(self, r.lowerBound), r.upperBound)
    }

    func clamped01() -> Self { clamped(to: 0...1) }
}
