//
//  PlaycutDetailSections.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Core
import WXUI

// MARK: - Header Section

struct PlaycutHeaderSection: View {
    let playcut: Playcut
    let artwork: UIImage?
    @Binding var isShowingLightbox: Bool
    let artworkNamespace: Namespace.ID
    let artworkGeometryID: String
    
    var body: some View {
        VStack {
            // Artwork
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    isShowingLightbox = true
                }
            } label: {
                if let artwork = artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(12)
                        .padding(.bottom, 16)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    PlaceholderArtworkView(
                        cornerRadius: 12,
                        shadowYOffset: 3
                    )
                    .aspectRatio(contentMode: .fit)
                }
            }
            .frame(maxWidth: 280, maxHeight: 280)
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("Expand artwork")
            .accessibilityHint("Tap to view full-screen")
            .accessibilityAddTraits(.isButton)
            .matchedGeometryEffect(id: artworkGeometryID, in: artworkNamespace)
            .shadow(radius: 20, x: 0, y: 10)
            
            // Song info
            VStack {
                Text(playcut.songTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                
                Text(playcut.artistName)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                
                if let releaseTitle = playcut.releaseTitle {
                    Text(releaseTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(.white)
            .padding(.bottom)
        }
    }
}

// MARK: - Artwork Lightbox

struct ArtworkLightboxView: View {
    let image: UIImage
    let namespace: Namespace.ID
    let geometryID: String
    let onDismiss: () -> Void
    
    @State private var scale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var accumulatedOffset: CGSize = .zero
    @State private var backgroundOpacity: CGFloat = 1
    
    private var effectiveScale: CGFloat { scale * gestureScale }
    
    var body: some View {
        ZStack {
            Rectangle()
                .ignoresSafeArea()
                .foregroundStyle(            Material.ultraThinMaterial.opacity(backgroundOpacity))
                .onTapGesture {
                    dismiss()
                }
            
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .matchedGeometryEffect(id: geometryID, in: namespace)
                .scaleEffect(effectiveScale)
                .offset(offset)
                .simultaneousGesture(dragGesture)
                .gesture(magnificationGesture)
                .onTapGesture(count: 2, perform: toggleZoom)
                .accessibilityLabel("Dismiss artwork")
                .accessibilityHint("Swipe down or tap background to close")
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: offset)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: backgroundOpacity)
        .accessibilityAction(.escape, dismiss)
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
        backgroundOpacity = 1
    }
    
    private func resetOffsets() {
        offset = .zero
        accumulatedOffset = .zero
    }
    
    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}

// MARK: - Loading Section

struct PlaycutLoadingSection: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("Loading metadata...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.primary.opacity(0.1))
        )
    }
}

// MARK: - Metadata Section

#Preview {
    @Previewable @State var expandedBio = false
    @Previewable @State var isShowingLightbox = false
    @Namespace var previewNamespace
    
    let metadata = PlaycutMetadata(
        label: "We Release Whatever The Fuck We Want Okay?",
        releaseYear: 2025,
        discogsURL: nil,
        artistBio: nil,
        wikipediaURL: nil,
        spotifyURL: nil,
        appleMusicURL: nil,
        youtubeMusicURL: nil,
        bandcampURL: nil,
        soundcloudURL: nil
    )
    
    PlaycutLoadingSection()
    
    PlaycutHeaderSection(
        playcut: Playcut(
            id: 0,
            hour: 0,
            chronOrderID: 0,
            songTitle: "Pharoah's Dance",
            labelName: "Columbia",
            artistName: "Miles Davis",
            releaseTitle: "Bitches Brew"
        ),
        artwork: nil,
        isShowingLightbox: $isShowingLightbox,
        artworkNamespace: previewNamespace,
        artworkGeometryID: "preview-artwork"
    )
    
    PlaycutMetadataSection(
        metadata: metadata,
        expandedBio: $expandedBio
    )
    
    ExternalLinksSection(metadata: metadata)
}

struct PlaycutMetadataSection: View {
    let metadata: PlaycutMetadata
    @Binding var expandedBio: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
        
            if metadata.label != nil || metadata.releaseYear != nil {
                // Label and Year
                Grid(alignment: .leadingFirstTextBaseline, verticalSpacing: 10) {
                    if let label = metadata.label {
                        GridRow {
                            MetadataLabel(title: "Label")
                            MetadataValue(value: label)
                        }
                    }
                    if let year = metadata.releaseYear {
                        GridRow {
                            MetadataLabel(title: "Year")
                            HStack {
                                MetadataValue(value: String(year))
                                Spacer()
                            }
                        }
                    }
                }
                
                // Artist Bio
                if let bio = metadata.artistBio, !bio.isEmpty {
                    ArtistBioSection(bio: bio, expandedBio: $expandedBio)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.primary.opacity(0.1))
        )
    }
}

