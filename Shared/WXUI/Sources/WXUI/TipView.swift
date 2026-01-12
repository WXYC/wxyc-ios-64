//
//  TipView.swift
//  WXUI
//
//  Created by Jake Bromberg on 1/12/26.
//

import SwiftUI

/// A reusable tip view component with an icon, caption, headline, and dismiss button.
///
/// Use this as the base for contextual tips throughout the app.
public struct TipView<Background: View>: View {
    public typealias Dismissal = () -> Void

    let iconName: String
    let caption: String
    let headline: String
    @Binding var isVisible: Bool
    let onDismiss: Dismissal
    @ViewBuilder let background: () -> Background

    public init(
        iconName: String,
        caption: String,
        headline: String,
        isVisible: Binding<Bool>,
        onDismiss: @escaping Dismissal = { },
        @ViewBuilder background: @escaping () -> Background
    ) {
        self.iconName = iconName
        self.caption = caption
        self.headline = headline
        self._isVisible = isVisible
        self.onDismiss = onDismiss
        self.background = background
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 32))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))

                Text(headline)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    isVisible = false
                }
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background { background() }
        .clipShape(.rect(cornerRadius: 16))
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        ))
    }
}
