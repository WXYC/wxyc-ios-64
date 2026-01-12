//
//  ArtworkLightboxView.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

struct ArtworkLightboxView: View {
    let image: UIImage
    let namespace: Namespace.ID
    let geometryID: String
    let isActive: Bool
    let cornerRadius: CGFloat
    let onDismiss: () -> Void
    
    @State private var scale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var accumulatedOffset: CGSize = .zero
    @State private var backgroundOpacity: CGFloat = 0
    
    private var effectiveScale: CGFloat { scale * gestureScale }
    @State private var animatedCornerRadius: CGFloat = 12
    @State private var shadowOpacity: CGFloat = 1
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(backgroundOpacity)
                    .onTapGesture {
                        dismiss()
                    }
                
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: animatedCornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.3 * shadowOpacity), radius: 20 * shadowOpacity, x: 0, y: 10 * shadowOpacity)
                    .matchedGeometryEffect(id: geometryID, in: namespace, isSource: isActive)
                    .scaleEffect(effectiveScale)
                    .offset(offset)
                    .contentShape(Rectangle())
                    .simultaneousGesture(dragGesture)
                    .gesture(magnificationGesture)
                    .onTapGesture(count: 2, perform: toggleZoom)
                    .accessibilityLabel("Dismiss artwork")
                    .accessibilityHint("Swipe down or tap background to close")
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: offset)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: backgroundOpacity)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: animatedCornerRadius)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: shadowOpacity)
        .accessibilityAction(.escape, dismiss)
        .onAppear {
            animatedCornerRadius = cornerRadius
            shadowOpacity = 1
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                backgroundOpacity = 1
                animatedCornerRadius = 0
                shadowOpacity = 0
            }
        }
        .onChange(of: isActive) { _, active in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                backgroundOpacity = active ? 1 : 0
                animatedCornerRadius = active ? 0 : cornerRadius
                shadowOpacity = active ? 0 : 1
            }
        }
        .onDisappear {
            resetState()
        }
    }
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                if effectiveScale > 1.02 {
                    offset = CGSize(
                        width: accumulatedOffset.width + value.translation.width,
                        height: accumulatedOffset.height + value.translation.height
                    )
                } else {
                    offset = value.translation
                    let progress = min(abs(value.translation.height) / 220, 1)
                    backgroundOpacity = 1 - (progress * 0.75)
                }
            }
            .onEnded { value in
                if effectiveScale > 1.02 {
                    accumulatedOffset = offset
                } else {
                    let shouldDismiss = abs(value.translation.height) > 140
                    if shouldDismiss {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            offset = .zero
                            backgroundOpacity = 1
                        }
                    }
                }
            }
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                gestureScale = value
            }
            .onEnded { _ in
                scale = clamp(effectiveScale, lower: 1, upper: 4)
                gestureScale = 1
                if scale <= 1.02 {
                    resetOffsets()
                }
            }
    }
    
    private func toggleZoom() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if effectiveScale <= 1.02 {
                scale = 2.2
            } else {
                scale = 1
                resetOffsets()
            }
        }
    }
    
    private func dismiss() {
        onDismiss()
    }
    
    private func resetState() {
        scale = 1
        gestureScale = 1
        resetOffsets()
        backgroundOpacity = 0
        shadowOpacity = 1
    }
    
    private func resetOffsets() {
        offset = .zero
        accumulatedOffset = .zero
    }
    
    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
