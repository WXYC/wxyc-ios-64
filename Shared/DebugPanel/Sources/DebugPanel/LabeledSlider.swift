//
//  LabeledSlider.swift
//  DebugPanel
//
//  A title + formatted-value readout + slider, with optional step snapping, an
//  optional `onEditingChanged` callback (e.g. to replay a haptic once a drag
//  settles), and an optional trailing reset button. The one control shared by
//  `OnAirBannerDebugView`'s `labeledSlider` helper, `LikeEffectTuningView`'s
//  `tuner` helper, and the two hand-rolled slider+reset stanzas in
//  `VisualizerDebugView` ("Signal Boost", "Stream Gain") — three ad hoc
//  versions of the identical control (issue #771).
//
//  `body` is a `Group` of its three pieces (readout row, slider, optional reset
//  button) rather than a `VStack`, so it flattens transparently in both call
//  contexts: inside a `Form`/`List` each piece becomes its own row, matching
//  `OnAirBannerDebugView`'s pre-#771 `labeledSlider` free function exactly; and
//  inside a plain `VStack` (`VisualizerDebugView`'s `DebugSection`) the three
//  pieces become separate `VStack` children at the section's own spacing,
//  again matching pre-#771 output exactly. The one place this is NOT a pixel
//  match: `LikeEffectTuningView`'s pre-#771 `tuner` grouped its readout+slider
//  into a single tight `Form` row (`VStack(spacing: 2)`); consolidated onto
//  this control, each parameter now renders as two `Form` rows instead of one
//  — a deliberate, minor layout normalization judged acceptable for a
//  DEBUG-only tuning bench, not a pixel-for-pixel port.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

#if DEBUG
/// A labeled slider with a trailing value readout, for DEBUG tuning panels.
public struct LabeledSlider: View {
    private let title: String
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double?
    private let format: (Double) -> String
    private let monospacedDigitReadout: Bool
    private let onEditingChanged: (Bool) -> Void
    private let resetLabel: String
    private let onReset: (() -> Void)?

    /// - Parameters:
    ///   - title: The control's label, shown leading.
    ///   - value: The bound slider value.
    ///   - range: The slider's range.
    ///   - step: Snaps the slider to discrete increments (e.g. `1` for an
    ///     integer count). `nil` (the default) is a continuous slider.
    ///   - format: Renders `value` for the trailing readout. Defaults to two
    ///     decimal places.
    ///   - monospacedDigitReadout: Fixes the readout's digit widths so it
    ///     doesn't jiggle horizontally while dragging.
    ///   - onEditingChanged: Called on drag start/end, e.g. to replay a haptic
    ///     once the thumb settles rather than on every intermediate value.
    ///   - resetLabel: The reset button's title, when `onReset` is supplied.
    ///   - onReset: When non-`nil`, shows a trailing reset button beneath the
    ///     slider that calls this closure.
    public init(
        _ title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double? = nil,
        format: @escaping (Double) -> String = { String(format: "%.2f", $0) },
        monospacedDigitReadout: Bool = false,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
        resetLabel: String = "Reset",
        onReset: (() -> Void)? = nil
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.format = format
        self.monospacedDigitReadout = monospacedDigitReadout
        self.onEditingChanged = onEditingChanged
        self.resetLabel = resetLabel
        self.onReset = onReset
    }

    public var body: some View {
        Group {
            HStack {
                Text(title)
                Spacer()
                readout
            }
            if let step {
                Slider(value: $value, in: range, step: step, onEditingChanged: onEditingChanged)
            } else {
                Slider(value: $value, in: range, onEditingChanged: onEditingChanged)
            }
            if let onReset {
                Button(resetLabel, action: onReset)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var readout: some View {
        if monospacedDigitReadout {
            Text(format(value)).foregroundStyle(.secondary).monospacedDigit()
        } else {
            Text(format(value)).foregroundStyle(.secondary)
        }
    }
}
#endif
