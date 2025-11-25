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
            .glassEffect(.clear, in: ArtworkStyle.roundedRectangle)
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
    }
}

/// Loading placeholder for artwork
struct LoadingArtworkView: View {
    let shadowYOffset: CGFloat
    
    var body: some View {
        ArtworkStyle.roundedRectangle
            .glassEffect(
                .clear.tint(.indigo).interactive(),
                in: ArtworkStyle.roundedRectangle
            )
            .preferredColorScheme(.light)
            .opacity(0.1625)
            .artworkShadow(radius: 3, yOffset: shadowYOffset)
    }
}

/// Placeholder view with WXYC logo and animated gradient
struct PlaceholderArtworkView: View {
    let proxyHeight: CGFloat
    let shadowYOffset: CGFloat
    let meshGradient: TimelineView<AnimationTimelineSchedule, MeshGradient>
    
    var body: some View {
        ZStack(alignment: .center) {
            ArtworkStyle.roundedRectangle
                .frame(
                    maxWidth: proxyHeight * 0.75,
                    maxHeight: proxyHeight * 0.75
                )
                .glassEffect(
                    .clear
                        .tint(
                            Color(
                                hue: 248 / 360,
                                saturation: 100 / 100,
                                brightness: 100 / 100,
                                opacity: 0.125
                            )
                        )
                        .interactive(),
                    in: ArtworkStyle.roundedRectangle
                )
                .preferredColorScheme(.light)
                .opacity(0.65)
                .clipShape(ArtworkStyle.roundedRectangle)
                .shadow(radius: 2, x: 0, y: shadowYOffset)
                
            WXYCLogo()
                .glassEffect(.clear, in: WXYCLogo())
                .preferredColorScheme(.light)
                .background(meshGradient.opacity(0.6))
                .clipShape(WXYCLogo())
                .shadow(radius: 2, x: 0, y: shadowYOffset)
        }
        .backgroundStyle(.clear)
    }
}

#Preview("PlaceholderArtworkView") {
    let colors: [Color] = [
        .indigo, .orange, .pink, .purple,
        .yellow, .blue, .green, .indigo,
        .pink, .purple, .yellow, .blue,
        .green, .indigo, .orange, .pink
    ]
    
    let meshGradient = TimelineView(.animation) { context in
        let time = context.date.timeIntervalSince1970
        let offsetX = Float(sin(time)) * 0.25
        let offsetY = Float(cos(time)) * 0.25
        
        MeshGradient(
            width: 4,
            height: 4,
            points: [
                [0.0, 0.0], [0.3, 0.0], [0.7, 0.0], [1.0, 0.0],
                [0.0, 0.3], [0.2 + offsetX, 0.4 + offsetY], [0.7 + offsetX, 0.2 + offsetY], [1.0, 0.3],
                [0.0, 0.7], [0.3 + offsetX, 0.8], [0.7 + offsetX, 0.6], [1.0, 0.7],
                [0.0, 1.0], [0.3, 1.0], [0.7, 1.0], [1.0, 1.0]
            ],
            colors: colors
        )
    }
    
    PlaceholderArtworkView(
        proxyHeight: 150,
        shadowYOffset: 0,
        meshGradient: meshGradient
    )
    .frame(width: 150, height: 150)
    .padding()
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
                                    proxyHeight: proxy.size.height,
                                    shadowYOffset: shadowYOffset,
                                    meshGradient: meshGradientAnimation
                                )
                            }
                        }
                        .padding(12.0)
                        .clipShape(.rect(corners: .concentric))
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
                        .padding(.trailing, 12.0)
                        
                        //            // Share button
                        //            Button(action: {
                        //                showingShareSheet = true
                        //            }) {
                        //                Image(systemName: "ellipsis")
                        //                    .font(.title3)
                        //                    .foregroundStyle(.white)
                        //                    .frame(width: 44, height: 44)
                        //            }
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
        .environment(\.radioPlayerController, RadioPlayerController.shared)
        .environment(\.playlistService, PlaylistService())
        .environment(\.artworkService, MultisourceArtworkService())
        .background(
            Image("background")
                .resizable()
                .ignoresSafeArea()
        )
}
