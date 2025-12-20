//
//  ParameterStore.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
//

import Foundation
import Observation

/// Observable storage for wallpaper parameter values.
///
/// Stores current parameter values at runtime and syncs with UserDefaults
/// for persistence. The store is keyed by wallpaper ID.
@Observable
public final class ParameterStore {
    private var values: [String: Any] = [:]
    private let manifest: WallpaperManifest

    public init(manifest: WallpaperManifest) {
        self.manifest = manifest
        loadFromDefaults()
    }

    // MARK: - Float Values

    public func floatValue(for parameterId: String) -> Float {
        values[parameterId] as? Float ?? defaultFloatValue(for: parameterId)
    }

    public func setFloat(_ value: Float, for parameterId: String) {
        values[parameterId] = value
        saveToDefaults(parameterId: parameterId, value: value)
    }

    // MARK: - Bool Values

    public func boolValue(for parameterId: String) -> Bool {
        values[parameterId] as? Bool ?? defaultBoolValue(for: parameterId)
    }

    public func setBool(_ value: Bool, for parameterId: String) {
        values[parameterId] = value
        saveToDefaults(parameterId: parameterId, value: value)
    }

    // MARK: - Color Values (as individual float components)

    public func colorComponent(_ componentId: String, for parameterId: String) -> Float {
        let key = "\(parameterId).\(componentId)"
        if let value = values[key] as? Float {
            return value
        }
        return defaultColorComponent(componentId, for: parameterId)
    }

    public func setColorComponent(_ componentId: String, value: Float, for parameterId: String) {
        let key = "\(parameterId).\(componentId)"
        values[key] = value
        saveColorComponentToDefaults(parameterId: parameterId, componentId: componentId, value: value)
    }

    // MARK: - Reset

    public func reset() {
        for param in manifest.parameters {
            switch param.type {
            case .float:
                if let defaultValue = param.defaultValue.floatValue {
                    setFloat(defaultValue, for: param.id)
                }
            case .bool:
                if let defaultValue = param.defaultValue.boolValue {
                    setBool(defaultValue, for: param.id)
                }
            case .color:
                if let components = param.components {
                    for component in components {
                        setColorComponent(component.id, value: component.defaultValue, for: param.id)
                    }
                }
            case .float2, .float3:
                // Handle vector types if needed
                break
            }
        }
    }

    // MARK: - Shader Argument Building

    /// Builds shader arguments based on the manifest's shaderArguments configuration.
    public func buildShaderArguments(time: Float, viewSize: (Float, Float), displayScale: Float) -> [ShaderArgumentValue] {
        manifest.shaderArguments.map { arg in
            switch arg.source {
            case .time:
                return .float(time)
            case .viewSize:
                return .float2(viewSize.0, viewSize.1)
            case .displayScale:
                return .float(displayScale)
            case .parameter:
                guard let id = arg.id else { return .float(0) }
                return .float(floatValue(for: id))
            case .color:
                guard let id = arg.id else { return .float3(0, 0, 0) }
                let r = colorComponent("r", for: id)
                let g = colorComponent("g", for: id)
                let b = colorComponent("b", for: id)
                return .float3(r, g, b)
            }
        }
    }

    // MARK: - Private Helpers

    private func loadFromDefaults() {
        let defaults = UserDefaults.standard
        for param in manifest.parameters {
            switch param.type {
            case .float:
                if let key = param.userDefaultsKey, defaults.object(forKey: key) != nil {
                    values[param.id] = defaults.float(forKey: key)
                }
            case .bool:
                if let key = param.userDefaultsKey, defaults.object(forKey: key) != nil {
                    values[param.id] = defaults.bool(forKey: key)
                }
            case .color:
                if let components = param.components {
                    for component in components {
                        if let key = component.userDefaultsKey, defaults.object(forKey: key) != nil {
                            let storeKey = "\(param.id).\(component.id)"
                            values[storeKey] = defaults.float(forKey: key)
                        }
                    }
                }
            case .float2, .float3:
                break
            }
        }
    }

    private func saveToDefaults(parameterId: String, value: Float) {
        guard let param = manifest.parameters.first(where: { $0.id == parameterId }),
              let key = param.userDefaultsKey else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private func saveToDefaults(parameterId: String, value: Bool) {
        guard let param = manifest.parameters.first(where: { $0.id == parameterId }),
              let key = param.userDefaultsKey else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private func saveColorComponentToDefaults(parameterId: String, componentId: String, value: Float) {
        guard let param = manifest.parameters.first(where: { $0.id == parameterId }),
              let component = param.components?.first(where: { $0.id == componentId }),
              let key = component.userDefaultsKey else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private func defaultFloatValue(for parameterId: String) -> Float {
        manifest.parameters
            .first(where: { $0.id == parameterId })?
            .defaultValue.floatValue ?? 0
    }

    private func defaultBoolValue(for parameterId: String) -> Bool {
        manifest.parameters
            .first(where: { $0.id == parameterId })?
            .defaultValue.boolValue ?? false
    }

    private func defaultColorComponent(_ componentId: String, for parameterId: String) -> Float {
        guard let param = manifest.parameters.first(where: { $0.id == parameterId }),
              let component = param.components?.first(where: { $0.id == componentId }) else {
            return 0
        }
        return component.defaultValue
    }
}

// MARK: - Shader Argument Values

public enum ShaderArgumentValue {
    case float(Float)
    case float2(Float, Float)
    case float3(Float, Float, Float)
}
