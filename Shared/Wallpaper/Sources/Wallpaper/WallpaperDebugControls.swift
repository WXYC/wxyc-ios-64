//
//  WallpaperDebugControls.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import SwiftUI

/// Debug controls for wallpaper settings, intended for use in a Form.
public struct WallpaperDebugControls: View {
    @Bindable var configuration: WallpaperConfiguration

    public init(configuration: WallpaperConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        Section {
            Picker("Wallpaper", selection: $configuration.selectedWallpaperID) {
                ForEach(WallpaperRegistry.shared.wallpapers) { wallpaper in
                    Text(wallpaper.displayName).tag(wallpaper.id)
                }
            }

            if let wallpaper = WallpaperRegistry.shared.wallpaper(for: configuration.selectedWallpaperID) {
                // Use id to force view recreation when wallpaper changes
                Group {
                    if !wallpaper.manifest.parameters.isEmpty {
                        DisclosureGroup("Parameters") {
                            WallpaperDebugControlsGenerator(wallpaper: wallpaper)
                        }
                    }

                    // Show shader directive toggles if available
                    ShaderDirectiveControls(wallpaper: wallpaper)
                }
                .id(wallpaper.id)
            }

            Button("Reset Wallpaper Settings") {
                configuration.reset()
            }
            .foregroundStyle(.red)

            Button("Nuke Legacy Data") {
                WallpaperConfiguration.nukeLegacyData()
            }
            .foregroundStyle(.red)
        } header: {
            Text("Wallpaper")
        }
    }
}

// MARK: - Shader Directive Controls

/// Shows toggles for shader compiler directives (feature flags).
private struct ShaderDirectiveControls: View {
    let wallpaper: LoadedWallpaper
    @State private var directives: [ShaderDirectiveStore.DirectiveInfo] = []

    var body: some View {
        if !directives.isEmpty {
            DisclosureGroup("Shader Features") {
                ForEach(directives) { directive in
                    Toggle(directive.displayName, isOn: Binding(
                        get: { wallpaper.directiveStore.isEnabled(directive.id) },
                        set: { wallpaper.directiveStore.setEnabled($0, for: directive.id) }
                    ))
                }

                Text("Changes recompile the shader")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    init(wallpaper: LoadedWallpaper) {
        self.wallpaper = wallpaper
        // Parse directives from shader source on init
        self._directives = State(initialValue: Self.parseDirectives(for: wallpaper))
    }

    private static func parseDirectives(for wallpaper: LoadedWallpaper) -> [ShaderDirectiveStore.DirectiveInfo] {
        guard let shaderFile = wallpaper.manifest.renderer.shaderFile else { return [] }

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
        if wallpaper.directiveStore.availableDirectives.isEmpty && !directives.isEmpty {
            wallpaper.directiveStore.configure(with: directives.map(\.id))
            // Apply initial states
            for directive in directives {
                if !directive.isEnabled {
                    wallpaper.directiveStore.setEnabled(false, for: directive.id)
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
