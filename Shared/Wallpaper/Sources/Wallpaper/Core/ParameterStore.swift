//
//  ParameterStore.swift
//  Wallpaper
//
//  Storage for shader parameter overrides.
//
//  Created by Jake Bromberg on 12/19/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Caching
import Foundation
import Observation

/// Observable storage for theme parameter values.
///
/// Stores current parameter values at runtime and syncs with UserDefaults
/// for persistence. The store is keyed by theme ID.
@Observable
@MainActor
public final class ParameterStore: Sendable {
    private var values: [String: Any] = [:]
    private let manifest: ThemeManifest
    private let defaults: DefaultsStorage

    public init(manifest: ThemeManifest, defaults: DefaultsStorage = UserDefaults.standard) {
        self.manifest = manifest
        self.defaults = defaults
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

    // MARK: - Float2 Values

    public func float2Value(for parameterId: String) -> (Float, Float) {
        if let tuple = values[parameterId] as? (Float, Float) {
            return tuple
        }
        return defaultFloat2Value(for: parameterId)
    }

    public func setFloat2(_ value: (Float, Float), for parameterId: String) {
        values[parameterId] = value
        // UserDefaults persistence for float2 would need special handling
    }

    // MARK: - Float3 Values

    public func float3Value(for parameterId: String) -> (Float, Float, Float) {
        if let tuple = values[parameterId] as? (Float, Float, Float) {
            return tuple
        }
        return defaultFloat3Value(for: parameterId)
    }

    public func setFloat3(_ value: (Float, Float, Float), for parameterId: String) {
        values[parameterId] = value
        // UserDefaults persistence for float3 would need special handling
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
    public func buildShaderArguments(
        time: Float,
        viewSize: (Float, Float),
        displayScale: Float
    ) -> [ShaderArgumentValue] {
        manifest.shaderArguments.map { arg in
            switch arg.source {
            case .time:
                return .float(time)
            case .viewSize:
                return .float2(viewSize.0, viewSize.1)
            case .viewWidth:
                return .float(viewSize.0)
            case .viewHeight:
                return .float(viewSize.1)
            case .displayScale:
                return .float(displayScale)
            case .parameter:
                guard let id = arg.id,
                      let param = manifest.parameters.first(where: { $0.id == id }) else {
                    return .float(0)
                }
                switch param.type {
                case .float:
                    let rawValue = floatValue(for: id)
                    let easedValue = applyEasing(rawValue, param: param)
                    return .float(easedValue)
                case .float2:
                    let (x, y) = float2Value(for: id)
                    return .float2(x, y)
                case .float3:
                    let (x, y, z) = float3Value(for: id)
                    return .float3(x, y, z)
                case .bool:
                    return .float(boolValue(for: id) ? 1.0 : 0.0)
                case .color:
                    let r = colorComponent("r", for: id)
                    let g = colorComponent("g", for: id)
                    let b = colorComponent("b", for: id)
                    return .float3(r, g, b)
                }
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
        for param in manifest.parameters {
            let key = storageKey(for: param)
            switch param.type {
            case .float:
                if defaults.object(forKey: key) != nil {
                    values[param.id] = defaults.float(forKey: key)
                }
            case .bool:
                if defaults.object(forKey: key) != nil {
                    values[param.id] = defaults.bool(forKey: key)
                }
            case .color:
                if let components = param.components {
                    for component in components {
                        let componentKey = storageKey(for: param, component: component)
                        if defaults.object(forKey: componentKey) != nil {
                            let storeKey = "\(param.id).\(component.id)"
                            values[storeKey] = defaults.float(forKey: componentKey)
                        }
                    }
                }
            case .float2, .float3:
                break
            }
        }
    }

    private func saveToDefaults(parameterId: String, value: Float) {
        guard let param = manifest.parameters.first(where: { $0.id == parameterId }) else { return }
        defaults.set(value, forKey: storageKey(for: param))
    }

    private func saveToDefaults(parameterId: String, value: Bool) {
        guard let param = manifest.parameters.first(where: { $0.id == parameterId }) else { return }
        defaults.set(value, forKey: storageKey(for: param))
    }

    private func saveColorComponentToDefaults(parameterId: String, componentId: String, value: Float) {
        guard let param = manifest.parameters.first(where: { $0.id == parameterId }),
              let component = param.components?.first(where: { $0.id == componentId }) else { return }
        defaults.set(value, forKey: storageKey(for: param, component: component))
    }

    /// Returns the UserDefaults key for a parameter.
    /// Uses the explicit `userDefaultsKey` if provided, otherwise auto-generates from theme and parameter IDs.
    private func storageKey(for param: ParameterDefinition) -> String {
        param.userDefaultsKey ?? "Theme.\(manifest.id).Param.\(param.id)"
    }

    /// Returns the UserDefaults key for a color component.
    /// Uses the explicit `userDefaultsKey` if provided, otherwise auto-generates from theme, parameter, and component IDs.
    private func storageKey(for param: ParameterDefinition, component: ParameterComponentDefinition) -> String {
        component.userDefaultsKey ?? "Theme.\(manifest.id).Param.\(param.id).\(component.id)"
    }

    private func defaultFloatValue(for parameterId: String) -> Float {
        manifest.parameters
            .first(where: { $0.id == parameterId })?
            .defaultValue.floatValue ?? 0
    }

    private func defaultFloat2Value(for parameterId: String) -> (Float, Float) {
        guard let param = manifest.parameters.first(where: { $0.id == parameterId }),
              case .float2(let x, let y) = param.defaultValue else {
            return (0, 0)
        }
        return (x, y)
    }

    private func defaultFloat3Value(for parameterId: String) -> (Float, Float, Float) {
        guard let param = manifest.parameters.first(where: { $0.id == parameterId }),
              case .float3(let x, let y, let z) = param.defaultValue else {
            return (0, 0, 0)
        }
        return (x, y, z)
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

    /// Applies the easing function defined in the parameter to a value.
    private func applyEasing(_ value: Float, param: ParameterDefinition) -> Float {
        guard let easing = param.easing,
              let range = param.range else {
            return value
        }
        // Normalize value to 0-1 range
        let normalized = (value - range.min) / (range.max - range.min)
        let clamped = max(0, min(1, normalized))
        // Apply easing
        let eased = easing.apply(to: clamped)
        // Scale back to original range
        return range.min + eased * (range.max - range.min)
    }
}

// MARK: - Shader Argument Values

public enum ShaderArgumentValue {
    case float(Float)
    case float2(Float, Float)
    case float3(Float, Float, Float)
}
