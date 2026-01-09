//
//  QualityProfile.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 1/5/26.
//

import Foundation

/// A fixed quality profile that overrides adaptive thermal optimization.
///
/// Use this to specify fixed FPS, scale, and LOD values for specific rendering contexts,
/// such as the wallpaper picker where lower quality is acceptable to reduce GPU load.
public struct QualityProfile: Equatable, Sendable {
    /// Target frames per second.
    public let fps: Float

    /// Render scale factor (0.5 to 1.0).
    public let scale: Float

    /// Shader level of detail (0.0 to 1.0).
    public let lod: Float

    /// Creates a quality profile with specified FPS, scale, and LOD.
    ///
    /// - Parameters:
    ///   - fps: Target frames per second (clamped to 15-60).
    ///   - scale: Render scale factor (clamped to 0.5-1.0).
    ///   - lod: Shader level of detail (clamped to 0.0-1.0, default 1.0).
    public init(fps: Float, scale: Float, lod: Float = 1.0) {
        self.fps = fps.clamped(to: ThermalProfile.fpsRange)
        self.scale = scale.clamped(to: ThermalProfile.scaleRange)
        self.lod = lod.clamped(to: ThermalProfile.lodRange)
    }

    /// Quality profile for wallpaper picker cards (30 FPS, 0.75 scale, 0.5 LOD).
    public static let picker = QualityProfile(fps: 30, scale: 0.75, lod: 0.5)
}
