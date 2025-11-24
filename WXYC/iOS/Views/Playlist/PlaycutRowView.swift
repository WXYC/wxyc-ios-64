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
    private let shadowOffsetAtTop: CGFloat = -2
    private let shadowOffsetAtBottom: CGFloat = 2

    private let artworkService = MultisourceArtworkService()

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
                                Image(uiImage: artwork)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: 6.0,
                                            style: .circular
                                        )
                                    )
                                    .glassEffect(
                                        .clear,
                                        in: RoundedRectangle(cornerRadius: 6.0, style: .circular)
                                    )
                                    .shadow(radius: 3, x: 0, y: shadowYOffset)
                            } else if isLoadingArtwork {
                                RoundedRectangle(cornerRadius: 6.0, style: .circular)
                                    .glassEffect(
                                        .clear.tint(.indigo).interactive(),
                                        in: RoundedRectangle(
                                            cornerRadius: 6.0,
                                            style: .circular
                                        )
                                    )
                                    .preferredColorScheme(.light)
                                    .opacity(0.1625)
                                    .glassEffect(
                                        .clear,
                                        in: RoundedRectangle(cornerRadius: 6.0, style: .circular)
                                    )
                                    .shadow(radius: 3, x: 0, y: shadowYOffset)
                            } else {
                                ZStack(alignment: .center) {
                                    RoundedRectangle(cornerRadius: 6.0, style: .circular)
                                        .frame(
                                            maxWidth: proxy.size.height * 0.75,
                                            maxHeight: proxy.size.height * 0.75
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
                                            in: RoundedRectangle(
                                                cornerRadius: 6.0,
                                                style: .circular
                                            )
                                        )
                                        .preferredColorScheme(.light)
                                        .opacity(0.65)
                                        .clipShape(
                                            RoundedRectangle(cornerRadius: 6.0, style: .circular)
                                        )
                                        .shadow(radius: 2, x: 0, y: shadowYOffset)
                                        
                                    WXYCLogo()
                                        .glassEffect(.clear, in: WXYCLogo())
                                        .preferredColorScheme(.light)
                                        .background(meshGradientAnimation.opacity(0.6))
                                        .clipShape(WXYCLogo())
                                        .shadow(radius: 2, x: 0, y: shadowYOffset)
                                }
                                .backgroundStyle(.clear)
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
                    let _ = print("🔍 Frame debug - local: \(localFrame), scroll: \(scrollFrame)")
                    
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
                
                // Debug: print the raw scroll position to understand what values we're getting
                print("📍 Row \(playcut.songTitle): scrollPosition = \(scrollPosition)")
                
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
                
                print("   → normalizedPosition = \(normalizedPosition), shadowYOffset = \(shadowYOffset)")
            }
            .task {
                await loadArtwork()
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(playcut: playcut, artwork: artwork)
            }
    }

    private func loadArtwork() async {
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
        .background(
            Image("background")
                .resizable()
                .ignoresSafeArea()
        )
}
