//
//  PlaybackBlendMode.swift
//  Wallpaper
//
//  Blend mode options for playback controls, stored per-theme
//
//  Created by Jake Bromberg on 12/01/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

// MARK: - Playback Blend Mode

/// Available SwiftUI blend modes for the playback button.
/// Stored per-theme in ThemeConfiguration.
///
/// Note: Compositing modes (sourceAtop, destinationOver, destinationOut,
/// plusDarker, plusLighter) are excluded because they don't interpolate
/// correctly with opacity crossfade during theme transitions.
public enum PlaybackBlendMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case normal
    case multiply
    case screen
    case overlay
    case darken
    case lighten
    case colorDodge
    case colorBurn
    case softLight
    case hardLight
    case difference
    case exclusion
    case hue
    case saturation
    case color
    case luminosity

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .normal: "Normal"
        case .multiply: "Multiply"
        case .screen: "Screen"
        case .overlay: "Overlay"
        case .darken: "Darken"
        case .lighten: "Lighten"
        case .colorDodge: "Color Dodge"
        case .colorBurn: "Color Burn"
        case .softLight: "Soft Light"
        case .hardLight: "Hard Light"
        case .difference: "Difference"
        case .exclusion: "Exclusion"
        case .hue: "Hue"
        case .saturation: "Saturation"
        case .color: "Color"
        case .luminosity: "Luminosity"
        }
    }

    public var blendMode: BlendMode {
        switch self {
        case .normal: .normal
        case .multiply: .multiply
        case .screen: .screen
        case .overlay: .overlay
        case .darken: .darken
        case .lighten: .lighten
        case .colorDodge: .colorDodge
        case .colorBurn: .colorBurn
        case .softLight: .softLight
        case .hardLight: .hardLight
        case .difference: .difference
        case .exclusion: .exclusion
        case .hue: .hue
        case .saturation: .saturation
        case .color: .color
        case .luminosity: .luminosity
        }
    }

    /// The default blend mode for playback controls
    public static let `default`: PlaybackBlendMode = .colorDodge
}

// MARK: - Environment Key

private struct PlaybackBlendModeKey: EnvironmentKey {
    static let defaultValue: BlendMode = PlaybackBlendMode.default.blendMode
}

public extension EnvironmentValues {
    /// The blend mode to apply to playback controls
    var playbackBlendMode: BlendMode {
        get { self[PlaybackBlendModeKey.self] }
        set { self[PlaybackBlendModeKey.self] = newValue }
    }
}

public extension View {
    /// Sets the blend mode for playback controls in this view hierarchy
    func playbackBlendMode(_ mode: BlendMode) -> some View {
        environment(\.playbackBlendMode, mode)
    }
}
