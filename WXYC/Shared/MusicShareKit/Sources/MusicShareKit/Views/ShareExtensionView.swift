//
//  ShareExtensionView.swift
//  MusicShareKit
//
//  Created by Jake Bromberg on 11/24/25.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct ShareExtensionView: View {
    @State private var viewModel: ShareExtensionViewModel
    
    public init(extensionContext: NSExtensionContext?) {
        _viewModel = State(initialValue: ShareExtensionViewModel(extensionContext: extensionContext))
    }
    
    public var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.cancel()
                }
            
            // Card container
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Content
                contentView
            }
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .containerRelativeFrame(.horizontal) { width, _ in
                width * 0.85
            }
        }
        .task {
            await viewModel.extractAndProcessURL()
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Button("Cancel") {
                viewModel.cancel()
            }
            
            Spacer()
            
            Text(viewModel.headerTitle)
                .fontWeight(.semibold)
            
            Spacer()
            
            Button("Submit") {
                viewModel.submit()
            }
            .fontWeight(.semibold)
            .disabled(!viewModel.canSubmit)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color(uiColor: .secondarySystemBackground))
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var contentView: some View {
        Group {
            switch viewModel.state {
            case .loading:
                loadingView
            case .error:
                errorView
            case .loaded(let track):
                trackView(track)
            }
        }
        .frame(minHeight: 244)
    }
    
    private var loadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var errorView: some View {
        Text("No music link found")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func trackView(_ track: MusicTrack) -> some View {
        VStack(spacing: 16) {
            // Artwork
            artworkView
            
            // Track info
            Text(track.displayTitle)
                .font(.body)
                .multilineTextAlignment(.center)
            
            // Service badge
            Text("via \(track.service.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
    
    @ViewBuilder
    private var artworkView: some View {
        if let image = viewModel.artworkImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 150, height: 150)
                .overlay {
                    if viewModel.isLoadingArtwork {
                        ProgressView()
                    }
                }
        }
    }
}

// MARK: - View Model

@Observable
@MainActor
public class ShareExtensionViewModel {
    
    public enum State {
        case loading
        case error
        case loaded(MusicTrack)
    }
    
    var state: State = .loading
    var artworkImage: UIImage?
    var isLoadingArtwork = false
    
    private weak var extensionContext: NSExtensionContext?
    private let serviceRegistry = MusicServiceRegistry.shared
    private var musicTrack: MusicTrack?
    
    var headerTitle: String {
        if case .loaded(let track) = state {
            return track.service.displayName
        }
        return "Send A Request"
    }
    
    var canSubmit: Bool {
        if case .loaded = state {
            return true
        }
        return false
    }
    
    public init(extensionContext: NSExtensionContext?) {
        self.extensionContext = extensionContext
    }
    
    // MARK: - Actions
    
    func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "ShareExtension", code: 0, userInfo: nil))
    }
    
    func submit() {
        guard let track = musicTrack else { return }
        
        // TODO: Implement actual submission logic here
        print("Submitting track: \(track.displayTitle)")
        print("Service: \(track.service.displayName)")
        print("URL: \(track.url.absoluteString)")
        
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    // MARK: - URL Processing
    
    func extractAndProcessURL() async {
        guard let extensionContext = extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            state = .error
            return
        }
        
        for item in inputItems {
            if let attachments = item.attachments {
                for attachment in attachments {
                    if attachment.hasItemConformingToTypeIdentifier("public.url") {
                        do {
                            let url = try await loadURL(from: attachment)
                            await processURL(url)
                            return
                        } catch {
                            print("Error loading URL: \(error)")
                        }
                    }
                }
            }
            
            // Check for text content that might contain URLs
            if let text = item.attributedContentText?.string ?? item.attributedTitle?.string,
               let url = extractURL(from: text) {
                await processURL(url)
                return
            }
        }
        
        state = .error
    }
    
    private func loadURL(from attachment: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            attachment.loadItem(forTypeIdentifier: "public.url", options: nil) { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                if let url = data as? URL {
                    continuation.resume(returning: url)
                } else if let urlString = data as? String, let url = URL(string: urlString) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: NSError(domain: "ShareExtension", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
                }
            }
        }
    }
    
    private func extractURL(from text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        
        return matches?.first.flatMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return URL(string: String(text[range]))
        }
    }
    
    private func processURL(_ url: URL) async {
        guard let track = serviceRegistry.parse(url: url) else {
            state = .error
            return
        }
        
        self.musicTrack = track
        state = .loaded(track)
        
        // Fetch artwork
        await fetchArtwork(for: track)
    }
    
    private func fetchArtwork(for track: MusicTrack) async {
        guard let service = serviceRegistry.identifyService(for: track.url) else { return }
        
        isLoadingArtwork = true
        defer { isLoadingArtwork = false }
        
        do {
            if let artworkURL = try await service.fetchArtwork(for: track) {
                let (data, _) = try await URLSession.shared.data(from: artworkURL)
                
                if let image = UIImage(data: data) {
                    self.artworkImage = image
                    self.musicTrack?.artworkURL = artworkURL
                }
            }
        } catch {
            print("Failed to fetch artwork: \(error)")
        }
    }
}

