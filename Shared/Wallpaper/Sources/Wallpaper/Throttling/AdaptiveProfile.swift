//
//  AdaptiveProfile.swift
//  Wallpaper
//
//  Device-specific quality profile for adaptive rendering.
//
//  Created by Jake Bromberg on 01/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Persistent thermal optimization profile for a specific shader.
///
/// Stores the learned optimal wallpaper FPS and scale settings for a shader based on
/// observed thermal behavior. Profiles are persisted across app launches
/// to avoid re-learning optimal settings on each launch.
public struct AdaptiveProfile: Codable, Sendable, Equatable {

    /// Identifier for the shader this profile applies to.
    public let shaderId: String

    /// Target wallpaper frames per second (15.0 - 60.0).
    public var wallpaperFPS: Float

    /// Render scale factor (0.5 - 1.0).
    public var scale: Float

    /// Shader level of detail (0.0 - 1.0, where 1.0 is full quality).
    public var lod: Float

    /// Last recorded thermal momentum for this shader.
    public var qualityMomentum: Float

    /// When this profile was last updated.
    public var lastUpdated: Date

    /// Number of optimization samples recorded.
    public var sampleCount: Int

    /// Number of sessions it took to reach stability (nil until first stable session).
    public var sessionsToStability: Int?

    /// Whether this profile has reached a stable optimized state.
    public var isStabilized: Bool

    /// Valid range for wallpaper FPS.
    public static let wallpaperFPSRange: ClosedRange<Float> = 15.0...60.0

    /// Valid range for scale.
    public static let scaleRange: ClosedRange<Float> = 0.5...1.0

    /// Valid range for LOD.
    public static let lodRange: ClosedRange<Float> = 0.0...1.0

    /// Creates a new thermal profile with default (maximum quality) settings.
    ///
    /// - Parameter shaderId: The identifier of the shader.
    public init(shaderId: String) {
        self.shaderId = shaderId
        self.wallpaperFPS = Self.wallpaperFPSRange.upperBound
        self.scale = Self.scaleRange.upperBound
        self.lod = Self.lodRange.upperBound
        self.qualityMomentum = 0
        self.lastUpdated = Date()
        self.sampleCount = 0
        self.sessionsToStability = nil
        self.isStabilized = false
    }

    /// Creates a thermal profile with specified values.
    public init(
        shaderId: String,
        wallpaperFPS: Float,
        scale: Float,
        lod: Float = 1.0,
        qualityMomentum: Float = 0,
        lastUpdated: Date = Date(),
        sampleCount: Int = 0,
        sessionsToStability: Int? = nil,
        isStabilized: Bool = false
    ) {
        self.shaderId = shaderId
        self.wallpaperFPS = wallpaperFPS.clamped(to: Self.wallpaperFPSRange)
        self.scale = scale.clamped(to: Self.scaleRange)
        self.lod = lod.clamped(to: Self.lodRange)
        self.qualityMomentum = qualityMomentum
        self.lastUpdated = lastUpdated
        self.sampleCount = sampleCount
        self.sessionsToStability = sessionsToStability
        self.isStabilized = isStabilized
    }

    /// Whether this profile is at maximum quality (no throttling applied).
    public var isAtMaxQuality: Bool {
        wallpaperFPS >= Self.wallpaperFPSRange.upperBound - 0.1
            && scale >= Self.scaleRange.upperBound - 0.01
            && lod >= Self.lodRange.upperBound - 0.01
    }

    /// Updates wallpaper FPS, scale, and LOD, clamping to valid ranges.
    public mutating func update(wallpaperFPS: Float, scale: Float, lod: Float) {
        self.wallpaperFPS = wallpaperFPS.clamped(to: Self.wallpaperFPSRange)
        self.scale = scale.clamped(to: Self.scaleRange)
        self.lod = lod.clamped(to: Self.lodRange)
        self.lastUpdated = Date()
        self.sampleCount += 1
    }

    /// Marks this profile as having reached stability.
    public mutating func markStabilized() {
        guard !isStabilized else { return }
        isStabilized = true
        sessionsToStability = sampleCount
    }

    // MARK: - Codable (backward compatible)

    private enum CodingKeys: String, CodingKey {
        case shaderId
        case wallpaperFPS = "fps"  // Keep "fps" key for backward compatibility
        case scale, lod, qualityMomentum, lastUpdated, sampleCount
        case sessionsToStability, isStabilized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shaderId = try container.decode(String.self, forKey: .shaderId)
        wallpaperFPS = try container.decode(Float.self, forKey: .wallpaperFPS)
        scale = try container.decode(Float.self, forKey: .scale)
        // Default to max LOD for profiles saved before LOD was added
        lod = try container.decodeIfPresent(Float.self, forKey: .lod) ?? Self.lodRange.upperBound
        qualityMomentum = try container.decode(Float.self, forKey: .qualityMomentum)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        sampleCount = try container.decode(Int.self, forKey: .sampleCount)
        sessionsToStability = try container.decodeIfPresent(Int.self, forKey: .sessionsToStability)
        isStabilized = try container.decode(Bool.self, forKey: .isStabilized)
    }
}

// MARK: - Float Clamping Extension

extension Float {

    /// Clamps the value to the specified range.
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
