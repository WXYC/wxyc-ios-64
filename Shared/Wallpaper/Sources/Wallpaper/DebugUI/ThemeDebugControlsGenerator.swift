//
//  ThemeDebugControlsGenerator.swift
//  Wallpaper
//
//  Generates debug controls from shader directives.
//
//  Created by Jake Bromberg on 12/19/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

/// Generates debug controls for a theme based on its parameter definitions.
public struct ThemeDebugControlsGenerator: View {
    let theme: LoadedTheme

    public init(theme: LoadedTheme) {
        self.theme = theme
    }

    public var body: some View {
        let parameters = theme.manifest.parameters

        if parameters.isEmpty {
            EmptyView()
        } else {
            parameterControls(parameters)
        }
    }

    @ViewBuilder
    private func parameterControls(_ parameters: [ParameterDefinition]) -> some View {
        // Group parameters by their group property
        let grouped = Dictionary(grouping: parameters) { $0.group ?? "" }
        let sortedGroups = grouped.keys.sorted()

        ForEach(sortedGroups, id: \.self) { group in
            if let params = grouped[group] {
                if !group.isEmpty {
                    Text(group)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(params) { param in
                    controlView(for: param)
                }
            }
        }
    }

    @ViewBuilder
    private func controlView(for parameter: ParameterDefinition) -> some View {
        switch parameter.type {
        case .float:
            FloatSliderControl(parameter: parameter, store: theme.parameterStore)

        case .color:
            ColorControl(parameter: parameter, store: theme.parameterStore)

        case .bool:
            boolToggle(for: parameter)

        case .float2, .float3:
            // Not yet implemented - fall back to individual float controls
            EmptyView()
        }
    }

    private func boolToggle(for parameter: ParameterDefinition) -> some View {
        let binding = Binding<Bool>(
            get: { theme.parameterStore.boolValue(for: parameter.id) },
            set: { theme.parameterStore.setBool($0, for: parameter.id) }
        )

        return Toggle(parameter.label, isOn: binding)
    }
}