// MARK: - Preview

#Preview("Loading") {
    ShareExtensionPreviewView(state: .loading)
}

#Preview("Error") {
    ShareExtensionPreviewView(state: .error)
}

#Preview("Apple Music") {
    ShareExtensionPreviewView(state: .loaded(MusicTrack(
        service: .appleMusic,
        url: URL(string: "https://music.apple.com/us/album/scraping-past/273128726?i=273128743")!,
        title: "Scraping Past",
        artist: "Atlas Sound",
        album: "Let the Blind Lead Those Who Can See But Cannot Feel",
        identifier: "273128743"
    )))
}

#Preview("Spotify") {
    ShareExtensionPreviewView(state: .loaded(MusicTrack(
        service: .spotify,
        url: URL(string: "https://open.spotify.com/track/4PTG3Z6ehGkBFwjybzWkR8")!,
        title: "Paranoid Android",
        artist: "Radiohead",
        album: "OK Computer",
        identifier: "4PTG3Z6ehGkBFwjybzWkR8"
    )))
}

#Preview("Long Title") {
    ShareExtensionPreviewView(state: .loaded(MusicTrack(
        service: .bandcamp,
        url: URL(string: "https://example.bandcamp.com/track/example")!,
        title: "A Very Long Song Title That Might Need Multiple Lines",
        artist: "An Artist With A Really Long Name",
        album: "An Album With An Extremely Long Title Too",
        identifier: "123"
    )))
}

// MARK: - Preview Helper View

private struct ShareExtensionPreviewView: View {
    let state: ShareExtensionViewModel.State
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") { }
                    
                    Spacer()
                    
                    Text(headerTitle)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button("Submit") { }
                        .fontWeight(.semibold)
                        .disabled(!canSubmit)
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(Color(uiColor: .secondarySystemBackground))
                
                // Content
                Group {
                    switch state {
                    case .loading:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .error:
                        Text("No music link found")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .loaded(let track):
                        VStack(spacing: 16) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(uiColor: .tertiarySystemFill))
                                .frame(width: 150, height: 150)
                                .overlay {
                                    Image(systemName: "music.note")
                                        .font(.largeTitle)
                                        .foregroundStyle(.secondary)
                                }
                            
                            Text(track.displayTitle)
                                .font(.body)
                                .multilineTextAlignment(.center)
                            
                            Text("via \(track.service.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                    }
                }
                .frame(minHeight: 244)
            }
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .containerRelativeFrame(.horizontal) { width, _ in
                width * 0.85
            }
        }
    }
    
    private var headerTitle: String {
        if case .loaded(let track) = state {
            return track.service.displayName
        }
        return "Send A Request"
    }
    
    private var canSubmit: Bool {
        if case .loaded = state {
            return true
        }
        return false
    }
}
