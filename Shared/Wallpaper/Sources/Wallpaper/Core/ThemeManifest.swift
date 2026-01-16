//
//  ThemeManifest.swift
//  Wallpaper
//
//  Theme manifest JSON model with shader parameters.
//
//  Created by Jake Bromberg on 12/19/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

/// Codable representation of a theme manifest.
/// Themes are the primary entity containing wallpaper configuration and styling properties.
@MainActor
public struct ThemeManifest: Codable, Sendable {
    public let id: String
    public let displayName: String
    public let version: String

    // Wallpaper configuration
    public let renderer: RendererConfiguration
    public let parameters: [ParameterDefinition]
    public let shaderArguments: [ShaderArgument]

    // Theme properties
    public let accent: AccentColor
    public let material: MaterialConfiguration
    public let button: ButtonConfiguration?

    enum CodingKeys: String, CodingKey {
        case id, displayName, version, renderer, parameters, shaderArguments
        case accent, material, button
    }

    public init(
        id: String,
        displayName: String,
        version: String,
        renderer: RendererConfiguration,
        parameters: [ParameterDefinition] = [],
        shaderArguments: [ShaderArgument] = [],
        accent: AccentColor,
        material: MaterialConfiguration,
        button: ButtonConfiguration = .colored
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.renderer = renderer
        self.parameters = parameters
        self.shaderArguments = shaderArguments
        self.accent = accent
        self.material = material
        self.button = button
    }
}

// MARK: - Renderer Configuration

public struct RendererConfiguration: Codable, Sendable {
    public let type: RendererType
    public let shaderFile: String?
    public let functionName: String?
    public let vertexFunction: String?
    public let fragmentFunction: String?
    public let layers: [LayerConfiguration]?
    public let timeScale: Float?
    public let passes: [PassConfiguration]?

    /// Maximum render scale (0.5 to 1.0). Caps resolution for expensive shaders
    /// to leave GPU headroom for UI rendering. Defaults to 1.0 (full resolution).
    public let maxScale: Float?

    /// Configuration for compute-based renderers (type == .compute).
    public let compute: ComputeConfiguration?

    public init(
        type: RendererType,
        shaderFile: String? = nil,
        functionName: String? = nil,
        vertexFunction: String? = nil,
        fragmentFunction: String? = nil,
        layers: [LayerConfiguration]? = nil,
        timeScale: Float? = nil,
        passes: [PassConfiguration]? = nil,
        maxScale: Float? = nil,
        compute: ComputeConfiguration? = nil
    ) {
        self.type = type
        self.shaderFile = shaderFile
        self.functionName = functionName
        self.vertexFunction = vertexFunction
        self.fragmentFunction = fragmentFunction
        self.layers = layers
        self.timeScale = timeScale
        self.passes = passes
        self.maxScale = maxScale
        self.compute = compute
    }

    /// Effective maximum scale (defaults to 1.0)
    public var effectiveMaxScale: Float {
        maxScale ?? 1.0
    }
}

// MARK: - Multi-Pass Configuration

/// Configuration for a single render pass in a multi-pass shader.
public struct PassConfiguration: Codable, Sendable {
    public let name: String
    public let fragmentFunction: String
    public let scale: Float?
    public let inputs: [PassInput]?

    public init(
        name: String,
        fragmentFunction: String,
        scale: Float? = nil,
        inputs: [PassInput]? = nil
    ) {
        self.name = name
        self.fragmentFunction = fragmentFunction
        self.scale = scale
        self.inputs = inputs
    }

    /// Effective scale factor (defaults to 1.0)
    public var effectiveScale: Float {
        scale ?? 1.0
    }
}

/// Input texture binding for a render pass.
public struct PassInput: Codable, Sendable {
    public let channel: Int
    public let source: String

    public init(channel: Int, source: String) {
        self.channel = channel
        self.source = source
    }

    /// Known special source values
    public static let previousFrame = "previousFrame"
    public static let noise = "noise"
}

// MARK: - Compute Shader Configuration

/// Configuration for compute-based wallpapers (e.g., physarum simulation).
public struct ComputeConfiguration: Codable, Sendable {
    /// Compute passes to execute each frame, in order.
    public let passes: [ComputePassConfiguration]

    /// Fragment function for final rendering to screen.
    public let renderFunction: String

    /// Persistent textures that survive between frames.
    public let persistentTextures: [PersistentTextureConfiguration]?

    /// Base particle count (scaled by LOD at runtime).
    public let particleCount: Int?

    public init(
        passes: [ComputePassConfiguration],
        renderFunction: String,
        persistentTextures: [PersistentTextureConfiguration]? = nil,
        particleCount: Int? = nil
    ) {
        self.passes = passes
        self.renderFunction = renderFunction
        self.persistentTextures = persistentTextures
        self.particleCount = particleCount
    }
}

/// Configuration for a single compute pass.
public struct ComputePassConfiguration: Codable, Sendable {
    /// Name of this pass (for debugging and texture references).
    public let name: String

    /// Metal compute function name.
    public let functionName: String

    /// Thread group size (defaults to 32x32x1 if not specified).
    public let threadGroupSize: [Int]?

