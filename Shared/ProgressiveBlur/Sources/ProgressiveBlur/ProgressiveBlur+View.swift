import SwiftUI

public enum BlurDirection: Int, Sendable {
    case topToBottom = 0
    case bottomToTop = 1
    case leftToRight = 2
    case rightToLeft = 3
}

public struct ProgressiveBlurModifier: ViewModifier {
    let radius: CGFloat
    let offset: CGFloat
    let interpolation: CGFloat
    let direction: BlurDirection
    let noise: CGFloat
    let useDrawingGroup: Bool
    
    public func body(content: Content) -> some View {
        let contentWithDrawingGroup = Group {
            if useDrawingGroup {
                content.drawingGroup()
            } else {
                content
            }
        }
        
        contentWithDrawingGroup.visualEffect { [radius, offset, interpolation, direction, noise] content, geometry in
            let size = geometry.size
            let radiusFloat = Float(radius)
            let offsetFloat = Float(offset)
            let interpFloat = Float(interpolation)
            let dirFloat = Float(direction.rawValue)
            let noiseFloat = Float(noise)
            
            // Pass 1: Horizontal Blur
            // Stride: (1, 0)
            // Noise: 0
            return content.layerEffect(
                ShaderLibrary.bundle(.module).progressiveBlur(
                    .float2(size),
                    .float(radiusFloat),
                    .float(offsetFloat),
                    .float(interpFloat),
                    .float(dirFloat),
                    .float(0.0), // No noise in first pass
                    .float2(CGVector(dx: 1, dy: 0))
                ),
                maxSampleOffset: CGSize(width: radius, height: radius),
                isEnabled: radius > 0
            )
            // Pass 2: Vertical Blur + Noise
            // Stride: (0, 1)
            // Noise: noiseFloat
            .layerEffect(
                ShaderLibrary.bundle(.module).progressiveBlur(
                    .float2(size),
                    .float(radiusFloat),
                    .float(offsetFloat),
                    .float(interpFloat),
                    .float(dirFloat),
                    .float(noiseFloat),
                    .float2(CGVector(dx: 0, dy: 1))
                ),
                maxSampleOffset: CGSize(width: radius, height: radius),
                isEnabled: radius > 0 || noise > 0
            )
        }
    }
}

public extension View {
    func progressiveBlur(
        radius: CGFloat,
        offset: CGFloat = 0,
        interpolation: CGFloat = 1,
        direction: BlurDirection = .topToBottom,
        noise: CGFloat = 0,
        drawingGroup: Bool = false
    ) -> some View {
        modifier(ProgressiveBlurModifier(
            radius: radius,
            offset: offset,
            interpolation: interpolation,
            direction: direction,
            noise: noise,
            useDrawingGroup: drawingGroup
        ))
    }
}
