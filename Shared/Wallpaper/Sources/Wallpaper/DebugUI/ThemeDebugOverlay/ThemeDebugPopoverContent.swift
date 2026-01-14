//
//  ThemeDebugPopoverContent.swift
//  Wallpaper
//
//  Content for the theme debug popover containing all control sections.
//
//  Created by Jake Bromberg on 12/18/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

#if DEBUG
/// Content for the theme debug popover.
struct ThemeDebugPopoverContent: View {
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

                let theme = configuration.selectedTheme

                // LCD brightness controls
                DisclosureGroup(isExpanded: $isLCDBrightnessExpanded) {
                    LCDBrightnessControls(configuration: configuration)
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
        .presentationBackgroundInteraction(.enabled)
        .presentationBackground {
            Rectangle()
                .fill(.gray)
                .opacity(0.5)
        }
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
#endif
