//
//  ShareExtensionView.swift
//  MusicShareKit
//
//  Created by Jake Bromberg on 11/24/25.
//

#if canImport(UIKit)
import SwiftUI
import UIKit
import RequestService
import Secrets

public struct ShareExtensionView: View {
    @State private var viewModel: ShareExtensionViewModel
    
    public init(extensionContext: NSExtensionContext?) {
        _viewModel = State(initialValue: ShareExtensionViewModel(extensionContext: extensionContext))
    }
    
    /// Preview initializer for testing UI states
    fileprivate init(viewModel: ShareExtensionViewModel) {
        _viewModel = State(initialValue: viewModel)
    }
    
    /// Creates a preview with a pre-configured state
    static func preview(state: ShareExtensionViewModel.State) -> some View {
        ShareExtensionView(viewModel: ShareExtensionViewModel(previewState: state))
    }
    
    /// Creates a preview that loads real data from a URL
    static func preview(url: URL) -> some View {
        ShareExtensionView(viewModel: ShareExtensionViewModel(previewURL: url))
            .frame(maxWidth: .infinity)
    }
    
    public var body: some View {
        ZStack {
            Image("background", bundle: .module)
                .resizable()
                .ignoresSafeArea()
            
            VStack(alignment: .center, spacing: 0) {
                contentView
                
                Spacer()
                
                footerView
                    .safeAreaPadding(.bottom)
            }
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await viewModel.extractAndProcessURL()
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            Button("Cancel") {
                viewModel.cancel()
            }
            .wxycShareStyle(fontColor: .pink, weight: .regular)
            
            Button("Request") {
                viewModel.submit()
            }
            .wxycShareStyle(fontColor: .purple, weight: .bold)
            .disabled(!viewModel.canSubmit)
        }
        .padding(.horizontal, 16)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
        VStack(spacing: 20) {
            logo

            Text("Send a request")
                .font(.title3)
                .fontWeight(.semibold)

            artworkView
            
            VStack {
                // Track info
                if let title = track.title {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                }
                
                if let artist = track.artist {
                    Text(artist)
                        .font(.title2)
                        .multilineTextAlignment(.center)
                }
                
                if let album = track.album,
                   !album.isEmpty {
                    Text(album)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .preferredColorScheme(.light)
    }
    
    @ViewBuilder
    private var artworkView: some View {
        Group {
            if let image = viewModel.artworkImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: 200)
                    .overlay {
                        if viewModel.isLoadingArtwork {
                            ProgressView()
                        }
                    }
            }
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 3, y: 3)
    }
    
    private var logo: some View {
        meshGradient
            .opacity(0.25)
            .clipShape(WXYCLogo())
            .glassEffect(.regular, in: WXYCLogo())
            .shadow(
                color: .orange.opacity(0.5),
                radius: 2,
                y: 3
            )
            .frame(height: 80)
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
    
    // Generate colors once at initialization
    static let gradientColors: [Color] = (0..<16).map { _ in
        palette.randomElement()!
    }
    
    var meshGradient: some View {
        TimelineView(.animation) { context in
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
                colors: Self.gradientColors
            )
        }
    }
}

extension Button {
    func wxycShareStyle(
        fontColor: Color,
        weight: Font.Weight
    ) -> some View {
        modifier(
            ButtonModifier(
                fontColor: fontColor,
                weight: weight
            )
        )
    }
}

struct ButtonModifier: ViewModifier {
    let fontColor: Color
    let weight: Font.Weight
    
