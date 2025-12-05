//
//  SiriTipView.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/3/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Core
import WXUI

/// A custom Siri tip view that displays a suggestion to use voice commands.
///
/// Display Logic:
/// - DEBUG: Shows on every launch for testing purposes
/// - RELEASE: Shows after the second launch, until dismissed; never shows again once dismissed
struct SiriTipView: View {
    typealias Dismissal = () -> Void
    
    @Binding var isVisible: Bool
    private let onDismiss: Dismissal
    
    init(isVisible: Binding<Bool>, onDismiss: @escaping Dismissal = { }) {
        self.onDismiss = onDismiss
        self._isVisible = isVisible
    }
    
    
    /// Whether the glow effect is currently active
    @State private var isGlowing = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "siri")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            
            // Tip content
            VStack(alignment: .leading, spacing: 2) {
                Text("Try saying")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                
                Text("\u{201C}Hey Siri, play WXYC\u{201D}")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
            
            Spacer()
            
            // Close button
            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    isVisible = false
                }
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .onTapGesture {
            triggerGlow()
        }
        .task {
            triggerGlow()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .intelligenceBackground(
            in: RoundedRectangle(cornerRadius: 16),
            lineWidths: isGlowing ? [2, 4, 6] : [0, 0, 0],
            blurs: isGlowing ? [5, 6, 12] : [0, 0, 0]
        )
        .intelligenceOverlay(
            in: RoundedRectangle(cornerRadius: 16),
            lineWidths: isGlowing ? [2, 4, 6] : [0, 0, 0],
            blurs: isGlowing ? [5, 6, 12] : [0, 0, 0]
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        ))
    }
    
    /// Triggers the glow effect temporarily
    private func triggerGlow() {
        Task {
            try? await Task.sleep(for: .seconds(1))
            
            withAnimation(.easeIn(duration: 0.3)) {
                isGlowing = true
            }
            
            try? await Task.sleep(for: .seconds(5))
            
            withAnimation(.easeOut(duration: 0.5)) {
                isGlowing = false
            }
        }
    }
}

// MARK: - Persistence

extension SiriTipView {
    private static let hasLaunchedBeforeKey = "siriTip.hasLaunchedBefore"
    private static let wasDismissedKey = "siriTip.wasDismissed"
    
    /// Call this at app launch to record that a launch has occurred.
    /// Returns whether the Siri tip should be shown.
    static func recordLaunchAndShouldShow() -> Bool {
#if DEBUG
        // In debug builds, always show for testing
        return true
#else
        let defaults = UserDefaults.wxyc
        
        // If user already dismissed, never show again
        if defaults.bool(forKey: wasDismissedKey) {
            return false
        }
        
        // Check if this is the first launch
        let hasLaunchedBefore = defaults.bool(forKey: hasLaunchedBeforeKey)
        
        if !hasLaunchedBefore {
            // First launch - record it but don't show the tip
            defaults.set(true, forKey: hasLaunchedBeforeKey)
            return false
        }
        
        // Second launch or later, and not yet dismissed - show the tip
        return true
#endif
    }
    
    /// Call this when the user dismisses the tip to prevent future displays.
    static func recordDismissal() {
        UserDefaults.wxyc.set(true, forKey: wasDismissedKey)
    }
    
    /// Resets the Siri tip state (useful for testing).
    static func resetState() {
        let defaults = UserDefaults.wxyc
        defaults.removeObject(forKey: hasLaunchedBeforeKey)
        defaults.removeObject(forKey: wasDismissedKey)
    }
}

// https://github.com/Livsy90/IntelligenceGlow/tree/main

public extension View {
    /// Applies a glowing angular-gradient stroke as a background using the provided shape.
    @MainActor
    func intelligenceBackground<S: InsettableShape>(
        in shape: S,
        lineWidths: [CGFloat] = [6, 9, 11, 15],
        blurs: [CGFloat] = [0, 4, 12, 15],
        updateInterval: TimeInterval = 0.4,
        animationDurations: [TimeInterval] = [0.5, 0.6, 0.8, 1.0],
        gradientGenerator: @MainActor @Sendable @escaping () -> [Gradient.Stop] = { .intelligenceStyle }
    ) -> some View {
        background(
            shape.intelligenceStroke(
                lineWidths: lineWidths,
                blurs: blurs,
                updateInterval: updateInterval,
                animationDurations: animationDurations,
                gradientGenerator: gradientGenerator
            )
        )
    }
    
