//
//  WallpaperDebugControlsGenerator.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
//

import SwiftUI

/// Generates debug controls for a wallpaper based on its parameter definitions.
public struct WallpaperDebugControlsGenerator: View {
    let wallpaper: LoadedWallpaper

    public init(wallpaper: LoadedWallpaper) {
        self.wallpaper = wallpaper
    }

    public var body: some View {
        let parameters = wallpaper.manifest.parameters

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
            FloatSliderControl(parameter: parameter, store: wallpaper.parameterStore)

        case .color:
            ColorControl(parameter: parameter, store: wallpaper.parameterStore)

        case .bool:
            boolToggle(for: parameter)

        case .float2, .float3:
            // Not yet implemented - fall back to individual float controls
            EmptyView()
        }
    }

    private func boolToggle(for parameter: ParameterDefinition) -> some View {
        let binding = Binding<Bool>(
            get: { wallpaper.parameterStore.boolValue(for: parameter.id) },
            set: { wallpaper.parameterStore.setBool($0, for: parameter.id) }
        )

        return Toggle(parameter.label, isOn: binding)
    }
}
