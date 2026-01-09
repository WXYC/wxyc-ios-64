//
//  ThemeDebugOverlay.swift
//  Wallpaper
//
//  Floating button overlay that presents theme debug controls in a popover.
//

import SwiftUI

#if DEBUG
/// Floating button overlay for theme debug controls.
/// Shows a button in the bottom-right corner that presents a popover with
/// theme selection and parameter controls.
public struct ThemeDebugOverlay: View {
    @Bindable var configuration: ThemeConfiguration
    @State private var showingPopover = false

    public init(configuration: ThemeConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    showingPopover = true
                } label: {
                    Image(systemName: "photo.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
                #if os(tvOS)
                .sheet(isPresented: $showingPopover) {
                    ThemeDebugPopoverContent(configuration: configuration)
                }
                #else
                .popover(isPresented: $showingPopover) {
                    ThemeDebugPopoverContent(configuration: configuration)
                }
                #endif
            }
        }
        .padding()
    }
}

/// Content for the theme debug popover.
private struct ThemeDebugPopoverContent: View {
    @Bindable var configuration: ThemeConfiguration
    @AppStorage("ThemeDebug.isLCDBrightnessExpanded") private var isLCDBrightnessExpanded = false
    @AppStorage("ThemeDebug.isAccentColorExpanded") private var isAccentColorExpanded = false
    @AppStorage("ThemeDebug.isOverlayOpacityExpanded") private var isOverlayOpacityExpanded = false
    @AppStorage("ThemeDebug.isParametersExpanded") private var isParametersExpanded = false
    @AppStorage("ThemeDebug.isShaderFeaturesExpanded") private var isShaderFeaturesExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Theme picker (always visible)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Theme")
                        .font(.headline)

                    Picker("Theme", selection: $configuration.selectedThemeID) {
                        ForEach(ThemeRegistry.shared.themes) { theme in
                            Text(theme.displayName).tag(theme.id)
                        }
                    }
                    .labelsHidden()
                }

                Divider()

                let theme = ThemeRegistry.shared.theme(for: configuration.selectedThemeID)

                // LCD brightness controls
                DisclosureGroup(isExpanded: $isLCDBrightnessExpanded) {
                    LCDBrightnessControls(configuration: configuration, theme: theme)
                        .padding(.top, 8)
                } label: {
                    Text("LCD Brightness")
                        .font(.headline)
                }

                if let theme {
                    // Accent color controls
                    DisclosureGroup(isExpanded: $isAccentColorExpanded) {
                        AccentColorControls(configuration: configuration, theme: theme)
                            .padding(.top, 8)
                    } label: {
                        HStack {
                            Text("Accent Color")
                                .font(.headline)
                            Spacer()
                            RoundedRectangle(cornerRadius: 4)
                                .fill(configuration.effectiveAccentColor.color(brightness: 0.8))
                                .frame(width: 20, height: 20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }

                    // Overlay opacity controls
                    DisclosureGroup(isExpanded: $isOverlayOpacityExpanded) {
                        OverlayOpacityControls(configuration: configuration, theme: theme)
                            .padding(.top, 8)
                    } label: {
                        Text("Overlay Opacity")
                            .font(.headline)
                    }

                    // Parameters
                    if !theme.manifest.parameters.isEmpty {
                        DisclosureGroup(isExpanded: $isParametersExpanded) {
                            ThemeDebugControlsGenerator(theme: theme)
                                .padding(.top, 8)
                        } label: {
                            Text("Parameters")
                                .font(.headline)
                        }
                    }

                    // Shader directives
                    ShaderDirectiveControlsDisclosure(
                        theme: theme,
                        isExpanded: $isShaderFeaturesExpanded
                    )
                }

                Divider()

                // Reset button
                Button("Reset Theme Settings") {
                    configuration.reset()
                }
                .foregroundStyle(.red)
            }
            .padding()
        }
        .frame(minWidth: 300, minHeight: 200)
        .presentationCompactAdaptation(.popover)
    }
}

/// Controls for adjusting the theme's accent color hue and saturation.
private struct AccentColorControls: View {
    @Bindable var configuration: ThemeConfiguration
    let theme: LoadedTheme

    private var hueBinding: Binding<Double> {
        Binding(
            get: { configuration.accentHueOverride ?? theme.manifest.accent.hue },
            set: { configuration.accentHueOverride = $0 }
        )
    }

    private var saturationBinding: Binding<Double> {
        Binding(
            get: { configuration.accentSaturationOverride ?? theme.manifest.accent.saturation },
            set: { configuration.accentSaturationOverride = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hue: \(Int(hueBinding.wrappedValue))°")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: hueBinding, in: 0...360)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Saturation: \(Int(saturationBinding.wrappedValue * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: saturationBinding, in: 0...1)
            }

            if configuration.accentHueOverride != nil || configuration.accentSaturationOverride != nil {
                Button("Reset to Theme Default") {
                    configuration.accentHueOverride = nil
                    configuration.accentSaturationOverride = nil
                }
                .font(.caption)
            }
        }
    }
}

