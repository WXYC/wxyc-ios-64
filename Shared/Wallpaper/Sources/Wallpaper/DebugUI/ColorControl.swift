//
//  ColorControl.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
//

import SwiftUI

/// A control for color parameters with RGB sliders, auto-generated from parameter definitions.
struct ColorControl: View {
    let parameter: ParameterDefinition
    @Bindable var store: ParameterStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(parameter.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let components = parameter.components {
                ForEach(components, id: \.id) { component in
                    componentSlider(component)
                }

                colorSwatch
            }
        }
    }

    private func componentSlider(_ component: ParameterComponentDefinition) -> some View {
        let binding = Binding<Float>(
            get: { store.colorComponent(component.id, for: parameter.id) },
            set: { store.setColorComponent(component.id, value: $0, for: parameter.id) }
        )

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(component.label)
                Spacer()
                Text(String(format: "%.2f", binding.wrappedValue))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            #if os(tvOS)
            HStack {
                Button("-") {
                    binding.wrappedValue = max(0, binding.wrappedValue - 0.05)
                }
                Spacer()
                Button("+") {
                    binding.wrappedValue = min(1, binding.wrappedValue + 0.05)
                }
            }
            #else
            Slider(value: binding, in: 0...1)
            #endif
        }
    }

    private var colorSwatch: some View {
        let r = store.colorComponent("r", for: parameter.id)
        let g = store.colorComponent("g", for: parameter.id)
        let b = store.colorComponent("b", for: parameter.id)

        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(red: Double(r), green: Double(g), blue: Double(b)))
            .frame(width: 44, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.primary.opacity(0.2), lineWidth: 1)
            )
    }
}