    /// Textures to bind as inputs (read-only).
    public let inputs: [ComputeTextureBinding]?

    /// Textures to bind as outputs (write-only or read-write).
    public let outputs: [ComputeTextureBinding]?

    public init(
        name: String,
        functionName: String,
        threadGroupSize: [Int]? = nil,
        inputs: [ComputeTextureBinding]? = nil,
        outputs: [ComputeTextureBinding]? = nil
    ) {
        self.name = name
        self.functionName = functionName
        self.threadGroupSize = threadGroupSize
        self.inputs = inputs
        self.outputs = outputs
    }

    /// Effective thread group size (defaults to 32x32x1).
    public var effectiveThreadGroupSize: (Int, Int, Int) {
        guard let size = threadGroupSize, size.count >= 3 else {
            return (32, 32, 1)
        }
        return (size[0], size[1], size[2])
    }
}

/// Texture binding for compute passes.
public struct ComputeTextureBinding: Codable, Sendable {
    /// Texture index in the shader.
    public let index: Int

    /// Source texture name (references a persistent texture or special value).
    public let source: String

    /// For input bindings: if true, reads from the current buffer instead of previous.
    /// Use this when a later pass needs to read what an earlier pass in the same frame wrote.
    public let readFromCurrent: Bool?

    /// For output bindings: if true, writes to the previous buffer instead of current.
    /// Use this when you need to write to the "other" buffer (e.g., blur reads current, writes previous).
    public let writeToPrevious: Bool?

    public init(index: Int, source: String, readFromCurrent: Bool? = nil, writeToPrevious: Bool? = nil) {
        self.index = index
        self.source = source
        self.readFromCurrent = readFromCurrent
        self.writeToPrevious = writeToPrevious
    }

    /// Whether this input should read from current buffer (defaults to false = read from previous).
    public var shouldReadFromCurrent: Bool {
        readFromCurrent ?? false
    }

    /// Whether this output should write to previous buffer (defaults to false = write to current).
    public var shouldWriteToPrevious: Bool {
        writeToPrevious ?? false
    }

    /// Known special source values
    public static let trailMap = "trailMap"
    public static let particleBuffer = "particleBuffer"
    public static let counterBuffer = "counterBuffer"
}

/// Configuration for a persistent texture.
public struct PersistentTextureConfiguration: Codable, Sendable {
    /// Unique name for this texture.
    public let name: String

    /// Pixel format (e.g., "rg16Float", "r32Uint").
    public let format: String

    /// Scale relative to screen size (1.0 = full resolution).
    public let scale: Float?

    /// Whether this texture uses ping-pong double buffering.
    public let doubleBuffered: Bool?

    public init(
        name: String,
        format: String,
        scale: Float? = nil,
        doubleBuffered: Bool? = nil
    ) {
        self.name = name
        self.format = format
        self.scale = scale
        self.doubleBuffered = doubleBuffered
    }

    /// Effective scale (defaults to 1.0).
    public var effectiveScale: Float {
        scale ?? 1.0
    }

    /// Whether double buffering is enabled (defaults to false).
    public var isDoubleBuffered: Bool {
        doubleBuffered ?? false
    }
}

public enum RendererType: String, Codable, Sendable {
    case stitchable
    case rawMetal
    case composite
    case swiftUI
    case compute
}

// MARK: - Overlay Configuration

/// Shared overlay configuration used by both materials and buttons.
public struct OverlayConfiguration: Codable, Sendable, Equatable {
    /// The opacity of the overlay tint (0.0 to 1.0).
    public let opacity: Double

    /// The overlay darkness (0.0 = white, 1.0 = black).
    public let darkness: Double

    public init(opacity: Double = 0.0, darkness: Double = 1.0) {
        self.opacity = opacity
        self.darkness = darkness
    }
}

// MARK: - Material Configuration

/// Configuration for material/glass backgrounds.
public struct MaterialConfiguration: Codable, Sendable, Equatable {
    /// Whether content on top should use light or dark appearance.
    public let foreground: ForegroundStyle

    /// The blur radius for material backgrounds.
    /// Higher values create more blur. Typical range: 4.0 to 20.0.
    public let blurRadius: Double

    /// Overlay tint applied on top of the blur.
    public let overlay: OverlayConfiguration

    public init(
        foreground: ForegroundStyle,
        blurRadius: Double = 8.0,
        overlay: OverlayConfiguration = OverlayConfiguration()
    ) {
        self.foreground = foreground
        self.blurRadius = blurRadius
        self.overlay = overlay
    }
}

// MARK: - Button Configuration

/// Button appearance configuration as an enum with associated values.
/// Colored buttons have solid capsule backgrounds; glass buttons have overlay settings.
public enum ButtonConfiguration: Codable, Sendable, Equatable {
    case colored
    case glass(OverlayConfiguration)

    private enum CodingKeys: String, CodingKey {
        case style, opacity, darkness
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let style = try container.decode(String.self, forKey: .style)

