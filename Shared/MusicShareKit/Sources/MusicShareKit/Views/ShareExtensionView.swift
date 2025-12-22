//
//  ShareExtensionView.swift
//  MusicShareKit
//
//  Created by Jake Bromberg on 11/24/25.
//

#if canImport(UIKit)
import SwiftUI
import UIKit
import WXUI
import Logger

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
    
    @Environment(\.colorScheme) var colorScheme
    
    public var body: some View {
        ZStack {
            Rectangle()
                .fill(
                    WXYCBackground()
                        .secondary
                )
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
        .requestSentHUD(isPresented: $viewModel.showRequestSentHUD)
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
            .wxycShareStyle(weight: .regular)
            .foregroundStyle(cancelButtonForegroundStyle)
            
            Button("Request") {
                viewModel.submit()
            }
            .font(Font.title3.weight(.bold))
            .frame(minWidth: 0, maxWidth: .infinity)
            .saturation(0.75)
            .padding(.vertical, 10)
            .glassEffectClearIfAvailable()
            .background(requestBackground)
            .clipShape(.capsule)
            .disabled(!viewModel.canSubmit)
        }
        .padding(.horizontal, 16)
    }
    
    var requestBackground: some View {
        Group {
            if colorScheme == .light {
                WXYCMeshAnimation()
                    .opacity(0.4)
                    .blendMode(.plusDarker)
                    .colorInvert()
            } else {
                WXYCMeshAnimation()
                    .opacity(0.95)
                    .blendMode(.multiply)
            }
        }
    }
    
    var cancelButtonForegroundStyle: AnyShapeStyle {
        if colorScheme == .light {
            AnyShapeStyle(Color.pink.opacity(0.75))
        } else {
            AnyShapeStyle(.white)
        }
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
            WXYCLogo()
                .blendMode(.difference)
                .shadow(
                    color: logoShadowColor,
                    radius: 2,
                    y: 2
                )
                .frame(height: 80)

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
        .glassEffectIfAvailable(in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 3, y: 3)
    }
    
    var logoShadowColor: Color {
        switch colorScheme {
        case .light:
            Color(
                hue: 250 / 360,
                saturation: 45 / 100,
                brightness: 100 / 100
            )
        case .dark:
            Color(
                hue: 250 / 360,
                saturation: 75 / 100,
                brightness: 80 / 100
            )
        @unknown default:
            fatalError()
        }
    }
}

extension View {
    func wxycShareStyle(
        weight: Font.Weight
    ) -> some View {
        modifier(
            ButtonModifier(
                weight: weight
            )
        )
    }
}

struct ButtonModifier: ViewModifier {
    let weight: Font.Weight
    
    func body(content: Content) -> some View {
        content
            .frame(minWidth: 0, maxWidth: .infinity)
            .font(Font.title3.weight(weight))
            .saturation(0.75)
            .padding(.vertical, 10)
            .clipShape(.capsule)
            .glassEffectClearIfAvailable()
    }
}

// MARK: - View Model

@Observable
@MainActor
class ShareExtensionViewModel {
    
    enum State {
        case loading
        case error
        case loaded(MusicTrack)
    }
    
    var state: State = .loading
    var artworkImage: UIImage?
    var isLoadingArtwork = false
    var showRequestSentHUD = false

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
    
    init(extensionContext: NSExtensionContext?) {
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
                withAnimation {
                    showRequestSentHUD = true
                }
                // Delay dismissal to show the HUD
                try? await Task.sleep(for: .seconds(1.5))
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
        Log(.info, "extractAndProcessURL started")

        // Configure Spotify credentials
        let config = MusicShareKit.configuration
        await SpotifyService.configure(credentials: SpotifyCredentials(
            clientId: config.spotifyClientId,
            clientSecret: config.spotifyClientSecret
        ))
        Log(.info, "Spotify credentials configured")

        // For URL-based previews, process the stored URL
        if let previewURL = previewURL {
            Log(.info, "Processing preview URL: \(previewURL)")
            await processURL(previewURL)
            return
        }

        // Skip URL extraction for state-based preview mode
        guard !isPreview else {
            Log(.info, "Skipping - isPreview mode")
            return
        }

        guard let extensionContext = extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            Log(.error, "extensionContext or inputItems is nil")
            state = .error
            return
        }
        Log(.info, "Found \(inputItems.count) input items")
        
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
