import Foundation
import Testing
@testable import MusicShareKit

// MARK: - Test Data

private enum TestURLs {
    static let appleMusic = URL(string: "https://music.apple.com/us/album/take-a-little-trip/1280170831?i=1280171884")!
    static let spotify = URL(string: "https://open.spotify.com/track/5ghb02xEjrv3ZSrURC6O57?si=1d8bb9822f3a4f28")!
    static let bandcamp = URL(string: "https://patrickcowley.bandcamp.com/album/afternooners")!
    static let youtube = URL(string: "https://www.youtube.com/watch?v=7SKorvPNRDI")!
    static let soundcloud = URL(string: "https://soundcloud.com/darkentriesrecords/patrick-cowley-surfside-sex")!
    
    static let all: [URL] = [appleMusic, spotify, bandcamp, youtube, soundcloud]
    
    /// Maps each URL to its owning service
    static func expectedService(for url: URL) -> MusicServiceIdentifier {
        switch url {
        case appleMusic: return .appleMusic
        case spotify: return .spotify
        case bandcamp: return .bandcamp
        case youtube: return .youtubeMusic
        case soundcloud: return .soundcloud
        default: fatalError("Unknown test URL: \(url)")
        }
    }
}

// MARK: - Service Factory

/// Services that have actual implementations (excludes .unknown)
private let testableServices: [MusicServiceIdentifier] = [
    .appleMusic, .spotify, .bandcamp, .youtubeMusic, .soundcloud
]

private func makeService(for identifier: MusicServiceIdentifier) -> any MusicService {
    switch identifier {
    case .appleMusic: return AppleMusicService()
    case .spotify: return SpotifyService()
    case .bandcamp: return BandcampService()
    case .youtubeMusic: return YouTubeMusicService()
    case .soundcloud: return SoundCloudService()
    case .unknown: fatalError("No service implementation for .unknown")
    }
}

// MARK: - Cross-Product URL Handling Tests

@Suite("Music Service URL Handling")
struct MusicServiceURLHandlingTests {
    
    @Test(
        "Service handles URL correctly",
        arguments: testableServices, TestURLs.all
    )
    func serviceHandlesURL(serviceId: MusicServiceIdentifier, url: URL) {
        let service = makeService(for: serviceId)
        let urlOwner = TestURLs.expectedService(for: url)
        let shouldHandle = (serviceId == urlOwner)
        
        #expect(
            service.canHandle(url: url) == shouldHandle,
            "\(serviceId.displayName) should\(shouldHandle ? "" : " not") handle \(urlOwner.displayName) URL"
        )
    }
}

// MARK: - Service-Specific URL Parsing Tests

@Suite("URL Parsing")
struct URLParsingTests {
    
    @Test("Parses service URL and extracts identifier", arguments: [
        (TestURLs.appleMusic, MusicServiceIdentifier.appleMusic, "1280171884"),
        (TestURLs.spotify, .spotify, "track:5ghb02xEjrv3ZSrURC6O57"),
        (TestURLs.bandcamp, .bandcamp, "album:afternooners"),
        (TestURLs.youtube, .youtubeMusic, "7SKorvPNRDI"),
        (TestURLs.soundcloud, .soundcloud, "darkentriesrecords/patrick-cowley-surfside-sex"),
    ])
    func parsesURLCorrectly(url: URL, expectedService: MusicServiceIdentifier, expectedIdentifier: String) {
        let service = makeService(for: expectedService)
        let track = service.parse(url: url)
        
        #expect(track != nil, "Should parse \(expectedService.displayName) URL")
        #expect(track?.service == expectedService)
        #expect(track?.url == url)
        #expect(track?.identifier == expectedIdentifier)
        // Metadata is nil until fetchMetadata is called
        #expect(track?.title == nil)
        #expect(track?.artist == nil)
    }
}

// MARK: - Alternative URL Format Tests

@Suite("Alternative URL Formats")
struct AlternativeURLFormatTests {
    
    // Apple Music
    @Test("Apple Music handles music:// scheme URLs")
    func appleMusicHandlesMusicScheme() {
        let service = AppleMusicService()
        let url = URL(string: "music://album/some-album/1234567890")!
        #expect(service.canHandle(url: url))
    }
    
    @Test("Apple Music falls back to album ID when no track ID in query")
    func appleMusicFallsBackToAlbumId() {
        let service = AppleMusicService()
        let albumOnlyURL = URL(string: "https://music.apple.com/us/album/some-album/1234567890")!
        let track = service.parse(url: albumOnlyURL)
        #expect(track?.identifier == "1234567890")
    }
    
    // Spotify
    @Test("Spotify handles spotify: scheme URLs")
    func spotifyHandlesSpotifyScheme() {
        let service = SpotifyService()
        let url = URL(string: "spotify:track:4iV5W9uYEdYUVa79Axb7Rh")!
        
        #expect(service.canHandle(url: url))
        
        let track = service.parse(url: url)
        #expect(track?.identifier == "track:4iV5W9uYEdYUVa79Axb7Rh")
    }
    
