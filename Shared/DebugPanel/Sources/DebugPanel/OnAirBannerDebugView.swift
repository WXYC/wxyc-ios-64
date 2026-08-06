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
import WXUI

#if DEBUG
/// A sheet of live design controls for the on-air banner — indicator color/glow, DJ-handle
/// SF Pro axes, and spacing — each set grouped under a collapsible disclosure group.
///
/// Presented by tapping the banner itself rather than living in the general debug sheet.
public struct OnAirBannerDebugView: View {
    @Bindable private var state = OnAirDebugState.shared

    // Disclosure-group open/closed state persists across presentations so the
    // panel reopens the way it was left, rather than resetting every time.
    @AppStorage("OnAirDebug.disclosure.indicator") private var indicatorExpanded = true
    @AppStorage("OnAirDebug.disclosure.handle") private var handleExpanded = true
    @AppStorage("OnAirDebug.disclosure.adaptive") private var adaptiveExpanded = true
    @AppStorage("OnAirDebug.disclosure.wave") private var waveExpanded = true
    @AppStorage("OnAirDebug.disclosure.requestLine") private var requestLineExpanded = true
    @AppStorage("OnAirDebug.disclosure.spacing") private var spacingExpanded = true

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Force Sample DJ", isOn: $state.forceOnAir)
                    TextField("DJ handle", text: $state.forcedDJName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Substitutes a sample named DJ so the named-handle layout can be previewed when nobody is signed on (otherwise the banner reads \"Auto DJ\"). Edit the handle to try the adaptive width fit against short and long names.")
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

                DisclosureGroup("Adaptive Width", isExpanded: $adaptiveExpanded) {
                    Toggle("Condense to fit", isOn: $state.adaptiveWidth)
                    labeledSlider("Width Floor", value: $state.handleWidthFloor, in: SFProFontAxis.width.range, format: "%.0f")
                    Text("When on, the handle narrows its width axis (down to the floor) so a long name stays on one line beside the say-hi chip, without shrinking the point size. \"Width\" above is the base (expanded) width used when the name already fits.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("Handle Wave", isExpanded: $waveExpanded) {
                    Toggle("Enable wave", isOn: $state.waveEnabled)
                    Button("Play wave") { state.waveReplayToken += 1 }
                        .disabled(!state.waveEnabled)
                    labeledSlider("Duration (s)", value: $state.waveDuration, in: 0.2...3.0)
                    labeledSlider("Depth", value: $state.waveDepth, in: 0...536, format: "%.0f")
                    labeledSlider("Thinning", value: $state.waveWeightDepth, in: 0...647, format: "%.0f")
                    labeledSlider("Crest Width", value: $state.waveCrestHalfWidth, in: 0.1...1.0)
                    labeledSlider("Repetitions", value: $state.waveRepetitions, in: 1...5, format: "%.0f", step: 1)
                    labeledSlider("Spacing", value: $state.waveSpacing, in: 0.1...1.0)
                    Text("Sweeps a lightening crest across the DJ handle. Depth dips the grade axis (metric-neutral, subtle) and thinning dips the weight axis for a much thinner, near-hairline crest — the fixed per-letter cells absorb the width change so the handle's total width never moves. Crest width is how many letters light at once; repetitions is how many crests sweep across. Spacing sets how far apart they launch — 1 plays them one at a time, lower values overlap several at once so the animation reads snappier. Plays on appear and whenever the handle changes; \"Play wave\" replays it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("Request Line Chip", isExpanded: $requestLineExpanded) {
                    labeledSlider("Tint Opacity", value: $state.requestLineTintOpacity, in: 0...1)
                    Text("Background transparency of the green \"SAY HI\" chip — 1 is solid, 0 is clear glass. The text and icon stay opaque.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("Spacing", isExpanded: $spacingExpanded) {
                    labeledSlider("Below ON AIR", value: $state.onAirSpacing, in: 0...40, format: "%.1f")
                    labeledSlider("Handle Line Spacing", value: $state.handleLineSpacing, in: 0...30, format: "%.1f")
                }
            }
            .sheetChrome(title: "On Air Banner")
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

    /// A labeled slider with a trailing value readout. Pass `step` to snap the
    /// slider to discrete increments (e.g. `1` for an integer count).
    @ViewBuilder
    private func labeledSlider(
        _ title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        format: String = "%.2f",
        step: Double? = nil
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(String(format: format, value.wrappedValue))
                .foregroundStyle(.secondary)
        }
        if let step {
            Slider(value: value, in: range, step: step)
        } else {
            Slider(value: value, in: range)
        }
    }
}
#endif
