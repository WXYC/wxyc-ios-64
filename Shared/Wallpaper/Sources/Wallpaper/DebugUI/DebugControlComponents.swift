//
//  DebugControlComponents.swift
//  Wallpaper
//
//  Reusable components for debug controls to reduce repetition.
//
//  Created by Jake Bromberg on 01/14/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

#if DEBUG

// MARK: - Labeled Slider

/// A slider with a label showing the current value.
struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: SliderValueFormat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(formatValue())
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            
            Slider(value: $value, in: range)
        }
    }
    
    private func formatValue() -> String {
        switch format {
        case .decimal(let precision):
            return value.formatted(.number.precision(.fractionLength(precision)))
        case .percentage:
            return "\(Int(value * 100))%"
        case .integer:
            return "\(Int(value))"
        case .custom(let formatter):
            return formatter(value)
        }
    }
}

/// Format options for slider value display.
enum SliderValueFormat {
    case decimal(precision: Int)
    case percentage
    case integer
    case custom((Double) -> String)
}

// MARK: - Labeled Slider with Override

/// A slider that displays an override indicator when the value differs from default.
struct OverridableSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: SliderValueFormat
    let isOverridden: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                if isOverridden {
                    Text("(override)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(formatValue())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Slider(value: $value, in: range)
        }
    }
    
    private func formatValue() -> String {
        switch format {
        case .decimal(let precision):
            return value.formatted(.number.precision(.fractionLength(precision)))
        case .percentage:
            return "\(Int(value * 100))%"
        case .integer:
            return "\(Int(value))"
        case .custom(let formatter):
            return formatter(value)
        }
    }
}

// MARK: - Conditional Reset Button

/// A reset button that only appears when there are overrides to reset.
struct ConditionalResetButton: View {
    let hasOverrides: Bool
    let label: String
    let action: () -> Void
    var style: ResetButtonStyle = .normal
    
    var body: some View {
        if hasOverrides {
            Button(label, action: action)
                .font(.caption)
                .foregroundStyle(style == .destructive ? .red : .primary)
        }
    }
}

enum ResetButtonStyle {
    case normal
    case destructive
}

// MARK: - Labeled Picker

/// A picker with a label above it.
struct LabeledPicker<SelectionValue: Hashable, Content: View>: View {
    let label: String
    @Binding var selection: SelectionValue
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(label, selection: $selection, content: content)
                .pickerStyle(.menu)
        }
    }
}

// MARK: - Fallback Binding Helper

/// Creates a binding that reads from an override value or falls back to a default.
///
/// Note: This function generates Sendable warnings in DEBUG builds, which is acceptable
/// since these debug controls are main-actor isolated and run on the main thread.
nonisolated func overrideBinding<T>(
    get override: @escaping @autoclosure () -> T?,
    fallback: @escaping @autoclosure () -> T,
    set: @escaping (T) -> Void
) -> Binding<T> {
    Binding(
        get: { override() ?? fallback() },
        set: set
    )
}

#endif
