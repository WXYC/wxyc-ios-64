//
//  StitchableWallpaperView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
//

import SwiftUI

/// Generic view for wallpapers that use SwiftUI's colorEffect with stitchable shaders.
public struct StitchableWallpaperView: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.wallpaperAnimationStartTime) private var startTime

    let wallpaper: LoadedWallpaper

    public init(wallpaper: LoadedWallpaper) {
        self.wallpaper = wallpaper
    }

    public var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geometry in
                let time = Float(context.date.timeIntervalSince(startTime))
                let width = Float(geometry.size.width)
                let height = Float(geometry.size.height)
                let scale = Float(displayScale)

                let arguments = wallpaper.parameterStore.buildShaderArguments(
                    time: time,
                    viewSize: (width, height),
                    displayScale: scale
                )

                Rectangle()
                    .fill(.black)
                    .colorEffect(buildShader(arguments: arguments))
                    .ignoresSafeArea()
            }
        }
    }

    private func buildShader(arguments: [ShaderArgumentValue]) -> Shader {
        guard let functionName = wallpaper.manifest.renderer.functionName else {
            // Fallback to a simple black color if no function specified
            return Shader(function: ShaderFunction(library: .default, name: ""), arguments: [])
        }

        let shaderArgs: [Shader.Argument] = arguments.map { value in
            switch value {
            case .float(let v):
                return .float(v)
            case .float2(let x, let y):
                return .float2(x, y)
            case .float3(let x, let y, let z):
                return .float3(x, y, z)
            }
        }

        let function = ShaderFunction(
            library: ShaderLibrary.bundle(.module),
            name: functionName
        )

        return Shader(function: function, arguments: shaderArgs)
    }
}
