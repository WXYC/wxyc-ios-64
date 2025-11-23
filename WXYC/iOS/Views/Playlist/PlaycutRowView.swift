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

struct PlaycutRowView: View {
    let playcut: Playcut
    @State private var artwork: UIImage?
    @State private var isLoadingArtwork = true
    @State private var showingShareSheet = false
    
    private let phi = (1 + sqrt(5)) / 2
    private let size: CGFloat = 120

    private let artworkService = MultisourceArtworkService()

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
                            } else {
                                ZStack(alignment: .center) {
                                    RoundedRectangle(cornerRadius: 6.0, style: .circular)
                                        .frame(
                                            maxWidth: proxy.size.height * 0.8,
                                            maxHeight: proxy.size.height * 0.8
                                        )
                                        .glassEffect(
                                            .clear.tint(.indigo).interactive(),
                                            in: RoundedRectangle(
                                                cornerRadius: 6.0,
                                                style: .circular
                                            )
                                        )
                                        .preferredColorScheme(.light)
                                        .opacity(0.1625)

                                    WXYCLogo()
                                        .glassEffect(.regular, in: WXYCLogo())
                                        .preferredColorScheme(.light)
                                }
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
