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
        HStack(spacing: 12) {
            // Artwork
            Group {
                if let artwork = artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image("logo")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(isLoadingArtwork ? 0.5 : 1.0)
                }
            }
            .padding(6.0)
            .frame(width: 120, height: 120)
//            .background(
//                RoundedRectangle(cornerRadius: 6)
//                    .fill(.ultraThinMaterial)
//            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            

            // Song info
            VStack(alignment: .leading) {
                Text(playcut.songTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(playcut.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            

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
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
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
        Color.purple
        
        VStack(spacing: 0) {
            PlayerHeaderView()
                .background(.blue)
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
    .environment(\.radioPlayerController, RadioPlayerController())
}
