import SwiftUI

public struct NoiseEffect: View {
    @State private var startTime = Date()
    public let noiseIntensity: Float
    public let frequency: Float
    
    public init(noiseIntensity: Float = 0.5, frequency: Float = 10.0) {
        self.noiseIntensity = noiseIntensity
        self.frequency = frequency
    }
    
    public var body: some View {
        TimelineView(.animation) { timelineContext -> Canvas<EmptyView> in
            let time = Float(timelineContext.date.timeIntervalSince(startTime))
            
            Canvas { graphicsContext, size in
                graphicsContext.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .shader(ShaderLibrary.bundle(Bundle.noise).noiseFragment(
                        .float(time),
                        .float(noiseIntensity),
                        .float(frequency)
                    ))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - View Modifier

public struct NoiseOverlay: ViewModifier {
    public var intensity: Float
    public var frequency: Float
    
    public init(intensity: Float, frequency: Float) {
        self.intensity = intensity
        self.frequency = frequency
    }
    
    public func body(content: Content) -> some View {
        content.overlay {
            NoiseEffect(noiseIntensity: intensity, frequency: frequency)
        }
    }
}

public extension View {
    func noise(intensity: Float = 0.5, frequency: Float = 10.0) -> some View {
        modifier(NoiseOverlay(intensity: intensity, frequency: frequency))
    }
}
