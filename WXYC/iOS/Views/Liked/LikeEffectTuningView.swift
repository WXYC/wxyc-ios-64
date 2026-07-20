//
//  LikeEffectTuningView.swift
//  WXYC
//
//  A DEBUG-only bench for dialing in the like celebration by feel: haptic
//  hardness (kind, intensity, sharpness, tap count, spacing) and the particle
//  burst (count, travel). Every control change replays the current haptic so the
//  feel can be tuned by hand. Opened from the Liked header; writes straight to
//  the shared `LikeHapticSettings` the production spray reads.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if DEBUG
import SwiftUI

struct LikeEffectTuningView: View {
    @Bindable private var settings = LikeHapticSettings.shared
    @Environment(\.dismiss) private var dismiss

    /// Drives the toolbar test heart. Toggling it into liked fires the real
    /// celebration (spray + jump + haptic) with the current settings.
    @State private var testLiked = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Haptic") {
                    Picker("Type", selection: $settings.kind) {
                        Text("Transient").tag(HapticEventSpec.Kind.transient)
                        Text("Continuous").tag(HapticEventSpec.Kind.continuous)
                    }
                    .onChange(of: settings.kind) { play() }

                    tuner("Intensity", value: $settings.intensity, in: 0 ... 1)
                    tuner("Sharpness", value: $settings.sharpness, in: 0 ... 1)
                    tuner("Taps", value: $settings.eventCount, in: 1 ... 8, step: 1, integer: true)
                    tuner("Spacing", value: $settings.spacing, in: 0.01 ... 0.1, unit: "s")
                    if settings.kind == .continuous {
                        tuner("Duration", value: $settings.duration, in: 0.02 ... 0.2, unit: "s")
                    }
                }

                Section("Particles") {
                    tuner("Count", value: $settings.particleCount, in: 1 ... 16, step: 1, integer: true, playsHaptic: false)
                    tuner("Travel", value: $settings.travel, in: 0.3 ... 2.0, unit: "×", playsHaptic: false)
                }
            }
            .navigationTitle("Like FX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    LikeHeartButton(isLiked: testLiked) { testLiked.toggle() }
                        .accessibilityIdentifier("likeFXTestHeart")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .usesCustomHaptics()
        .presentationDetents([.medium, .large])
    }

    /// A labelled slider that replays the current haptic once the drag ends, so
    /// the felt result matches where the thumb lands rather than buzzing through
    /// every intermediate value. The value label still tracks the drag live.
    @ViewBuilder
    private func tuner(
        _ title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double = 0,
        unit: String? = nil,
        integer: Bool = false,
        playsHaptic: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(label(for: value.wrappedValue, unit: unit, integer: integer))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            slider(value: value, in: range, step: step, playsHaptic: playsHaptic)
        }
    }

    @ViewBuilder
    private func slider(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double,
        playsHaptic: Bool
    ) -> some View {
        // The Particles sliders are visual-only, so they pass `playsHaptic: false`
        // and their touch-up is a no-op. Haptic sliders replay on release only.
        let onEditingChanged: (Bool) -> Void = { editing in
            if playsHaptic, !editing { play() }
        }
        if step > 0 {
            Slider(value: value, in: range, step: step, onEditingChanged: onEditingChanged)
        } else {
            Slider(value: value, in: range, onEditingChanged: onEditingChanged)
        }
    }

    private func label(for value: Double, unit: String?, integer: Bool) -> String {
        if integer {
            return "\(Int(value.rounded()))"
        }
        let formatted = String(format: "%.2f", value)
        return unit.map { formatted + $0 } ?? formatted
    }

    private func play() {
        #if os(iOS)
        if let pattern = HapticEventSpec.pattern(from: settings.makeEvents()) {
            Haptics.play(pattern)
        }
        #endif
    }
}

#Preview {
    LikeEffectTuningView()
}
#endif
