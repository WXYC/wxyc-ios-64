//
//  ThemeDebugOverlay.swift
//  Wallpaper
//
//  Floating button overlay that presents theme debug controls in a popover.
//

import ColorPalette
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
    @AppStorage("ThemeDebug.isMaterialExpanded") private var isMaterialExpanded = false
    @AppStorage("ThemeDebug.isParametersExpanded") private var isParametersExpanded = false
    @AppStorage("ThemeDebug.isShaderFeaturesExpanded") private var isShaderFeaturesExpanded = false
    @AppStorage("ThemeDebug.isPerformanceExpanded") private var isPerformanceExpanded = false
    @AppStorage("ThemeDebug.isPlaybackButtonExpanded") private var isPlaybackButtonExpanded = false

    @State private var isExporting = false
    @State private var exportError: Error?
    @State private var showingExportError = false
    #if canImport(UIKit) && !os(tvOS)
    @State private var exportedFileURL: URL?
    @State private var showingShareSheet = false
    #endif

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

                    // Material controls (blur, dark/light, opacity)
                    DisclosureGroup(isExpanded: $isMaterialExpanded) {
                        MaterialControls(configuration: configuration, theme: theme)
                            .padding(.top, 8)
                    } label: {
                        Text("Material")
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

                // Playback Button Blend Mode
                DisclosureGroup(isExpanded: $isPlaybackButtonExpanded) {
                    PlaybackButtonControls(configuration: configuration)
                        .padding(.top, 8)
                } label: {
                    Text("Playback Button")
                        .font(.headline)
                }

                // Performance controls (always visible)
                DisclosureGroup(isExpanded: $isPerformanceExpanded) {
                    PerformanceControls()
                        .padding(.top, 8)
                } label: {
                    Text("Performance")
                        .font(.headline)
                }

                Divider()

                // Reset button
                Button("Reset Theme Settings") {
                    configuration.reset()
                }
                .foregroundStyle(.red)

                #if canImport(UIKit) && !os(tvOS)
                Divider()

                // Export button
                Button {
                    Task {
                        await exportAllThemes()
                    }
                } label: {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text("Export All Themes")
                    }
                }
                .disabled(isExporting)
                #endif
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: isLCDBrightnessExpanded)
            .animation(.easeInOut(duration: 0.2), value: isAccentColorExpanded)
            .animation(.easeInOut(duration: 0.2), value: isMaterialExpanded)
            .animation(.easeInOut(duration: 0.2), value: isParametersExpanded)
            .animation(.easeInOut(duration: 0.2), value: isShaderFeaturesExpanded)
            .animation(.easeInOut(duration: 0.2), value: isPerformanceExpanded)
            .animation(.easeInOut(duration: 0.2), value: isPlaybackButtonExpanded)
        }
        .frame(minWidth: 300, minHeight: 200, maxHeight: 600)
        .presentationCompactAdaptation(.popover)
        #if canImport(UIKit) && !os(tvOS)
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
            }
        }
        #endif
        .alert("Export Failed", isPresented: $showingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError?.localizedDescription ?? "Unknown error")
        }
    }

    #if canImport(UIKit) && !os(tvOS)
    private func exportAllThemes() async {
        isExporting = true
        defer { isExporting = false }

        let exporter = ThemeExporter(configuration: configuration)

        do {
            let zipURL = try await exporter.exportAllThemes()
            exportedFileURL = zipURL
            showingShareSheet = true
        } catch {
            exportError = error
            showingExportError = true
        }
    }
    #endif
}

/// Controls for adjusting the theme's accent color hue, saturation, and brightness.
private struct AccentColorControls: View {
    @Bindable var configuration: ThemeConfiguration
    let theme: LoadedTheme
    @State private var generatedModeLabel: String?

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

