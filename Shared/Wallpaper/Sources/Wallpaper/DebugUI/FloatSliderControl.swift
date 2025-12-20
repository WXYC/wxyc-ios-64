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
            if let range = parameter.range {
                Slider(value: binding, in: range.min...range.max)
            } else {
                Slider(value: binding, in: 0...1)
            }
        }
    }
}
