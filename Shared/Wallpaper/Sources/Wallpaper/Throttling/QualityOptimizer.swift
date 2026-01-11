import Foundation

/// Computes optimal wallpaper FPS, scale, and LOD adjustments based on quality momentum.
///
/// Uses a 3-axis (LOD, Scale, WallpaperFPS) reactive control loop that:
/// - Immediately reduces quality when heating
/// - Slowly restores quality when cooling (half speed)
/// - Applies damping near equilibrium to prevent oscillation
public struct QualityOptimizer: Sendable {

    // MARK: - Constants

    /// Maximum wallpaper FPS adjustment per optimization tick.
    public static let maxWallpaperFPSStep: Float = 5.0

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

    /// Weight given to wallpaper FPS adjustments. FPS changes are most perceptible.
    public static let wallpaperFPSWeight: Float = 0.2

    public init() {}

    /// Computes the next wallpaper FPS, scale, and LOD values based on quality momentum.
    ///
    /// - Reduction order (least to most perceptible): LOD -> Scale -> Wallpaper FPS
    /// - Recovery order (reverse): Scale -> Wallpaper FPS -> LOD
    ///
    /// - Parameters:
    ///   - current: The current adaptive profile.
    ///   - momentum: Current quality momentum from QualitySignal.
    /// - Returns: Tuple of (wallpaperFPS, scale, lod) with optimized values.
    public func optimize(
        current: AdaptiveProfile,
        momentum: Float
    ) -> (wallpaperFPS: Float, scale: Float, lod: Float) {
        // In dead zone - no adjustment needed
        guard abs(momentum) > QualitySignal.deadZone else {
            return (current.wallpaperFPS, current.scale, current.lod)
        }

        var wallpaperFPS = current.wallpaperFPS
        var scale = current.scale
        var lod = current.lod

        if momentum > 0 {
            // Heating - reduce quality (LOD first, then scale, then wallpaper FPS)
            let step = min(momentum, 1.0) * 0.5

            // Reduce LOD first (least perceptible)
            lod -= step * Self.lodWeight * Self.maxLODStep * 5
            // Then reduce scale
            scale -= step * Self.scaleWeight * Self.maxScaleStep * 2
            // Finally reduce wallpaper FPS (most perceptible)
            wallpaperFPS -= step * Self.wallpaperFPSWeight * Self.maxWallpaperFPSStep * 2
        } else {
            // Cooling - restore quality slowly (reverse order)
            let step = min(abs(momentum), 1.0) * 0.5 * Self.recoverySpeedFactor

            // Restore scale first
            scale += step * Self.scaleWeight * Self.maxScaleStep * 2
            // Then restore wallpaper FPS
            wallpaperFPS += step * Self.wallpaperFPSWeight * Self.maxWallpaperFPSStep * 2
            // Finally restore LOD
            lod += step * Self.lodWeight * Self.maxLODStep * 5
        }

        // Apply damping when close to boundaries to prevent oscillation
        wallpaperFPS = applyDamping(wallpaperFPS, range: AdaptiveProfile.wallpaperFPSRange)
        scale = applyDamping(scale, range: AdaptiveProfile.scaleRange)
        lod = applyDamping(lod, range: AdaptiveProfile.lodRange)

        // Clamp to valid ranges
        return (
            wallpaperFPS.clamped(to: AdaptiveProfile.wallpaperFPSRange),
            scale.clamped(to: AdaptiveProfile.scaleRange),
            lod.clamped(to: AdaptiveProfile.lodRange)
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
