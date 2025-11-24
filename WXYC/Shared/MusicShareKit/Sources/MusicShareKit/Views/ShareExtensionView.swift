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
        return "Share Music"
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

#Preview {
    ShareExtensionView(extensionContext: nil)
}