// MARK: - Artist Bio Section

struct ArtistBioSection: View {
    let bio: String
    @Binding var expandedBio: Bool
    @State private var isTruncated: Bool = false
    @State private var parsedBio: AttributedString?
    
    private let resolver: DiscogsEntityResolver = DiscogsAPIEntityResolver.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About the Artist")
                .font(.headline.smallCaps())
                .foregroundStyle(.primary)
            
            parsedBioText
                .textSelection(.enabled)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(expandedBio ? nil : 4)
                .background(
                    TruncationDetector(text: parsedBioText, lineLimit: 4, isTruncated: $isTruncated)
                )
            
            if isTruncated {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedBio.toggle()
                    }
                } label: {
                    Text(expandedBio ? "Show Less" : "Read More")
                        .font(.caption.smallCaps())
                        .fontWeight(.bold)
                }
            }
        }
        .task {
            // Parse async with resolver to resolve artist IDs
            parsedBio = await DiscogsFormatter.parseToAttributedString(bio, resolver: resolver)
        }
    }
    
    private var parsedBioText: Text {
        if let parsedBio {
            return Text(parsedBio)
        } else {
            // Show synchronously parsed version while async resolves
            return DiscogsFormatter.parse(bio)
        }
    }
}

// MARK: - Truncation Detection

private struct TruncationDetector: View {
    let text: Text
    let lineLimit: Int
    @Binding var isTruncated: Bool
    
    var body: some View {
        GeometryReader { geometry in
            text
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { fullTextGeometry in
                        Color.clear.onAppear {
                            checkTruncation(fullHeight: fullTextGeometry.size.height, availableWidth: geometry.size.width)
                        }
                        .onChange(of: fullTextGeometry.size) { _ in
                            checkTruncation(fullHeight: fullTextGeometry.size.height, availableWidth: geometry.size.width)
                        }
                    }
                )
                .hidden()
        }
        .hidden()
    }
    
    private func checkTruncation(fullHeight: CGFloat, availableWidth: CGFloat) {
        // Estimate line height based on body font
        let estimatedLineHeight: CGFloat = 20
        let maxCollapsedHeight = CGFloat(lineLimit) * estimatedLineHeight * 1.2 // 1.2 for line spacing
        isTruncated = fullHeight > maxCollapsedHeight
    }
}

// MARK: - Streaming Links Section

struct StreamingLinksSection: View {
    let metadata: PlaycutMetadata
    let isLoading: Bool
    var onServiceTapped: ((StreamingService) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add it to your library")
                .font(.headline.smallCaps())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StreamingButton(
                    service: .spotify,
                    url: metadata.spotifyURL,
                    isLoading: isLoading,
                    onTap: onServiceTapped
                )
                
                StreamingButton(
                    service: .appleMusic,
                    url: metadata.appleMusicURL,
                    isLoading: isLoading,
                    onTap: onServiceTapped
                )
                
                StreamingButton(
                    service: .youtubeMusic,
                    url: metadata.youtubeMusicURL,
                    isLoading: isLoading,
                    onTap: onServiceTapped
                )
                
                StreamingButton(
                    service: .bandcamp,
                    url: metadata.bandcampURL,
                    isLoading: isLoading,
                    onTap: onServiceTapped
                )
                
                StreamingButton(
                    service: .soundcloud,
                    url: metadata.soundcloudURL,
                    isLoading: isLoading,
                    onTap: onServiceTapped
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.primary.opacity(0.1))
        )
    }
}

// MARK: - External Links Section

struct ExternalLinksSection: View {
    let metadata: PlaycutMetadata
    var onLinkTapped: ((String) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More Info")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                if let discogsURL = metadata.discogsURL {
                    ExternalLinkButton(
                        title: "Discogs",
                        imageName: "discogs",
                        url: discogsURL,
                        onTap: onLinkTapped
                    )
                }
                
                if let wikipediaURL = metadata.wikipediaURL {
                    ExternalLinkButton(
                        title: "Wikipedia",
                        imageName: "wikipedia",
                        url: wikipediaURL,
                        onTap: onLinkTapped
                    )
                }
            }
        }
        .tint(.primary)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.primary.opacity(0.1))
        )
    }
}
