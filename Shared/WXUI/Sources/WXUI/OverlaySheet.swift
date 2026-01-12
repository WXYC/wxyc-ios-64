//
//  OverlaySheet.swift
//  WXUI
//
//  Created by Jake Bromberg on 12/31/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

// MARK: - Environment Keys for Scroll State

private struct ScrolledToTopKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(true)
}

private struct ScrollIdleKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(true)
}

private struct SheetDraggingKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct LightboxActiveKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var scrolledToTopBinding: Binding<Bool> {
        get { self[ScrolledToTopKey.self] }
        set { self[ScrolledToTopKey.self] = newValue }
    }

    var scrollIdleBinding: Binding<Bool> {
        get { self[ScrollIdleKey.self] }
        set { self[ScrollIdleKey.self] = newValue }
    }

    public var overlaySheetDragging: Bool {
        get { self[SheetDraggingKey.self] }
        set { self[SheetDraggingKey.self] = newValue }
    }

    var lightboxActiveBinding: Binding<Bool> {
        get { self[LightboxActiveKey.self] }
        set { self[LightboxActiveKey.self] = newValue }
    }
}

// MARK: - Scroll Offset Tracking

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

public struct OverlaySheet<Content: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> Content

    @State private var offsetY: CGFloat = 0
    @State private var appeared = false
    @State private var scrolledToTop = true
    @State private var scrollIdle = true
    @State private var isDragging = false
    @State private var lightboxActive = false

    private let dismissThreshold: CGFloat = 150
    private let springAnimation = Animation.spring(response: 0.4, dampingFraction: 0.85)

    public init(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isPresented = isPresented
        self.content = content
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Dimming backdrop
                Color.black
                    .opacity(appeared ? 0.3 : 0)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismiss()
                    }

                content()
                    .environment(\.scrolledToTopBinding, $scrolledToTop)
                    .environment(\.scrollIdleBinding, $scrollIdle)
                    .environment(\.overlaySheetDragging, isDragging)
                    .environment(\.lightboxActiveBinding, $lightboxActive)
                    .frame(maxWidth: .infinity)
                    .frame(height: geometry.size.height * 0.9)
                    .background(.ultraThinMaterial)
                    .clipShape(.rect(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 20, y: -5)
                    .offset(y: appeared ? max(offsetY, 0) : geometry.size.height)
                    #if !os(tvOS)
                    .simultaneousGesture(dragGesture)
                    #endif
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(springAnimation) {
                appeared = true
            }
        }
    }

    #if !os(tvOS)
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { gesture in
                // Don't handle drag when a lightbox or similar overlay is active
                guard !lightboxActive else { return }

                // Only allow dragging down to dismiss when scrolled to top and scroll is idle
                if scrolledToTop && scrollIdle && gesture.translation.height > 0 {
                    isDragging = true
                    offsetY = gesture.translation.height
                } else if isDragging {
                    // Continue drag if we started it
                    offsetY = max(gesture.translation.height, 0)
                }
            }
            .onEnded { gesture in
                guard isDragging else { return }
                isDragging = false

                let velocity = gesture.predictedEndTranslation.height - gesture.translation.height

                if offsetY > dismissThreshold || velocity > 500 {
                    dismiss()
                } else {
                    withAnimation(springAnimation) {
                        offsetY = 0
                    }
                }
            }
    }
    #endif

    private func dismiss() {
        withAnimation(springAnimation) {
            appeared = false
            offsetY = 0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            isPresented = false
        }
    }
}

// MARK: - View Extension

extension View {
    public func overlaySheet<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ZStack {
            self

            if isPresented.wrappedValue {
                OverlaySheet(isPresented: isPresented, content: content)
                    .transition(.identity)
            }
        }
    }
}

// MARK: - Scroll Tracking Modifier

/// A view modifier that tracks scroll position and phase, reporting to the parent OverlaySheet
private struct OverlaySheetScrollTracker: ViewModifier {
    @Environment(\.scrolledToTopBinding) private var scrolledToTop
    @Environment(\.scrollIdleBinding) private var scrollIdle
    @Environment(\.overlaySheetDragging) private var sheetDragging

    func body(content: Content) -> some View {
        content
            .scrollDisabled(sheetDragging)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                let isAtTop = newValue <= 0
                if scrolledToTop.wrappedValue != isAtTop {
                    scrolledToTop.wrappedValue = isAtTop
                }
            }
            .onScrollPhaseChange { _, newPhase in
                let isIdle = newPhase == .idle
                if scrollIdle.wrappedValue != isIdle {
                    scrollIdle.wrappedValue = isIdle
                }
            }
    }
}

extension View {
    /// Apply this modifier to a ScrollView inside an OverlaySheet to enable
    /// drag-to-dismiss only when scrolled to the top.
    public func overlaySheetScrollTracking() -> some View {
        modifier(OverlaySheetScrollTracker())
    }

    /// Signals to the parent OverlaySheet that a lightbox or similar full-screen
    /// overlay is active, preventing the sheet's drag-to-dismiss gesture.
    public func overlaySheetLightboxActive(_ isActive: Bool) -> some View {
        modifier(OverlaySheetLightboxModifier(isActive: isActive))
    }
}

// MARK: - Lightbox Active Modifier

private struct OverlaySheetLightboxModifier: ViewModifier {
    let isActive: Bool
    @Environment(\.lightboxActiveBinding) private var lightboxActiveBinding

    func body(content: Content) -> some View {
        content
            .onChange(of: isActive) { _, newValue in
                lightboxActiveBinding.wrappedValue = newValue
            }
            .onAppear {
                lightboxActiveBinding.wrappedValue = isActive
            }
            .onDisappear {
                lightboxActiveBinding.wrappedValue = false
            }
    }
}
