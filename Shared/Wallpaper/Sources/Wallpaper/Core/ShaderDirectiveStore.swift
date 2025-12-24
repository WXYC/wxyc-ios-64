//
//  ShaderDirectiveStore.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/22/25.
//

import Foundation
import Observation

/// Observable storage for shader compiler directive states.
///
/// Used to communicate directive toggle states between debug UI and the shader renderer.
/// Changes to directives trigger shader recompilation via `Observations`.
@Observable
@MainActor
public final class ShaderDirectiveStore {
    /// Information about a single directive
    public struct DirectiveInfo: Identifiable, Sendable {
        public let id: String
        public let displayName: String
        public var isEnabled: Bool

        public init(id: String, displayName: String, isEnabled: Bool = true) {
            self.id = id
            self.displayName = displayName
            self.isEnabled = isEnabled
        }
    }

    /// The directives available for this shader
    public private(set) var availableDirectives: [DirectiveInfo] = []

    public nonisolated init() {}

    /// Configures the store with available directives from the shader.
    public func configure(with directiveNames: [String]) {
        availableDirectives = directiveNames.map { name in
            DirectiveInfo(
                id: name,
                displayName: humanReadableName(for: name),
                isEnabled: loadSavedState(for: name)
            )
        }
    }

    /// Whether a specific directive is enabled.
    public func isEnabled(_ directiveId: String) -> Bool {
        availableDirectives.first(where: { $0.id == directiveId })?.isEnabled ?? true
    }

    /// Sets whether a directive is enabled.
    public func setEnabled(_ enabled: Bool, for directiveId: String) {
        guard let index = availableDirectives.firstIndex(where: { $0.id == directiveId }) else {
            return
        }
        availableDirectives[index].isEnabled = enabled
        saveState(enabled, for: directiveId)
    }

    /// All currently enabled directive names.
    public var enabledDirectiveNames: Set<String> {
        Set(availableDirectives.filter(\.isEnabled).map(\.id))
    }

    // MARK: - Private Helpers

    private func humanReadableName(for directive: String) -> String {
        // Convert ENABLE_UV_ROTATION to "UV Rotation"
        var name = directive

        // Remove common prefixes
        for prefix in ["ENABLE_", "USE_", "WITH_"] {
            if name.hasPrefix(prefix) {
                name = String(name.dropFirst(prefix.count))
                break
            }
        }

        // Convert SNAKE_CASE to Title Case
        return name
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private nonisolated func userDefaultsKey(for directiveId: String) -> String {
        "ShaderDirective.\(directiveId)"
    }

    private nonisolated func loadSavedState(for directiveId: String) -> Bool {
        let key = userDefaultsKey(for: directiveId)
        // Default to true if not saved
        if UserDefaults.standard.object(forKey: key) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    private nonisolated func saveState(_ enabled: Bool, for directiveId: String) {
        let key = userDefaultsKey(for: directiveId)
        UserDefaults.standard.set(enabled, forKey: key)
    }
}
