//
//  FloatSliderControl.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
//

import SwiftUI

/// A slider control for float parameters, auto-generated from parameter definitions.
struct FloatSliderControl: View {
    let parameter: ParameterDefinition
    @Bindable var store: ParameterStore

    private var range: ClosedRange<Float> {
        if let r = parameter.range {
            r.min...r.max
        } else {
            0...1
        }
    }

    private var step: Float {
        (range.upperBound - range.lowerBound) / 20
    }

    var body: some View {
        let binding = Binding<Float>(
            get: { store.floatValue(for: parameter.id) },
            set: { store.setFloat($0, for: parameter.id) }
        )

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(parameter.label)
                Spacer()
                Text(String(format: "%.2f", binding.wrappedValue))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            #if os(tvOS)
            HStack {
                Button("-") {
                    binding.wrappedValue = max(range.lowerBound, binding.wrappedValue - step)
                }
                Spacer()
                Button("+") {
                    binding.wrappedValue = min(range.upperBound, binding.wrappedValue + step)
                }
            }
            #else
            Slider(value: binding, in: range)
            #endif
        }
    }
}