    /// Applies a glowing angular-gradient stroke as an overlay using the provided shape.
    @MainActor
    func intelligenceOverlay<S: InsettableShape>(
        in shape: S,
        lineWidths: [CGFloat] = [6, 9, 11, 15],
        blurs: [CGFloat] = [0, 4, 12, 15],
        updateInterval: TimeInterval = 0.4,
        animationDurations: [TimeInterval] = [0.5, 0.6, 0.8, 1.0],
        gradientGenerator: @MainActor @Sendable @escaping () -> [Gradient.Stop] = { .intelligenceStyle }
    ) -> some View {
        overlay(
            shape.intelligenceStroke(
                lineWidths: lineWidths,
                blurs: blurs,
                updateInterval: updateInterval,
                animationDurations: animationDurations,
                gradientGenerator: gradientGenerator
            )
        )
    }
}

public extension InsettableShape {
    /// Applies an Apple Intelligence–style animated angular-gradient glow stroke to any Shape.
    /// - Parameters:
    ///   - lineWidths: Line widths for each glow layer.
    ///   - blurs: Blur radius for each corresponding glow layer.
    ///   - updateInterval: How often to regenerate gradient stops.
    ///   - animationDurations: Animation duration per layer when gradient changes.
    ///   - gradientGenerator: Function that returns a new set of `Gradient.Stop` values.
    /// - Returns: A view that renders the shape with a glowing gradient stroke.
    @MainActor
    func intelligenceStroke(
        lineWidths: [CGFloat] = [6, 9, 11, 15],
        blurs: [CGFloat] = [0, 4, 12, 15],
        updateInterval: TimeInterval = 0.4,
        animationDurations: [TimeInterval] = [0.5, 0.6, 0.8, 1.0],
        gradientGenerator: @MainActor @Sendable @escaping () -> [Gradient.Stop] = { .intelligenceStyle }
    ) -> some View {
        IntelligenceStrokeView(
            shape: self,
            lineWidths: lineWidths,
            blurs: blurs,
            updateInterval: updateInterval,
            animationDurations: animationDurations,
            gradientGenerator: gradientGenerator
        )
        .allowsHitTesting(false)
    }
}

public extension Array where Element == Gradient.Stop {
    static var intelligenceStyle: [Gradient.Stop] {
        [
            Color(red: 188/255, green: 130/255, blue: 243/255),
            Color(red: 245/255, green: 185/255, blue: 234/255),
            Color(red: 141/255, green: 159/255, blue: 255/255),
            Color(red: 255/255, green: 103/255, blue: 120/255),
            Color(red: 255/255, green: 186/255, blue: 113/255),
            Color(red: 198/255, green: 134/255, blue: 255/255)
        ]
            .map {
                Gradient.Stop(color: $0, location: Double.random(in: 0...1))
            }
            .sorted {
                $0.location < $1.location
            }
    }
}

// MARK: - Generic glow stroke for any Shape

private struct IntelligenceStrokeView<S: InsettableShape>: View {
    let shape: S
    let lineWidths: [CGFloat]
    let blurs: [CGFloat]
    let updateInterval: TimeInterval
    let animationDurations: [TimeInterval]
    let gradientGenerator: @MainActor @Sendable () -> [Gradient.Stop]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stops: [Gradient.Stop] = .intelligenceStyle

    var body: some View {
        let layerCount = min(lineWidths.count, blurs.count, animationDurations.count)
        let gradient = AngularGradient(
            gradient: Gradient(stops: stops),
            center: .center
        )

        ZStack {
            ForEach(0..<layerCount, id: \.self) { i in
                shape
                    .strokeBorder(gradient, lineWidth: lineWidths[i])
                    .blur(radius: blurs[i])
                    .animation(
                        reduceMotion ? .linear(duration: 0) : .easeInOut(duration: animationDurations[i]),
                        value: stops
                    )
            }
        }
        .clipShape(shape)
        .task(id: updateInterval) {
            while !Task.isCancelled {
                stops = gradientGenerator()
                if #available(iOS 16.0, *) {
                    try? await Task.sleep(for: .seconds(updateInterval))
                } else {
                    try? await Task.sleep(nanoseconds: UInt64(updateInterval * 1_000_000_000))
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 30) {
        Text("Some text here")
            .padding(22)
            .intelligenceBackground(in: .capsule)
        Text("Some text here")
            .padding(22)
            .intelligenceOverlay(in: .rect(cornerRadius: 22))
    }
}


#Preview {
    ZStack {
        Color.indigo
            .backgroundStyle(WXYCBackground())
        
        VStack {
            SiriTipView(isVisible: .constant(true)) {
                print("Dismissed")
            }
            .padding()
        }
    }
}
