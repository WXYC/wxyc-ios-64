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
    @State private var startTime = Date()

    let wallpaper: LoadedWallpaper
    var audioData: AudioData?

    public init(wallpaper: LoadedWallpaper, audioData: AudioData? = nil) {
        self.wallpaper = wallpaper
        self.audioData = audioData
    }

    public var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geometry in
                let time = Float(context.date.timeIntervalSince(startTime))
                let width = Float(geometry.size.width)
                let height = Float(geometry.size.height)
                let scale = Float(displayScale)

                let audio = ParameterStore.AudioValues(
                    level: audioData?.level ?? 0,
                    bass: audioData?.bass ?? 0,
                    mid: audioData?.mid ?? 0,
                    high: audioData?.high ?? 0,
                    beat: audioData?.beat ?? 0
                )

                let arguments = wallpaper.parameterStore.buildShaderArguments(
                    time: time,
                    viewSize: (width, height),
                    displayScale: scale,
                    audio: audio
                )

                Rectangle()
                    .fill(.black)
                    .colorEffect(buildShader(arguments: arguments))
                    .ignoresSafeArea()
            }
        }
        .onAppear { startTime = Date() }
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
