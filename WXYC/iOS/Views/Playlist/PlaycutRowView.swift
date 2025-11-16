//
//  PlaycutRowView.swift
//  WXYC
//
//  SwiftUI view for Playcut playlist entries
//

import SwiftUI
import Core
import UIKit

struct PlaycutRowView: View {
    let playcut: Playcut
    @State private var artwork: UIImage?
    @State private var isLoadingArtwork = true
    @State private var showingShareSheet = false

    private let artworkService = MultisourceArtworkService()

    var body: some View {
        ZStack {
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
                    } else {
                        RoundedRectangle(cornerRadius: 6.0, style: .circular)
                            .opacity(0.25)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(12.0)
                .frame(width: 120, height: 120)
                

                // Song info
                VStack(alignment: .leading) {
                    Text(playcut.songTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text(playcut.artistName)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .compositingGroup()  // Enable knockout effect
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
    ZStack {
        Image("background")
            .resizable()
            .ignoresSafeArea()
        
        VStack(spacing: 12) {
            PlayerHeaderView()

            PlaycutRowView(
                playcut: Playcut(
                    id: 0,
                    hour: 0,
                    chronOrderID: 0,
                    songTitle: "VI Scose Poise",
                    labelName: "Warp",
                    artistName: "Autechre",
                    releaseTitle: "Confield"
                )
            )
            PlaycutRowView(
                playcut: Playcut(
                    id: 0,
                    hour: 0,
                    chronOrderID: 0,
                    songTitle: "VI Scose Poise",
                    labelName: "Warp",
                    artistName: "Autechre",
                    releaseTitle: "Confield"
                )
            )
        }
    }
    .environment(\.radioPlayerController, RadioPlayerController.shared)
}
