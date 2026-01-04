import Foundation

/// Computes optimal FPS and scale adjustments based on thermal momentum.
///
/// Uses a reactive control loop that:
/// - Immediately reduces quality when heating (scale first, then FPS)
/// - Slowly restores quality when cooling (half speed, scale first)
/// - Applies damping near equilibrium to prevent oscillation
public struct ThermalOptimizer: Sendable {

    /// Maximum FPS adjustment per optimization tick.
    public static let maxFPSStep: Float = 5.0

    /// Maximum scale adjustment per optimization tick.
    public static let maxScaleStep: Float = 0.05

    /// How much slower to restore quality compared to reducing it.
    public static let recoverySpeedFactor: Float = 0.5

    /// Weight given to scale adjustments (vs FPS). Scale changes are less perceptible.
    public static let scaleWeight: Float = 0.7

    /// Weight given to FPS adjustments.
    public static let fpsWeight: Float = 0.3

    public init() {}

    /// Computes the next FPS and scale values based on thermal momentum.
    ///
    /// - Parameters:
    ///   - current: The current thermal profile.
    ///   - momentum: Current thermal momentum from ThermalSignal.
    /// - Returns: Tuple of (fps, scale) with optimized values.
    public func optimize(current: ThermalProfile, momentum: Float) -> (fps: Float, scale: Float) {
        // In dead zone - no adjustment needed
        guard abs(momentum) > ThermalSignal.deadZone else {
            return (current.fps, current.scale)
        }

        var fps = current.fps
        var scale = current.scale

        if momentum > 0 {
            // Heating - reduce quality
            let step = min(momentum, 1.0) * 0.5

            // Reduce scale first (less perceptible)
            scale -= step * Self.scaleWeight * Self.maxScaleStep * 2
            // Then reduce FPS
            fps -= step * Self.fpsWeight * Self.maxFPSStep * 2
        } else {
            // Cooling - restore quality slowly
            let step = min(abs(momentum), 1.0) * 0.5 * Self.recoverySpeedFactor

            // Restore scale first
            scale += step * Self.scaleWeight * Self.maxScaleStep * 2
            // Then restore FPS
            fps += step * Self.fpsWeight * Self.maxFPSStep * 2
        }

        // Apply damping when close to boundaries to prevent oscillation
        fps = applyDamping(fps, range: ThermalProfile.fpsRange)
        scale = applyDamping(scale, range: ThermalProfile.scaleRange)

        // Clamp to valid ranges
        return (
            fps.clamped(to: ThermalProfile.fpsRange),
            scale.clamped(to: ThermalProfile.scaleRange)
        )
    }

    /// Applies damping when approaching range boundaries.
    private func applyDamping(_ value: Float, range: ClosedRange<Float>) -> Float {
        let margin = (range.upperBound - range.lowerBound) * 0.1
        let lowerThreshold = range.lowerBound + margin
        let upperThreshold = range.upperBound - margin

        if value < lowerThreshold {
            // Near lower bound, slow down changes
            let factor = (value - range.lowerBound) / margin
            return range.lowerBound + (value - range.lowerBound) * max(factor, 0.3)
        } else if value > upperThreshold {
            // Near upper bound, slow down changes
            let factor = (range.upperBound - value) / margin
            return range.upperBound - (range.upperBound - value) * max(factor, 0.3)
        }

        return value
    }
}