    private var brightnessBinding: Binding<Double> {
        Binding(
            get: { configuration.accentBrightnessOverride ?? theme.manifest.accent.brightness },
            set: { configuration.accentBrightnessOverride = $0 }
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

            VStack(alignment: .leading, spacing: 4) {
                Text("Brightness: \(brightnessBinding.wrappedValue, format: .number.precision(.fractionLength(2)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: brightnessBinding, in: 0.5...1.5)
            }

            Divider()

            // Generate accent color from wallpaper snapshot
            Button {
                generateAccentFromWallpaper()
            } label: {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("Generate from Wallpaper")
                }
            }
            .font(.caption)

            if let modeLabel = generatedModeLabel {
                Text("Generated using \(modeLabel) palette")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            let hasOverrides =
                configuration.accentHueOverride != nil ||
                configuration.accentSaturationOverride != nil ||
                configuration.accentBrightnessOverride != nil

            if hasOverrides {
                Button("Reset to Theme Default") {
                    configuration.accentHueOverride = nil
                    configuration.accentSaturationOverride = nil
                    configuration.accentBrightnessOverride = nil
                    generatedModeLabel = nil
                }
                .font(.caption)
            }
        }
    }

    private func generateAccentFromWallpaper() {
        // Capture snapshot from the active wallpaper renderer
        guard let snapshot = MetalWallpaperRenderer.captureMainSnapshot() else { return }

        // Extract dominant color
        let extractor = DominantColorExtractor()
        guard let dominantColor = extractor.extractDominantColor(from: snapshot) else { return }

        // Pick a random palette mode
        let allModes = PaletteMode.allCases
        guard let randomMode = allModes.randomElement() else { return }

        // Generate palette
        let generator = PaletteGenerator()
        let palette = generator.generatePalette(from: dominantColor, mode: randomMode)

        // Pick a random color from the palette
        guard let selectedColor = palette.colors.randomElement() else { return }

        // Apply to accent color overrides
        configuration.accentHueOverride = selectedColor.hue
        configuration.accentSaturationOverride = selectedColor.saturation
        configuration.accentBrightnessOverride = selectedColor.brightness

        // Update label to show which mode was used
        generatedModeLabel = randomMode.rawValue
    }
}

/// Controls for adjusting the theme's material properties (blur, dark/light, opacity).
private struct MaterialControls: View {
    @Bindable var configuration: ThemeConfiguration
    let theme: LoadedTheme

    private var blurRadiusBinding: Binding<Double> {
        Binding(
            get: { configuration.blurRadiusOverride ?? theme.manifest.blurRadius },
            set: { configuration.blurRadiusOverride = $0 }
        )
    }