/// Controls for adjusting the theme's overlay opacity.
private struct OverlayOpacityControls: View {
    @Bindable var configuration: ThemeConfiguration
    let theme: LoadedTheme

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { configuration.overlayOpacityOverride ?? theme.manifest.overlayOpacity },
            set: { configuration.overlayOpacityOverride = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Opacity: \(Int(opacityBinding.wrappedValue * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: opacityBinding, in: 0...1)
            }

            Text("Overlay is \(theme.manifest.overlayIsDark ? "dark (black)" : "light (white)")")
                .font(.caption)
                .foregroundStyle(.secondary)

            if configuration.overlayOpacityOverride != nil {
                Button("Reset to Theme Default") {
                    configuration.overlayOpacityOverride = nil
                }
                .font(.caption)
            }
        }
    }
}

/// Controls for adjusting the LCD visualizer brightness.
private struct LCDBrightnessControls: View {
    @Bindable var configuration: ThemeConfiguration
    let theme: LoadedTheme?

    private var offsetBinding: Binding<Double> {
        Binding(
            get: {
                configuration.lcdBrightnessOffsetOverride ?? theme?.manifest.lcdBrightnessOffset ?? 0.0
            },
            set: { configuration.lcdBrightnessOffsetOverride = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Min: \(configuration.lcdMinBrightness, format: .number.precision(.fractionLength(2)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $configuration.lcdMinBrightness, in: 0...1.5)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Max: \(configuration.lcdMaxBrightness, format: .number.precision(.fractionLength(2)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $configuration.lcdMaxBrightness, in: 0...1.5)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Offset: \(offsetBinding.wrappedValue, format: .number.precision(.fractionLength(2)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: offsetBinding, in: -0.5...0.5)
            }

            Text("Offset adjusts both min and max values per-theme")
                .font(.caption)
                .foregroundStyle(.secondary)

            let hasCustomValues =
                configuration.lcdMinBrightness != ThemeConfiguration.defaultLCDMinBrightness ||
                configuration.lcdMaxBrightness != ThemeConfiguration.defaultLCDMaxBrightness ||
                configuration.lcdBrightnessOffsetOverride != nil

            if hasCustomValues {
                Button("Reset to Default") {
                    configuration.lcdMinBrightness = ThemeConfiguration.defaultLCDMinBrightness
                    configuration.lcdMaxBrightness = ThemeConfiguration.defaultLCDMaxBrightness
                    configuration.lcdBrightnessOffsetOverride = nil
                }
                .font(.caption)
            }
        }
    }
}

/// Shader directive controls with disclosure group wrapper.
private struct ShaderDirectiveControlsDisclosure: View {
    let theme: LoadedTheme
    @Binding var isExpanded: Bool
    @State private var directives: [ShaderDirectiveStore.DirectiveInfo] = []

    var body: some View {
        if !directives.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 8) {
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
                .padding(.top, 8)
            } label: {
                Text("Shader Features")
                    .font(.headline)
            }
        }
    }

    init(theme: LoadedTheme, isExpanded: Binding<Bool>) {
        self.theme = theme
        self._isExpanded = isExpanded
        self._directives = State(initialValue: Self.parseDirectives(for: theme))
    }

    private static func parseDirectives(for theme: LoadedTheme) -> [ShaderDirectiveStore.DirectiveInfo] {
        guard let shaderFile = theme.manifest.renderer.shaderFile else { return [] }

        let shaderName = shaderFile.replacing(".metal", with: "")
        guard let url = Bundle.module.url(forResource: shaderName, withExtension: "metal"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        var directives: [ShaderDirectiveStore.DirectiveInfo] = []
        let lines = source.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isCommented = trimmed.hasPrefix("// #define ") || trimmed.hasPrefix("//#define ")
            let definePrefix = isCommented ? (trimmed.hasPrefix("// #define ") ? "// #define " : "//#define ") : "#define "

            if trimmed.hasPrefix(definePrefix) || (trimmed.hasPrefix("#define ") && !isCommented) {
                let prefix = trimmed.hasPrefix("#define ") ? "#define " : definePrefix
                let rest = String(trimmed.dropFirst(prefix.count))
                let parts = rest.components(separatedBy: .whitespaces)
                if let name = parts.first, !name.isEmpty {
                    let restAfterName = rest.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
                    if restAfterName.isEmpty || restAfterName.hasPrefix("//") {
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

        if theme.directiveStore.availableDirectives.isEmpty && !directives.isEmpty {
            theme.directiveStore.configure(with: directives.map(\.id))
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

        for prefix in ["ENABLE_", "USE_", "WITH_"] {
            if name.hasPrefix(prefix) {
                name = String(name.dropFirst(prefix.count))
                break
            }
        }

        return name
            .replacing("_", with: " ")
            .capitalized
    }
}
#endif
