//
//  OnAirBannerDebugView.swift
//  DebugPanel
//
//  Live design controls for the playlist "on air" banner, presented by tapping the banner.
//
//  Created by Jake Bromberg on 07/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playlist
import SwiftUI

#if DEBUG
/// A sheet of live design controls for the on-air banner — indicator color/glow, DJ-handle
/// SF Pro axes, and spacing — each set grouped under a collapsible disclosure group.
///
/// Presented by tapping the banner itself rather than living in the general debug sheet.
public struct OnAirBannerDebugView: View {
    @Bindable private var state = OnAirDebugState.shared
    @Environment(\.dismiss) private var dismiss

    @State private var indicatorExpanded = true
    @State private var handleExpanded = true
    @State private var spacingExpanded = true

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Force Sample DJ", isOn: $state.forceOnAir)
                } footer: {
                    Text("Substitutes a sample named DJ so the named-handle layout can be previewed when nobody is signed on (otherwise the banner reads \"Auto DJ\").")
                }

                DisclosureGroup("Indicator", isExpanded: $indicatorExpanded) {
                    HStack {
                        Text("Hue")
                        Spacer()
                        Text(String(format: "%.2f", state.indicatorHue))
                            .foregroundStyle(.secondary)
                        Circle()
                            .fill(indicatorPreviewColor)
                            .frame(width: 18, height: 18)
                    }
                    Slider(value: $state.indicatorHue, in: 0...1)
                    labeledSlider("Saturation", value: $state.indicatorSaturation, in: 0...1)
                    labeledSlider("Lightness", value: $state.indicatorLightness, in: 0...1)
                    labeledSlider("Blur Radius", value: $state.indicatorBlurRadius, in: 0...30, format: "%.1f")
                }

                DisclosureGroup("DJ Handle", isExpanded: $handleExpanded) {
                    labeledSlider(SFProFontAxis.weight.displayName, value: $state.handleWeight, in: SFProFontAxis.weight.range, format: "%.0f")
                    labeledSlider(SFProFontAxis.width.displayName, value: $state.handleWidth, in: SFProFontAxis.width.range, format: "%.0f")
                    labeledSlider(SFProFontAxis.opticalSize.displayName, value: $state.handleOpticalSize, in: SFProFontAxis.opticalSize.range, format: "%.0f")
                    labeledSlider(SFProFontAxis.grade.displayName, value: $state.handleGrade, in: SFProFontAxis.grade.range, format: "%.0f")
                }

                DisclosureGroup("Spacing", isExpanded: $spacingExpanded) {
                    labeledSlider("Below ON AIR", value: $state.onAirSpacing, in: 0...40, format: "%.1f")
                    labeledSlider("Handle Line Spacing", value: $state.handleLineSpacing, in: 0...30, format: "%.1f")
                }
            }
            .navigationTitle("On Air Banner")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Live swatch of the current HSL indicator color.
    private var indicatorPreviewColor: Color {
        let rgb = HSL(
            hue: state.indicatorHue,
            saturation: state.indicatorSaturation,
            lightness: state.indicatorLightness
        ).rgb
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// A labeled slider with a trailing value readout.
    @ViewBuilder
    private func labeledSlider(
        _ title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        format: String = "%.2f"
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(String(format: format, value.wrappedValue))
                .foregroundStyle(.secondary)
        }
        Slider(value: value, in: range)
    }
}
#endif
