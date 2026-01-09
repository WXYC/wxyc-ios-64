import Testing
import Foundation
@testable import Metadata

@Suite("PlaycutMetadata Tests")
struct PlaycutMetadataTests {

    // MARK: - ArtistMetadata Tests

    @Test("ArtistMetadata encodes and decodes correctly")
    func artistMetadataEncodesAndDecodes() throws {
        let artist = ArtistMetadata(
            bio: "Test biography",
            wikipediaURL: URL(string: "https://en.wikipedia.org/wiki/Test"),
            discogsArtistId: 12345
        )

        let encoded = try JSONEncoder().encode(artist)
        let decoded = try JSONDecoder().decode(ArtistMetadata.self, from: encoded)

        #expect(decoded == artist)
        #expect(decoded.bio == "Test biography")
        #expect(decoded.wikipediaURL?.absoluteString == "https://en.wikipedia.org/wiki/Test")
        #expect(decoded.discogsArtistId == 12345)
    }

    @Test("ArtistMetadata empty instance has nil values")
    func artistMetadataEmptyInstance() {
        let empty = ArtistMetadata.empty

        #expect(empty.bio == nil)
        #expect(empty.wikipediaURL == nil)
        #expect(empty.discogsArtistId == nil)
    }

    // MARK: - AlbumMetadata Tests

    @Test("AlbumMetadata encodes and decodes correctly")
    func albumMetadataEncodesAndDecodes() throws {
        let album = AlbumMetadata(
            label: "Test Records",
            releaseYear: 2024,
            discogsURL: URL(string: "https://www.discogs.com/release/123"),
            discogsArtistId: 456
        )

        let encoded = try JSONEncoder().encode(album)
        let decoded = try JSONDecoder().decode(AlbumMetadata.self, from: encoded)

        #expect(decoded == album)
        #expect(decoded.label == "Test Records")
        #expect(decoded.releaseYear == 2024)
        #expect(decoded.discogsURL?.absoluteString == "https://www.discogs.com/release/123")
        #expect(decoded.discogsArtistId == 456)
    }

    @Test("AlbumMetadata empty instance has nil values")
    func albumMetadataEmptyInstance() {
        let empty = AlbumMetadata.empty

        #expect(empty.label == nil)
        #expect(empty.releaseYear == nil)
        #expect(empty.discogsURL == nil)
        #expect(empty.discogsArtistId == nil)
    }

    // MARK: - StreamingLinks Tests

    @Test("StreamingLinks encodes and decodes correctly")
    func streamingLinksEncodesAndDecodes() throws {
        let streaming = StreamingLinks(
            spotifyURL: URL(string: "https://open.spotify.com/track/123"),
            appleMusicURL: URL(string: "https://music.apple.com/track/456"),
            youtubeMusicURL: URL(string: "https://music.youtube.com/watch?v=abc"),
            bandcampURL: URL(string: "https://artist.bandcamp.com/track/song"),
            soundcloudURL: URL(string: "https://soundcloud.com/artist/song")
        )

        let encoded = try JSONEncoder().encode(streaming)
        let decoded = try JSONDecoder().decode(StreamingLinks.self, from: encoded)

        #expect(decoded == streaming)
        #expect(decoded.spotifyURL?.absoluteString == "https://open.spotify.com/track/123")
        #expect(decoded.appleMusicURL?.absoluteString == "https://music.apple.com/track/456")
    }

    @Test("StreamingLinks hasAny returns true when any link present")
    func streamingLinksHasAny() {
        let withSpotify = StreamingLinks(spotifyURL: URL(string: "https://spotify.com"))
        let withApple = StreamingLinks(appleMusicURL: URL(string: "https://music.apple.com"))
        let empty = StreamingLinks.empty

        #expect(withSpotify.hasAny == true)
        #expect(withApple.hasAny == true)
        #expect(empty.hasAny == false)
    }

    // MARK: - PlaycutMetadata Composite Tests

    @Test("PlaycutMetadata encodes and decodes with composite structure")
    func playcutMetadataCompositeEncodesAndDecodes() throws {
        let metadata = PlaycutMetadata(
            artist: ArtistMetadata(bio: "Bio", wikipediaURL: nil, discogsArtistId: 100),
            album: AlbumMetadata(label: "Label", releaseYear: 2023, discogsURL: nil, discogsArtistId: 100),
            streaming: StreamingLinks(spotifyURL: URL(string: "https://spotify.com"))
        )

        let encoded = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(PlaycutMetadata.self, from: encoded)

        #expect(decoded == metadata)
        #expect(decoded.artist.bio == "Bio")
        #expect(decoded.album.label == "Label")
        #expect(decoded.streaming.spotifyURL != nil)
    }

    @Test("PlaycutMetadata backward-compatible accessors work")
    func playcutMetadataBackwardCompatibleAccessors() {
        let metadata = PlaycutMetadata(
            artist: ArtistMetadata(bio: "Test Bio", wikipediaURL: URL(string: "https://wikipedia.org")),
            album: AlbumMetadata(label: "Test Label", releaseYear: 2024, discogsURL: URL(string: "https://discogs.com")),
            streaming: StreamingLinks(
                spotifyURL: URL(string: "https://spotify.com"),
                appleMusicURL: URL(string: "https://apple.com")
            )
        )

        // Verify backward-compatible accessors
        #expect(metadata.artistBio == "Test Bio")
        #expect(metadata.wikipediaURL?.absoluteString == "https://wikipedia.org")
        #expect(metadata.label == "Test Label")
        #expect(metadata.releaseYear == 2024)
        #expect(metadata.discogsURL?.absoluteString == "https://discogs.com")
        #expect(metadata.spotifyURL?.absoluteString == "https://spotify.com")
        #expect(metadata.appleMusicURL?.absoluteString == "https://apple.com")
        #expect(metadata.hasStreamingLinks == true)
    }

    @Test("PlaycutMetadata legacy initializer works")
    func playcutMetadataLegacyInitializer() {
        let metadata = PlaycutMetadata(
            label: "Legacy Label",
            releaseYear: 2022,
            discogsURL: URL(string: "https://discogs.com/release/1"),
            artistBio: "Legacy Bio",
            wikipediaURL: URL(string: "https://wikipedia.org/artist"),
            spotifyURL: URL(string: "https://spotify.com/track"),
            appleMusicURL: nil,
            youtubeMusicURL: nil,
            bandcampURL: nil,
            soundcloudURL: nil,
            discogsArtistId: 789
        )

        // Verify legacy values are stored in correct sub-structs
        #expect(metadata.artist.bio == "Legacy Bio")
        #expect(metadata.artist.wikipediaURL?.absoluteString == "https://wikipedia.org/artist")
        #expect(metadata.artist.discogsArtistId == 789)
        #expect(metadata.album.label == "Legacy Label")
        #expect(metadata.album.releaseYear == 2022)
        #expect(metadata.album.discogsURL?.absoluteString == "https://discogs.com/release/1")
        #expect(metadata.album.discogsArtistId == 789)
        #expect(metadata.streaming.spotifyURL?.absoluteString == "https://spotify.com/track")
    }

    @Test("PlaycutMetadata empty instance has empty sub-structs")
    func playcutMetadataEmptyInstance() {
        let empty = PlaycutMetadata.empty

        #expect(empty.artist == ArtistMetadata.empty)
        #expect(empty.album == AlbumMetadata.empty)
        #expect(empty.streaming == StreamingLinks.empty)
        #expect(empty.hasStreamingLinks == false)
    }
}
