//
//  CompositeWallpaperView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
//

import SwiftUI
import WXUI

/// View for composite wallpapers that layer multiple elements (e.g., gradient + shader overlay).
public struct CompositeWallpaperView: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.wallpaperAnimationStartTime) private var startTime

    let theme: LoadedTheme

    public init(theme: LoadedTheme) {
        self.theme = theme
    }

    public var body: some View {
        ZStack {
            ForEach(theme.manifest.renderer.layers ?? [], id: \.type) { layer in
                layerView(for: layer)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func layerView(for layer: LayerConfiguration) -> some View {
        switch layer.type {
        case .wxycGradient:
            Rectangle().fill(WXYCGradient())

        case .shader:
            if let shaderRef = layer.ref {
                shaderOverlay(functionName: shaderRef)
            }
        }
    }

    @ViewBuilder
    private func shaderOverlay(functionName: String) -> some View {
        TimelineView(.animation) { context in
            GeometryReader { geometry in
                let time = Float(context.date.timeIntervalSince(startTime))
                let arguments = theme.parameterStore.buildShaderArguments(
                    time: time,
                    viewSize: (Float(geometry.size.width), Float(geometry.size.height)),
                    displayScale: Float(displayScale)
                )

                Canvas { graphicsContext, size in
                    graphicsContext.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .shader(buildShader(functionName: functionName, arguments: arguments))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func buildShader(functionName: String, arguments: [ShaderArgumentValue]) -> Shader {
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
