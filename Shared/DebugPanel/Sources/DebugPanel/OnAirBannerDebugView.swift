//
//  OnAirBannerDebugView.swift
//  DebugPanel
//
//  Live design controls for the playlist "on air" banner, presented by tapping the banner.
//
//  Created by Jake Bromberg on 07/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import ColorPalette
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
                    LabeledSlider("Saturation", value: $state.indicatorSaturation, in: 0...1)
                    LabeledSlider("Lightness", value: $state.indicatorLightness, in: 0...1)
                    LabeledSlider("Blur Radius", value: $state.indicatorBlurRadius, in: 0...30, format: oneDecimal)
                }

                DisclosureGroup("DJ Handle", isExpanded: $handleExpanded) {
                    LabeledSlider(SFProFontAxis.weight.displayName, value: $state.handleWeight, in: SFProFontAxis.weight.range, format: noDecimals)
                    LabeledSlider(SFProFontAxis.width.displayName, value: $state.handleWidth, in: SFProFontAxis.width.range, format: noDecimals)
                    LabeledSlider(SFProFontAxis.opticalSize.displayName, value: $state.handleOpticalSize, in: SFProFontAxis.opticalSize.range, format: noDecimals)
                    LabeledSlider(SFProFontAxis.grade.displayName, value: $state.handleGrade, in: SFProFontAxis.grade.range, format: noDecimals)
                }

                DisclosureGroup("Adaptive Width", isExpanded: $adaptiveExpanded) {
                    Toggle("Condense to fit", isOn: $state.adaptiveWidth)
                    LabeledSlider("Width Floor", value: $state.handleWidthFloor, in: SFProFontAxis.width.range, format: noDecimals)
                    Text("When on, the handle narrows its width axis (down to the floor) so a long name stays on one line beside the say-hi chip, without shrinking the point size. \"Width\" above is the base (expanded) width used when the name already fits.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("Handle Wave", isExpanded: $waveExpanded) {
                    Toggle("Enable wave", isOn: $state.waveEnabled)
                    Button("Play wave") { state.waveReplayToken += 1 }
                        .disabled(!state.waveEnabled)
                    LabeledSlider("Duration (s)", value: $state.waveDuration, in: 0.2...3.0)
                    LabeledSlider("Depth", value: $state.waveDepth, in: 0...536, format: noDecimals)
                    LabeledSlider("Thinning", value: $state.waveWeightDepth, in: 0...647, format: noDecimals)
                    LabeledSlider("Crest Width", value: $state.waveCrestHalfWidth, in: 0.1...1.0)
                    LabeledSlider("Repetitions", value: $state.waveRepetitions, in: 1...5, step: 1, format: noDecimals)
                    LabeledSlider("Spacing", value: $state.waveSpacing, in: 0.1...1.0)
                    Text("Sweeps a lightening crest across the DJ handle. Depth dips the grade axis (metric-neutral, subtle) and thinning dips the weight axis for a much thinner, near-hairline crest — the fixed per-letter cells absorb the width change so the handle's total width never moves. Crest width is how many letters light at once; repetitions is how many crests sweep across. Spacing sets how far apart they launch — 1 plays them one at a time, lower values overlap several at once so the animation reads snappier. Plays on appear and whenever the handle changes; \"Play wave\" replays it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("Request Line Chip", isExpanded: $requestLineExpanded) {
                    LabeledSlider("Tint Opacity", value: $state.requestLineTintOpacity, in: 0...1)
                    Text("Background transparency of the green \"SAY HI\" chip — 1 is solid, 0 is clear glass. The text and icon stay opaque.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("Spacing", isExpanded: $spacingExpanded) {
                    LabeledSlider("Below ON AIR", value: $state.onAirSpacing, in: 0...40, format: oneDecimal)
                    LabeledSlider("Handle Line Spacing", value: $state.handleLineSpacing, in: 0...30, format: oneDecimal)
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

    /// One decimal place (e.g. blur radius, spacing) — `LabeledSlider`'s
    /// default is two, which this panel's non-normalized ranges don't need.
    private let oneDecimal: (Double) -> String = { String(format: "%.1f", $0) }

    /// Whole numbers (e.g. SF Pro axis values, wave depth/repetitions).
    private let noDecimals: (Double) -> String = { String(format: "%.0f", $0) }
}
#endif