        switch style {
        case "colored":
            self = .colored
        case "glass":
            let opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.0
            let darkness = try container.decodeIfPresent(Double.self, forKey: .darkness) ?? 1.0
            self = .glass(OverlayConfiguration(opacity: opacity, darkness: darkness))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .style,
                in: container,
                debugDescription: "Unknown button style: \(style)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .colored:
            try container.encode("colored", forKey: .style)
        case .glass(let overlay):
            try container.encode("glass", forKey: .style)
            try container.encode(overlay.opacity, forKey: .opacity)
            try container.encode(overlay.darkness, forKey: .darkness)
        }
    }
}

/// Configuration for a layer in a composite wallpaper.
public struct LayerConfiguration: Codable, Sendable {
    public let type: LayerType
    public let ref: String?

    public init(type: LayerType, ref: String? = nil) {
        self.type = type
        self.ref = ref
    }
}

public enum LayerType: String, Codable, Sendable {
    case wxycGradient
    case shader
}

// MARK: - Shader Arguments

public struct ShaderArgument: Codable, Sendable {
    public let source: ShaderArgumentSource
    public let id: String?

    public init(source: ShaderArgumentSource, id: String? = nil) {
        self.source = source
        self.id = id
    }
}

public enum ShaderArgumentSource: String, Codable, Sendable {
    case time
    case viewSize        // float2(width, height) - for shaders expecting float2
    case viewWidth       // float width - for shaders expecting separate floats
    case viewHeight      // float height - for shaders expecting separate floats
    case displayScale
    case parameter
    case color
}

// MARK: - Parameter Definitions

public struct ParameterDefinition: Codable, Sendable, Identifiable {
    public let id: String
    public let type: ParameterType
    public let label: String
    public let group: String?
    public let defaultValue: ParameterValue
    public let range: ParameterRange?
    public let userDefaultsKey: String?
    public let components: [ParameterComponentDefinition]?

    enum CodingKeys: String, CodingKey {
        case id, type, label, group
        case defaultValue = "default"
        case range, userDefaultsKey, components
    }

    public init(
        id: String,
        type: ParameterType,
        label: String,
        group: String? = nil,
        defaultValue: ParameterValue,
        range: ParameterRange? = nil,
        userDefaultsKey: String? = nil,
        components: [ParameterComponentDefinition]? = nil
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.group = group
        self.defaultValue = defaultValue
        self.range = range
        self.userDefaultsKey = userDefaultsKey
        self.components = components
    }
}

public enum ParameterType: String, Codable, Sendable {
    case float
    case float2
    case float3
    case color
    case bool
}

public struct ParameterRange: Codable, Sendable {
    public let min: Float
    public let max: Float

    public init(min: Float, max: Float) {
        self.min = min
        self.max = max
    }
}

/// For color parameters, defines each RGB component.
public struct ParameterComponentDefinition: Codable, Sendable {
    public let id: String
    public let label: String
    public let defaultValue: Float
    public let userDefaultsKey: String?

    enum CodingKeys: String, CodingKey {
        case id, label, userDefaultsKey
        case defaultValue = "default"
    }

    public init(
        id: String,
        label: String,
        defaultValue: Float,
        userDefaultsKey: String? = nil
    ) {
        self.id = id
        self.label = label
        self.defaultValue = defaultValue
        self.userDefaultsKey = userDefaultsKey
    }
}

// MARK: - Parameter Values

public enum ParameterValue: Codable, Sendable {
    case float(Float)
    case float2(Float, Float)
    case float3(Float, Float, Float)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
            return
        }

        if let floatValue = try? container.decode(Float.self) {
            self = .float(floatValue)
            return
        }

        if let array = try? container.decode([Float].self) {
            switch array.count {
            case 2:
                self = .float2(array[0], array[1])
            case 3:
                self = .float3(array[0], array[1], array[2])
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected 2 or 3 element array for vector type"
                )
            }
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Cannot decode parameter value"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .float(let value):
            try container.encode(value)
        case .float2(let x, let y):
            try container.encode([x, y])
        case .float3(let x, let y, let z):
            try container.encode([x, y, z])
        case .bool(let value):
            try container.encode(value)
        }
    }

    public var floatValue: Float? {
        if case .float(let v) = self { return v }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }
}

// MARK: - Override Application

extension ThemeManifest {
    /// Creates a new manifest with the provided overrides applied.
    /// Override values take precedence over the manifest's original values.
    public func applying(_ overrides: ThemeOverrides) -> ThemeManifest {
        ThemeManifest(
            id: id,
            displayName: displayName,
            version: version,
            renderer: renderer,
            parameters: parameters,
            shaderArguments: shaderArguments,
            accent: AccentColor(
                hue: overrides.accentHue ?? accent.hue,
                saturation: overrides.accentSaturation ?? accent.saturation,
                brightness: overrides.accentBrightness ?? accent.brightness
            ),
            material: MaterialConfiguration(
                foreground: material.foreground,
                blurRadius: overrides.blurRadius ?? material.blurRadius,
                overlay: OverlayConfiguration(
                    opacity: overrides.overlayOpacity ?? material.overlay.opacity,
                    darkness: overrides.overlayDarkness ?? material.overlay.darkness
                )
            ),
            button: button ?? .colored
        )
    }
}