    private var isDarkBinding: Binding<Bool> {
        Binding(
            get: { configuration.overlayIsDarkOverride ?? theme.manifest.overlayIsDark },
            set: { configuration.overlayIsDarkOverride = $0 }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { configuration.overlayOpacityOverride ?? theme.manifest.overlayOpacity },
            set: { configuration.overlayOpacityOverride = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Blur radius slider
            VStack(alignment: .leading, spacing: 4) {
                Text("Blur Radius: \(blurRadiusBinding.wrappedValue, format: .number.precision(.fractionLength(1)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: blurRadiusBinding, in: 0...30)
            }

            Divider()

            // Dark/Light toggle
            Toggle(isOn: isDarkBinding) {
                Text(isDarkBinding.wrappedValue ? "Dark Overlay" : "Light Overlay")
                    .font(.caption)
            }

            Divider()

            // Opacity slider
            VStack(alignment: .leading, spacing: 4) {
                Text("Opacity: \(Int(opacityBinding.wrappedValue * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: opacityBinding, in: 0...1)
            }

            // Reset button
            let hasOverrides =
                configuration.blurRadiusOverride != nil ||
                configuration.overlayIsDarkOverride != nil ||
                configuration.overlayOpacityOverride != nil

            if hasOverrides {
                Button("Reset to Theme Default") {
                    configuration.blurRadiusOverride = nil
                    configuration.overlayIsDarkOverride = nil
                    configuration.overlayOpacityOverride = nil
                }
                .font(.caption)
            }
        }
    }
}

/// Controls for adjusting the LCD visualizer HSB offsets.
private struct LCDBrightnessControls: View {
    @Bindable var configuration: ThemeConfiguration
    let theme: LoadedTheme?

    /// The base accent color to apply offsets to
    private var baseAccent: AccentColor {
        theme?.manifest.accent ?? AccentColor(hue: 23, saturation: 0.75, brightness: 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Top segments offset
            VStack(alignment: .leading, spacing: 4) {
                Text("Top Segments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HSBOffsetPicker(
                    hueOffset: $configuration.lcdMinOffset.hue,
                    saturationOffset: $configuration.lcdMinOffset.saturation,
                    brightnessOffset: $configuration.lcdMinOffset.brightness,
                    baseHue: baseAccent.hue,
                    baseSaturation: baseAccent.saturation,
                    baseBrightness: baseAccent.brightness
                )
            }

            // Bottom segments offset
            VStack(alignment: .leading, spacing: 4) {
                Text("Bottom Segments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HSBOffsetPicker(
                    hueOffset: $configuration.lcdMaxOffset.hue,
                    saturationOffset: $configuration.lcdMaxOffset.saturation,
                    brightnessOffset: $configuration.lcdMaxOffset.brightness,
                    baseHue: baseAccent.hue,
                    baseSaturation: baseAccent.saturation,
                    baseBrightness: baseAccent.brightness
                )
            }

            let hasCustomValues =
                configuration.lcdMinOffset != ThemeConfiguration.defaultLCDMinOffset ||
                configuration.lcdMaxOffset != ThemeConfiguration.defaultLCDMaxOffset

            if hasCustomValues {
                Button("Reset to Default") {
                    configuration.lcdMinOffset = ThemeConfiguration.defaultLCDMinOffset
                    configuration.lcdMaxOffset = ThemeConfiguration.defaultLCDMaxOffset
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

/// Controls for debugging shader performance (LOD, scale, FPS overrides).
private struct PerformanceControls: View {
    private let qualityController = AdaptiveQualityController.shared

    private var lodBinding: Binding<Float> {
        Binding(
            get: { qualityController.debugLODOverride ?? qualityController.currentLOD },
            set: { qualityController.debugLODOverride = $0 }
        )
    }

    private var scaleBinding: Binding<Float> {
        Binding(
            get: { qualityController.debugScaleOverride ?? qualityController.currentScale },
            set: { qualityController.debugScaleOverride = $0 }
        )
    }

    private var wallpaperFPSBinding: Binding<Float> {
        Binding(
            get: { qualityController.debugWallpaperFPSOverride ?? qualityController.currentWallpaperFPS },
            set: { qualityController.debugWallpaperFPSOverride = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Low Power Mode warning
            if qualityController.isLowPowerMode {
                HStack {
                    Image(systemName: "bolt.slash.fill")
                        .foregroundStyle(.yellow)
                    Text("Low Power Mode Active")
                        .font(.caption.bold())
                        .foregroundStyle(.yellow)
                }
                Text("Throttling locked to save battery. Disable Low Power Mode to adjust.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Current thermal state display
            HStack {
                Text("Thermal:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(thermalStateLabel)
                    .font(.caption)
                    .foregroundStyle(thermalStateColor)
                Spacer()
                Text("Momentum: \(qualityController.currentMomentum, format: .number.precision(.fractionLength(2)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Interpolation status
            HStack {
                Text("Interpolation:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if qualityController.interpolationEnabled {
                    Text("ON")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("(\(Int(qualityController.shaderFPS)) fps shader → \(Int(qualityController.currentWallpaperFPS)) fps display)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("OFF")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // LOD slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("LOD: \(lodBinding.wrappedValue, format: .number.precision(.fractionLength(2)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if qualityController.debugLODOverride != nil {
                        Text("(override)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Slider(value: lodBinding, in: Float(AdaptiveProfile.lodRange.lowerBound)...Float(AdaptiveProfile.lodRange.upperBound))
            }

            // Scale slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Scale: \(scaleBinding.wrappedValue, format: .number.precision(.fractionLength(2)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if qualityController.debugScaleOverride != nil {
                        Text("(override)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Slider(value: scaleBinding, in: Float(AdaptiveProfile.scaleRange.lowerBound)...Float(AdaptiveProfile.scaleRange.upperBound))
            }

            // Wallpaper FPS slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Wallpaper FPS: \(Int(wallpaperFPSBinding.wrappedValue))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if qualityController.debugWallpaperFPSOverride != nil {
                        Text("(override)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Slider(value: wallpaperFPSBinding, in: Float(AdaptiveProfile.wallpaperFPSRange.lowerBound)...Float(AdaptiveProfile.wallpaperFPSRange.upperBound), step: 1)
            }

            // Reset buttons
            let hasOverrides =
                qualityController.debugLODOverride != nil ||
                qualityController.debugScaleOverride != nil ||
                qualityController.debugWallpaperFPSOverride != nil

            if hasOverrides {
                Button("Clear Overrides") {
                    qualityController.debugLODOverride = nil
                    qualityController.debugScaleOverride = nil
                    qualityController.debugWallpaperFPSOverride = nil
                }
                .font(.caption)
            }

            Divider()

            // Reset learned profile button
            Button("Reset Learned Profile") {
                qualityController.resetCurrentProfile()
            }
            .font(.caption)
            .foregroundStyle(.red)
            .disabled(qualityController.isLowPowerMode)

            Text(qualityController.isLowPowerMode
                 ? "Disabled while Low Power Mode is active"
                 : "Removes persisted throttling values and resets to max quality")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var thermalStateLabel: String {
        switch qualityController.rawThermalState {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    private var thermalStateColor: Color {
        switch qualityController.rawThermalState {
        case .nominal: .green
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        @unknown default: .gray
        }
    }
}

/// Controls for adjusting the playback button blend mode.
private struct PlaybackButtonControls: View {
    @Bindable var configuration: ThemeConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Blend Mode", selection: $configuration.playbackBlendMode) {
                ForEach(PlaybackBlendMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Text("Changes the blend mode applied to the play/pause button.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