    func body(content: Content) -> some View {
        content
            .frame(minWidth: 0, maxWidth: .infinity)
            .font(Font.title3.weight(weight))
            .foregroundStyle(fontColor)
            .saturation(0.75)
            .padding(.vertical, 10)
            .clipShape(.capsule)
            .glassEffect(.regular)
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
    private let isPreview: Bool
    private var previewURL: URL?
    
    var canSubmit: Bool {
        if case .loaded = state {
            return true
        }
        return false
    }
    
    public init(extensionContext: NSExtensionContext?) {
        self.extensionContext = extensionContext
        self.isPreview = false
    }
    
    /// Preview initializer for testing UI states
    fileprivate init(previewState: State) {
        self.extensionContext = nil
        self.state = previewState
        self.isPreview = true
        if case .loaded(let track) = previewState {
            self.musicTrack = track
        }
    }
    
    /// Preview initializer that loads real data from a URL
    fileprivate init(previewURL: URL) {
        self.extensionContext = nil
        self.isPreview = true
        self.previewURL = previewURL
    }
    
    // MARK: - Actions
    
    func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "ShareExtension", code: 0, userInfo: nil))
    }
    
    func submit() {
        guard let track = musicTrack else { return }
        
        Task {
            do {
                try await RequestService.shared.sendRequest(
                    title: track.title ?? track.displayTitle,
                    artist: track.artist ?? "Unknown Artist",
                    album: track.album
                )
                extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            } catch {
                print("Failed to submit request: \(error)")
                // Still complete the extension even on error to avoid hanging
                extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        }
    }
    
    // MARK: - URL Processing
    
    func extractAndProcessURL() async {
        // Configure Spotify credentials
        await SpotifyService.configure(credentials: SpotifyCredentials(
            clientId: Secrets.spotifyClientId,
            clientSecret: Secrets.spotifyClientSecret
        ))
        
        // For URL-based previews, process the stored URL
        if let previewURL = previewURL {
            await processURL(previewURL)
            return
        }
        
        // Skip URL extraction for state-based preview mode
        guard !isPreview else { return }
        
        guard let extensionContext = extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            state = .error
            return
        }
        
        for item in inputItems {
            if let attachments = item.attachments {
                for attachment in attachments {
                    // First try public.url type
                    if attachment.hasItemConformingToTypeIdentifier("public.url") {
                        do {
                            let url = try await loadURL(from: attachment)
                            await processURL(url)
                            return
                        } catch {
                            print("Error loading URL: \(error)")
                        }
                    }
                    
                    // Try public.plain-text type (used by Bandcamp and other apps)
                    if attachment.hasItemConformingToTypeIdentifier("public.plain-text") {
                        do {
                            let text = try await loadText(from: attachment)
                            if let url = extractURL(from: text) {
                                await processURL(url)
                                return
                            }
                        } catch {
                            print("Error loading text: \(error)")
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
    
    private func loadText(from attachment: NSItemProvider) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            attachment.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                if let text = data as? String {
                    continuation.resume(returning: text)
                } else if let data = data as? Data, let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: NSError(domain: "ShareExtension", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid text"]))
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
        guard var track = serviceRegistry.parse(url: url) else {
            state = .error
            return
        }
        
        // Fetch full metadata (title, artist, artwork) before displaying
        if let service = serviceRegistry.identifyService(for: url) {
            do {
                track = try await service.fetchMetadata(for: track)
            } catch {
                print("Failed to fetch metadata: \(error)")
            }
        }
        
        self.musicTrack = track
        state = .loaded(track)
        
        // Fetch artwork image if we have an artwork URL
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

#Preview("Apple Music") {
    ShareExtensionView.preview(
        url: URL(string: "https://music.apple.com/us/album/take-a-little-trip/1280170831?i=1280171884")!
    )
}

#Preview("Spotify") {
    ShareExtensionView.preview(
        url: URL(string: "https://open.spotify.com/track/5ghb02xEjrv3ZSrURC6O57?si=1d8bb9822f3a4f28")!
    )
}

#Preview("Bandcamp") {
    ShareExtensionView.preview(
        url: URL(string: "https://patrickcowley.bandcamp.com/album/afternooners")!
    )
}

#Preview("YouTube") {
    ShareExtensionView.preview(
        url: URL(string: "https://www.youtube.com/watch?v=7SKorvPNRDI")!
    )
}

#Preview("SoundCloud") {
    ShareExtensionView.preview(
        url: URL(string: "https://soundcloud.com/darkentriesrecords/patrick-cowley-surfside-sex")!
    )
}

#Preview("Loading") {
    ShareExtensionView.preview(state: .loading)
}

#Preview("Error") {
    ShareExtensionView.preview(state: .error)
}

#endif
