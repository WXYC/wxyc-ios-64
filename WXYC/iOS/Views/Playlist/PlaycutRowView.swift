//
//  PlaycutRowView.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/13/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Core
import UIKit
import WXUI

// MARK: - Artwork View Components

/// Common styling for artwork views
private struct ArtworkStyle {
    static let cornerRadius: CGFloat = 6.0
    static let roundedRectangle = RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
}

/// View modifier for common artwork styling
private struct ArtworkShadowModifier: ViewModifier {
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat
    
    func body(content: Content) -> some View {
        content
            .glassEffectClearIfAvailable(in: ArtworkStyle.roundedRectangle)
            .shadow(radius: shadowRadius, x: 0, y: shadowYOffset)
    }
}

extension View {
    fileprivate func artworkShadow(radius: CGFloat, yOffset: CGFloat) -> some View {
        modifier(ArtworkShadowModifier(shadowRadius: radius, shadowYOffset: yOffset))
    }
}

/// Displays loaded artwork image
struct LoadedArtworkView: View {
    let artwork: UIImage
    let shadowYOffset: CGFloat
    
    var body: some View {
        Image(uiImage: artwork)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(ArtworkStyle.roundedRectangle)
            .artworkShadow(radius: 3, yOffset: shadowYOffset)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// Loading placeholder for artwork
struct LoadingArtworkView: View {
    let shadowYOffset: CGFloat
    
    var body: some View {
        ArtworkStyle.roundedRectangle
            .glassEffectClearTintedInteractiveIfAvailable(
                tint: .indigo,
                in: ArtworkStyle.roundedRectangle
            )
            .opacity(0.1625)
            .artworkShadow(radius: 3, yOffset: shadowYOffset)
    }
}


// Preference key to track scroll position
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct PlaycutRowView: View {
    let playcut: Playcut
    @State private var artwork: UIImage?
    @State private var isLoadingArtwork = true
    @State private var showingShareSheet = false
    @State private var showingDetailSheet = false
    @State private var timeOffset: Int = (-10..<10).randomElement()!
    @State private var colors = Self.randomColors()
    @State private var shadowYOffset: CGFloat = 0
    
    // Shadow offset configuration
    private let shadowOffsetAtTop: CGFloat = -3
    private let shadowOffsetAtBottom: CGFloat = 3

    @Environment(\.artworkService) private var artworkService

    private var meshGradientAnimation: TimelineView<AnimationTimelineSchedule, MeshGradient> {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSince1970 + TimeInterval(timeOffset)
            let offsetX = Float(sin(time)) * 0.25
            let offsetY = Float(cos(time)) * 0.25
            
            MeshGradient(
                width: 4,
                height: 4,
                points: [
                    [0.0, 0.0],
                    [0.3, 0.0],
                    [0.7, 0.0],
                    [1.0, 0.0],
                    [0.0, 0.3],
                    [0.2 + offsetX, 0.4 + offsetY],
                    [0.7 + offsetX, 0.2 + offsetY],
                    [1.0, 0.3],
                    [0.0, 0.7],
                    [0.3 + offsetX, 0.8],
                    [0.7 + offsetX, 0.6],
                    [1.0, 0.7],
                    [0.0, 1.0],
                    [0.3, 1.0],
                    [0.7, 1.0],
                    [1.0, 1.0]
                ],
                colors: colors
            )
        }
    }
    
    static func randomColors() -> [Color] {
        (0..<16).map { _ in palette.randomElement()! }
    }
    
    static let palette: [Color] = [
        .indigo,
        .orange,
        .pink,
        .purple,
        .yellow,
        .blue,
        .green,
    ]
    
    var body: some View {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    // Background layer
                    BackgroundLayer()
                    
                    // Content that can punch through the background
                    HStack(spacing: 0) {
                        // Artwork
                        Group {
                            if let artwork = artwork {
                                LoadedArtworkView(
                                    artwork: artwork,
                                    shadowYOffset: shadowYOffset
                                )
                            } else if isLoadingArtwork {
                                LoadingArtworkView(shadowYOffset: shadowYOffset)
                            } else {
                                PlaceholderArtworkView(
                                    cornerRadius: ArtworkStyle.cornerRadius,
                                    shadowYOffset: shadowYOffset,
                                    meshGradient: meshGradientAnimation
                                )
                                .frame(
                                    maxWidth: proxy.size.height * 0.75,
                                    maxHeight: proxy.size.height * 0.75
                                )
                            }
                        }
                        .padding(12.0)
                        .clipRounded()
                        .frame(maxWidth: proxy.size.width / 2.5, alignment: .leading)
                        
                        // Song info
                        VStack(alignment: .leading) {
                            Text(playcut.songTitle)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                            Text(playcut.artistName)
                                .foregroundStyle(.white)
                        }
                        .padding(0)
                        
                        Spacer()
                        
                        // Info button
                        Button {
                            showingDetailSheet = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(width: 44, height: 44)
                        }
                        .padding(.trailing, 4)
                    }
                }
            }
            .aspectRatio(2.5, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .overlay(
                GeometryReader { scrollProxy in
                    let scrollFrame = scrollProxy.frame(in: .named("scroll"))
                    let localFrame = scrollProxy.frame(in: .local)
                    
                    return Color.clear
                        .preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: scrollFrame.midY
                        )
                }
            )
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { scrollPosition in
                // Calculate shadow offset based on scroll position
                // scrollPosition is the midY of the row in the scroll view's coordinate space
                
                // Get screen bounds to understand visible area
                let screenHeight = UIScreen.main.bounds.height
                
                // The scrollPosition tells us where the row's midY is relative to the scroll content
                // When the row is at the top of the visible screen, scrollPosition ≈ 0
                // When the row is at the bottom of the visible screen, scrollPosition ≈ screenHeight
                
                // Normalize position: 0 at top of screen, 1 at bottom of screen
                let normalizedPosition = min(max(scrollPosition / screenHeight, 0), 1)
                
                // Interpolate from shadowOffsetAtTop (top) to shadowOffsetAtBottom (bottom)
                let range = shadowOffsetAtBottom - shadowOffsetAtTop
                shadowYOffset = shadowOffsetAtTop + (normalizedPosition * range)
            }
            .task {
                await loadArtwork()
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(playcut: playcut, artwork: artwork)
            }
            .sheet(isPresented: $showingDetailSheet) {
                PlaycutDetailView(playcut: playcut, artwork: artwork)
            }
    }

    private func loadArtwork() async {
        guard let artworkService = artworkService else {
            await MainActor.run {
                isLoadingArtwork = false
            }
            return
        }
        
        do {
            let fetchedImage = try await artworkService.fetchArtwork(for: playcut)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.artwork = fetchedImage
                    self.isLoadingArtwork = false
                }
            }
        } catch {
            await MainActor.run {
                isLoadingArtwork = false
            }
        }
    }
}

extension View {
    nonisolated public func clipRounded() -> some View {
        clipShape(Self.rectShape)
    }

    static nonisolated var rectShape: some Shape {
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            AnyShape(ConcentricRectangle.rect(corners: .concentric))
        } else {
            AnyShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

extension Shape {
    static var rectShape: some Shape {
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            AnyShape(ConcentricRectangle.rect(corners: .concentric))
        } else {
            AnyShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let playcut: Playcut
    let artwork: UIImage?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activity = PlaycutActivityItem(playcut: playcut)

        if let artwork = artwork {
            activity.image = artwork
        } else {
            activity.image = UIImage(named: "logo.pdf")
        }

        let items: [Any] = [
            activity.image ?? UIImage.logoImage,
            activity.activityTitle ?? "WXYC 89.3 FM",
            URL(string: "http://wxyc.org")!
        ]

        let activityViewController = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )

        return activityViewController
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

#Preview {
    PlaylistView()
        .environment(\.playlistService, PlaylistService())
        .environment(\.artworkService, MultisourceArtworkService())
        .background(WXYCBackground())
}
