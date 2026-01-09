import Foundation

/// Computes optimal FPS, scale, and LOD adjustments based on thermal momentum.
///
/// Uses a reactive control loop that:
/// - Immediately reduces quality when heating (LOD first, then scale, then FPS)
/// - Slowly restores quality when cooling (half speed, scale first, then FPS, then LOD)
/// - Applies damping near equilibrium to prevent oscillation
public struct ThermalOptimizer: Sendable {

    /// Maximum FPS adjustment per optimization tick.
    public static let maxFPSStep: Float = 5.0

    /// Maximum scale adjustment per optimization tick.
    public static let maxScaleStep: Float = 0.05

    /// Maximum LOD adjustment per optimization tick.
    public static let maxLODStep: Float = 0.1

    /// How much slower to restore quality compared to reducing it.
    public static let recoverySpeedFactor: Float = 0.5

    /// Weight given to LOD adjustments. LOD changes are least perceptible.
    public static let lodWeight: Float = 0.2

    /// Weight given to scale adjustments. Scale changes are moderately perceptible.
    public static let scaleWeight: Float = 0.6

    /// Weight given to FPS adjustments. FPS changes are most perceptible.
    public static let fpsWeight: Float = 0.2

    public init() {}

    /// Computes the next FPS, scale, and LOD values based on thermal momentum.
    ///
    /// Reduction order (least to most perceptible): LOD -> Scale -> FPS
    /// Recovery order (reverse): Scale -> FPS -> LOD
    ///
    /// - Parameters:
    ///   - current: The current thermal profile.
    ///   - momentum: Current thermal momentum from ThermalSignal.
    /// - Returns: Tuple of (fps, scale, lod) with optimized values.
    public func optimize(current: ThermalProfile, momentum: Float) -> (fps: Float, scale: Float, lod: Float) {
        // In dead zone - no adjustment needed
        guard abs(momentum) > ThermalSignal.deadZone else {
            return (current.fps, current.scale, current.lod)
        }

        var fps = current.fps
        var scale = current.scale
        var lod = current.lod

        if momentum > 0 {
            // Heating - reduce quality (LOD first, then scale, then FPS)
            let step = min(momentum, 1.0) * 0.5

            // Reduce LOD first (least perceptible)
            lod -= step * Self.lodWeight * Self.maxLODStep * 5
            // Then reduce scale
            scale -= step * Self.scaleWeight * Self.maxScaleStep * 2
            // Finally reduce FPS (most perceptible)
            fps -= step * Self.fpsWeight * Self.maxFPSStep * 2
        } else {
            // Cooling - restore quality slowly (reverse order)
            let step = min(abs(momentum), 1.0) * 0.5 * Self.recoverySpeedFactor

            // Restore scale first
            scale += step * Self.scaleWeight * Self.maxScaleStep * 2
            // Then restore FPS
            fps += step * Self.fpsWeight * Self.maxFPSStep * 2
            // Finally restore LOD
            lod += step * Self.lodWeight * Self.maxLODStep * 5
        }

        // Apply damping when close to boundaries to prevent oscillation
        fps = applyDamping(fps, range: ThermalProfile.fpsRange)
        scale = applyDamping(scale, range: ThermalProfile.scaleRange)
        lod = applyDamping(lod, range: ThermalProfile.lodRange)

        // Clamp to valid ranges
        return (
            fps.clamped(to: ThermalProfile.fpsRange),
            scale.clamped(to: ThermalProfile.scaleRange),
            lod.clamped(to: ThermalProfile.lodRange)
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
