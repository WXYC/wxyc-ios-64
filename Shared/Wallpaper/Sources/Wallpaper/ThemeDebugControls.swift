//
//  ThemeDebugControls.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import SwiftUI

/// Debug controls for theme settings, intended for use in a Form.
public struct ThemeDebugControls: View {
    @Bindable var configuration: ThemeConfiguration

    public init(configuration: ThemeConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        Section {
            Picker("Theme", selection: $configuration.selectedThemeID) {
                ForEach(ThemeRegistry.shared.themes) { theme in
                    Text(theme.displayName).tag(theme.id)
                }
            }

            if let theme = configuration.selectedTheme {
                // Use id to force view recreation when theme changes
                Group {
                    if !theme.manifest.parameters.isEmpty {
                        #if os(tvOS)
                        Section("Parameters") {
                            ThemeDebugControlsGenerator(theme: theme)
                        }
                        #else
                        DisclosureGroup("Parameters") {
                            ThemeDebugControlsGenerator(theme: theme)
                        }
                        #endif
                    }

                    // Show shader directive toggles if available
                    ShaderDirectiveControls(theme: theme)
                }
                .id(theme.id)
            }

            Button("Reset Theme Settings") {
                configuration.reset()
            }
            .foregroundStyle(.red)

            Button("Nuke Legacy Data") {
                ThemeConfiguration.nukeLegacyData()
            }
            .foregroundStyle(.red)
        } header: {
            Text("Theme")
        }
    }
}

// MARK: - Shader Directive Controls

/// Shows toggles for shader compiler directives (feature flags).
private struct ShaderDirectiveControls: View {
    let theme: LoadedTheme
    @State private var directives: [ShaderDirectiveStore.DirectiveInfo] = []

    var body: some View {
        if !directives.isEmpty {
            #if os(tvOS)
            Section("Shader Features") {
                ForEach(directives) { directive in
                    Toggle(directive.displayName, isOn: Binding(
                        get: { theme.directiveStore.isEnabled(directive.id) },
                        set: { theme.directiveStore.setEnabled($0, for: directive.id) }
                    ))
                }

                Text("Changes recompile the shader")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #else
            DisclosureGroup("Shader Features") {
                ForEach(directives) { directive in
                    Toggle(directive.displayName, isOn: Binding(
                        get: { theme.directiveStore.isEnabled(directive.id) },
                        set: { theme.directiveStore.setEnabled($0, for: directive.id) }
                    ))
                }

                Text("Changes recompile the shader")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif
        }
    }

    init(theme: LoadedTheme) {
        self.theme = theme
        // Parse directives from shader source on init
        self._directives = State(initialValue: Self.parseDirectives(for: theme))
    }

    private static func parseDirectives(for theme: LoadedTheme) -> [ShaderDirectiveStore.DirectiveInfo] {
        guard let shaderFile = theme.manifest.renderer.shaderFile else { return [] }

        let shaderName = shaderFile.replacingOccurrences(of: ".metal", with: "")
        guard let url = Bundle.module.url(forResource: shaderName, withExtension: "metal"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        var directives: [ShaderDirectiveStore.DirectiveInfo] = []
        let lines = source.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Look for #define DIRECTIVE_NAME pattern (no value, just a flag)
            // Also handle commented defines: // #define DIRECTIVE_NAME
            let isCommented = trimmed.hasPrefix("// #define ") || trimmed.hasPrefix("//#define ")
            let definePrefix = isCommented ? (trimmed.hasPrefix("// #define ") ? "// #define " : "//#define ") : "#define "

            if trimmed.hasPrefix(definePrefix) || (trimmed.hasPrefix("#define ") && !isCommented) {
                let prefix = trimmed.hasPrefix("#define ") ? "#define " : definePrefix
                let rest = String(trimmed.dropFirst(prefix.count))
                let parts = rest.components(separatedBy: .whitespaces)
                if let name = parts.first, !name.isEmpty {
                    // Skip defines with values (like NOISE_OCTAVES 4)
                    let restAfterName = rest.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
                    if restAfterName.isEmpty || restAfterName.hasPrefix("//") {
                        // Load saved state or default to enabled (based on whether it's commented)
                        let key = "ShaderDirective.\(name)"
                        let isEnabled: Bool
                        if UserDefaults.standard.object(forKey: key) != nil {
                            isEnabled = UserDefaults.standard.bool(forKey: key)
                        } else {
                            isEnabled = !isCommented
                        }
                        directives.append(ShaderDirectiveStore.DirectiveInfo(
                            id: name,
                            displayName: humanReadableName(for: name),
                            isEnabled: isEnabled
                        ))
                    }
                }
            }
        }

        // Configure the store if not already configured
        if theme.directiveStore.availableDirectives.isEmpty && !directives.isEmpty {
            theme.directiveStore.configure(with: directives.map(\.id))
            // Apply initial states
            for directive in directives {
                if !directive.isEnabled {
                    theme.directiveStore.setEnabled(false, for: directive.id)
                }
            }
        }

        return directives
    }

    private static func humanReadableName(for directive: String) -> String {
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
}
