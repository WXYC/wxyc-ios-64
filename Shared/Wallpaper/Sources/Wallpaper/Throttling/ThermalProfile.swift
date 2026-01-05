import Foundation

/// Persistent thermal optimization profile for a specific shader.
///
/// Stores the learned optimal FPS and scale settings for a shader based on
/// observed thermal behavior. Profiles are persisted across app launches
/// to avoid re-learning optimal settings on each launch.
public struct ThermalProfile: Codable, Sendable, Equatable {

    /// Identifier for the shader this profile applies to.
    public let shaderId: String

    /// Target frames per second (15.0 - 60.0).
    public var fps: Float

    /// Render scale factor (0.5 - 1.0).
    public var scale: Float

    /// Last recorded thermal momentum for this shader.
    public var thermalMomentum: Float

    /// When this profile was last updated.
    public var lastUpdated: Date

    /// Number of optimization samples recorded.
    public var sampleCount: Int

    /// Number of sessions it took to reach stability (nil until first stable session).
    public var sessionsToStability: Int?

    /// Whether this profile has reached a stable optimized state.
    public var isStabilized: Bool

    /// Valid range for FPS.
    public static let fpsRange: ClosedRange<Float> = 15.0...60.0

    /// Valid range for scale.
    public static let scaleRange: ClosedRange<Float> = 0.333...1.0

    /// Creates a new thermal profile with default (maximum quality) settings.
    ///
    /// - Parameter shaderId: The identifier of the shader.
    public init(shaderId: String) {
        self.shaderId = shaderId
        self.fps = Self.fpsRange.upperBound
        self.scale = Self.scaleRange.upperBound
        self.thermalMomentum = 0
        self.lastUpdated = Date()
        self.sampleCount = 0
        self.sessionsToStability = nil
        self.isStabilized = false
    }

    /// Creates a thermal profile with specified values.
    public init(
        shaderId: String,
        fps: Float,
        scale: Float,
        thermalMomentum: Float = 0,
        lastUpdated: Date = Date(),
        sampleCount: Int = 0,
        sessionsToStability: Int? = nil,
        isStabilized: Bool = false
    ) {
        self.shaderId = shaderId
        self.fps = fps.clamped(to: Self.fpsRange)
        self.scale = scale.clamped(to: Self.scaleRange)
        self.thermalMomentum = thermalMomentum
        self.lastUpdated = lastUpdated
        self.sampleCount = sampleCount
        self.sessionsToStability = sessionsToStability
        self.isStabilized = isStabilized
    }

    /// Whether this profile is at maximum quality (no throttling applied).
    public var isAtMaxQuality: Bool {
        fps >= Self.fpsRange.upperBound - 0.1 && scale >= Self.scaleRange.upperBound - 0.01
    }

    /// Updates FPS and scale, clamping to valid ranges.
    public mutating func update(fps: Float, scale: Float) {
        self.fps = fps.clamped(to: Self.fpsRange)
        self.scale = scale.clamped(to: Self.scaleRange)
        self.lastUpdated = Date()
        self.sampleCount += 1
    }

    /// Marks this profile as having reached stability.
    public mutating func markStabilized() {
        guard !isStabilized else { return }
        isStabilized = true
        sessionsToStability = sampleCount
    }
}

// MARK: - Float Clamping Extension

extension Float {

    /// Clamps the value to the specified range.
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
