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
//  Two knobs exist purely so consolidating onto one control doesn't change how
//  any of the three call sites lays out or reads:
//
//  `layout` picks how `body` presents its pieces. `.flattened` (the default) is
//  a `Group`, so each piece becomes its own container child — inside a
//  `Form`/`List` its own row, matching `OnAirBannerDebugView`'s pre-#771
//  `labeledSlider` free function; inside a plain `VStack`
//  (`VisualizerDebugView`'s `DebugSection`) its own `VStack` child at the
//  section's spacing, again matching pre-#771 output. `.grouped` packs the
//  readout and slider into one tight `VStack(spacing: 2)` — one `Form` row per
//  parameter, which is what `LikeEffectTuningView`'s pre-#771 `tuner` produced
//  and what its `.medium`-detent sheet has room for.
//
//  `controlsDisabled` greys the slider and reset button while leaving the title
//  and value readout legible. A `.disabled(_:)` on the whole control would
//  propagate through the flattened `Group` to the label too — which is not what
//  `VisualizerDebugView` did before #771, and its Amplification section rests
//  in the disabled state, so the section would normally read greyed out.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

#if DEBUG
/// A labeled slider with a trailing value readout, for DEBUG tuning panels.
public struct LabeledSlider: View {
    /// How `body` presents the readout row, slider, and optional reset button.
    public enum Layout {
        /// Each piece is its own container child — a separate `Form`/`List`
        /// row, or a separate `VStack` child at the enclosing stack's spacing.
        case flattened
        /// The readout and slider share one tight container child, so a `Form`
        /// renders one row per parameter instead of two.
        case grouped
    }

    private let title: String
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double?
    private let format: (Double) -> String
    private let monospacedDigitReadout: Bool
    private let onEditingChanged: (Bool) -> Void
    private let resetLabel: String
    private let onReset: (() -> Void)?
    private let layout: Layout
    private let controlsDisabled: Bool

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
    ///   - layout: Whether the pieces flatten into the enclosing container
    ///     (the default) or pack the readout and slider into one row.
    ///   - controlsDisabled: Disables the slider and reset button while leaving
    ///     the title and readout legible. Prefer this to a `.disabled(_:)` on
    ///     the whole control, which a `.flattened` layout propagates to the
    ///     label as well.
    public init(
        _ title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double? = nil,
        format: @escaping (Double) -> String = { String(format: "%.2f", $0) },
        monospacedDigitReadout: Bool = false,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
        resetLabel: String = "Reset",
        onReset: (() -> Void)? = nil,
        layout: Layout = .flattened,
        controlsDisabled: Bool = false
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
        self.layout = layout
        self.controlsDisabled = controlsDisabled
    }

    @ViewBuilder
    public var body: some View {
        switch layout {
        case .flattened:
            Group {
                readoutRow
                slider
                resetButton
            }
        case .grouped:
            VStack(alignment: .leading, spacing: 2) {
                readoutRow
                slider
            }
            resetButton
        }
    }

    private var readoutRow: some View {
        HStack {
            Text(title)
            Spacer()
            readout
        }
    }

    @ViewBuilder
    private var slider: some View {
        Group {
            if let step {
                Slider(value: $value, in: range, step: step, onEditingChanged: onEditingChanged)
            } else {
                Slider(value: $value, in: range, onEditingChanged: onEditingChanged)
            }
        }
        .disabled(controlsDisabled)
    }

    @ViewBuilder
    private var resetButton: some View {
        if let onReset {
            Button(resetLabel, action: onReset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(controlsDisabled)
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
