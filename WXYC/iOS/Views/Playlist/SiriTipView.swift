//
//  SiriTipView.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/3/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        ))
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

#Preview {
    VStack {
        SiriTipView(isVisible: .constant(true)) {
            print("Dismissed")
        }
        .padding()
    }
    .background(WXYCBackground())
}
