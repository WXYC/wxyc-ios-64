//
//  ThemeManifest.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
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
    public let foreground: ForegroundStyle
    public let accent: AccentColor
    public let appIconName: String?
    public let materialWeight: MaterialWeight
    public let buttonStyle: ButtonStyle?

    /// Tint applied to material backgrounds.
    /// Positive values lighten (white overlay), negative values darken (black overlay).
    /// Range: -1.0 to 1.0, where 0.0 is no tint.
    public let materialTint: Double

    /// Offset applied to LCD brightness values.
    /// Positive values increase brightness, negative values decrease it.
    /// Applied to both min and max brightness. Range: -0.5 to 0.5, default 0.0.
    private let _lcdBrightnessOffset: Double?

    /// Effective LCD brightness offset, defaulting to 0.0 if not specified.
    public var lcdBrightnessOffset: Double { _lcdBrightnessOffset ?? 0.0 }

    enum CodingKeys: String, CodingKey {
        case id, displayName, version, renderer, parameters, shaderArguments
        case foreground, accent, appIconName, materialWeight, buttonStyle, materialTint
        case _lcdBrightnessOffset = "lcdBrightnessOffset"
    }

    public init(
        id: String,
        displayName: String,
        version: String,
        renderer: RendererConfiguration,
        parameters: [ParameterDefinition] = [],
        shaderArguments: [ShaderArgument] = [],
        foreground: ForegroundStyle,
        accent: AccentColor,
        appIconName: String? = nil,
        materialWeight: MaterialWeight = .thin,
        buttonStyle: ButtonStyle = .colored,
        materialTint: Double = 0.0,
        lcdBrightnessOffset: Double = 0.0
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.renderer = renderer
        self.parameters = parameters
        self.shaderArguments = shaderArguments
        self.foreground = foreground
        self.accent = accent
        self.appIconName = appIconName
        self.materialWeight = materialWeight
        self.buttonStyle = buttonStyle
        self.materialTint = materialTint
        self._lcdBrightnessOffset = lcdBrightnessOffset
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

    public init(
        type: RendererType,
        shaderFile: String? = nil,
        functionName: String? = nil,
        vertexFunction: String? = nil,
        fragmentFunction: String? = nil,
        layers: [LayerConfiguration]? = nil,
        timeScale: Float? = nil,
        passes: [PassConfiguration]? = nil
    ) {
        self.type = type
        self.shaderFile = shaderFile
        self.functionName = functionName
        self.vertexFunction = vertexFunction
        self.fragmentFunction = fragmentFunction
        self.layers = layers
        self.timeScale = timeScale
        self.passes = passes
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

public enum RendererType: String, Codable, Sendable {
    case stitchable
    case rawMetal
    case composite
    case swiftUI
}

public enum ButtonStyle: String, Codable, Sendable {
    case colored   // Default: solid colored capsule backgrounds
    case glass     // Glass effect, no color background
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
