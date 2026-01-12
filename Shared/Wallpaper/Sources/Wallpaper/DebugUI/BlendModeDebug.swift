//
//  BlendModeDebug.swift
//  Wallpaper
//
//  Debug state for blend mode selection on playback controls
//

import SwiftUI

#if DEBUG
// MARK: - Blend Mode Debug State

/// All available SwiftUI blend modes for debug picker
public enum DebugBlendMode: String, CaseIterable, Identifiable, Sendable {
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
    case sourceAtop
    case destinationOver
    case destinationOut
    case plusDarker
    case plusLighter

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
        case .sourceAtop: "Source Atop"
        case .destinationOver: "Destination Over"
        case .destinationOut: "Destination Out"
        case .plusDarker: "Plus Darker"
        case .plusLighter: "Plus Lighter"
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
        case .sourceAtop: .sourceAtop
        case .destinationOver: .destinationOver
        case .destinationOut: .destinationOut
        case .plusDarker: .plusDarker
        case .plusLighter: .plusLighter
        }
    }
}

/// Shared state for playback controls debug settings
@MainActor
@Observable
public final class PlaybackControlsDebugState {
    public static let shared = PlaybackControlsDebugState()

    private static let blendModeKey = "PlaybackControls.blendMode"

    public var blendMode: DebugBlendMode {
        didSet {
            UserDefaults.standard.set(blendMode.rawValue, forKey: Self.blendModeKey)
        }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: Self.blendModeKey),
           let mode = DebugBlendMode(rawValue: saved) {
            self.blendMode = mode
        } else {
            self.blendMode = .colorDodge
        }
    }
}
#endif