    @Test("Spotify parses album URLs")
    func spotifyParsesAlbumURL() {
        let service = SpotifyService()
        let albumURL = URL(string: "https://open.spotify.com/album/1DFixLWuPkv3KT3TnV35m3")!
        let track = service.parse(url: albumURL)
        #expect(track?.identifier == "album:1DFixLWuPkv3KT3TnV35m3")
    }
    
    // Bandcamp
    @Test("Bandcamp parses track URLs")
    func bandcampParsesTrackURL() {
        let service = BandcampService()
        let trackURL = URL(string: "https://artist.bandcamp.com/track/song-name")!
        let track = service.parse(url: trackURL)
        #expect(track?.identifier == "track:song-name")
    }
    
    // YouTube
    @Test("YouTube handles music.youtube.com URLs")
    func youtubeHandlesMusicDomain() {
        let service = YouTubeMusicService()
        let musicURL = URL(string: "https://music.youtube.com/watch?v=7SKorvPNRDI")!
        #expect(service.canHandle(url: musicURL))
    }
    
    @Test("YouTube handles youtu.be short URLs")
    func youtubeHandlesShortURL() {
        let service = YouTubeMusicService()
        let shortURL = URL(string: "https://youtu.be/7SKorvPNRDI")!
        
        #expect(service.canHandle(url: shortURL))
        
        let track = service.parse(url: shortURL)
        #expect(track?.identifier == "7SKorvPNRDI")
    }
}

// MARK: - MusicServiceRegistry Tests

@Suite("Music Service Registry")
struct MusicServiceRegistryTests {
    let registry = MusicServiceRegistry.shared
    
    @Test("Identifies service from URL", arguments: [
        (TestURLs.appleMusic, MusicServiceIdentifier.appleMusic),
        (TestURLs.spotify, .spotify),
        (TestURLs.bandcamp, .bandcamp),
        (TestURLs.youtube, .youtubeMusic),
        (TestURLs.soundcloud, .soundcloud),
    ])
    func identifiesServiceFromURL(url: URL, expectedService: MusicServiceIdentifier) {
        let service = registry.identifyService(for: url)
        #expect(service?.identifier == expectedService)
    }
    
    @Test("Parses URL to track", arguments: [
        (TestURLs.appleMusic, MusicServiceIdentifier.appleMusic),
        (TestURLs.spotify, .spotify),
        (TestURLs.bandcamp, .bandcamp),
        (TestURLs.youtube, .youtubeMusic),
        (TestURLs.soundcloud, .soundcloud),
    ])
    func parsesURLToTrack(url: URL, expectedService: MusicServiceIdentifier) {
        let track = registry.parse(url: url)
        #expect(track?.service == expectedService)
    }
    
    @Test("Returns nil for unknown URLs")
    func returnsNilForUnknownURLs() {
        let unknownURL = URL(string: "https://example.com/some-page")!
        let track = registry.parse(url: unknownURL)
        #expect(track == nil)
    }
}

// MARK: - MusicTrack Display Tests

@Suite("Music Track Display")
struct MusicTrackDisplayTests {
    
    @Test("Display title formatting", arguments: [
        ("Take A Little Trip", "Patrick Cowley", "Afternooners", "Take A Little Trip - Patrick Cowley (Afternooners)"),
        ("Song Name", nil as String?, nil as String?, "Song Name"),
        ("Song Name", "Artist", nil as String?, "Song Name - Artist"),
    ])
    func displayTitleFormatting(title: String?, artist: String?, album: String?, expected: String) {
        let track = MusicTrack(
            service: .spotify,
            url: TestURLs.spotify,
            title: title,
            artist: artist,
            album: album,
            identifier: "123"
        )
        #expect(track.displayTitle == expected)
    }
    
    @Test("Display title falls back to URL when no metadata")
    func displayTitleFallsBackToURL() {
        let track = MusicTrack(
            service: .spotify,
            url: TestURLs.spotify,
            title: nil,
            artist: nil,
            album: nil,
            identifier: "123"
        )
        #expect(track.displayTitle == TestURLs.spotify.absoluteString)
    }
}

// MARK: - API Response Parsing Tests

@Suite("API Response Parsing")
struct APIResponseParsingTests {
    
    @Test("Spotify identifier parsing extracts type and ID")
    func spotifyIdentifierParsing() {
        let identifier = "track:5ghb02xEjrv3ZSrURC6O57"
        let components = identifier.split(separator: ":")
        
        #expect(components.count == 2)
        #expect(String(components[0]) == "track")
        #expect(String(components[1]) == "5ghb02xEjrv3ZSrURC6O57")
    }
    
    @Test("Apple Music identifier is numeric")
    func appleMusicIdentifierIsNumeric() {
        let service = AppleMusicService()
        let track = service.parse(url: TestURLs.appleMusic)
        
        #expect(track?.identifier == "1280171884")
        #expect(Int(track?.identifier ?? "") != nil)
    }
    
    @Test("Bandcamp identifier includes type prefix", arguments: [
        (URL(string: "https://artist.bandcamp.com/album/some-album")!, "album:"),
        (URL(string: "https://artist.bandcamp.com/track/some-song")!, "track:"),
    ])
    func bandcampIdentifierIncludesType(url: URL, expectedPrefix: String) {
        let service = BandcampService()
        let track = service.parse(url: url)
        #expect(track?.identifier?.hasPrefix(expectedPrefix) == true)
    }
}
