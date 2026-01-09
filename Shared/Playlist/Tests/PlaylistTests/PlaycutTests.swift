import Testing
import Foundation
@testable import Playlist

@Suite("Playcut Tests")
struct PlaycutTests {

    // MARK: - artworkCacheKey Tests

    @Test("artworkCacheKey uses releaseTitle when available")
    func artworkCacheKeyUsesReleaseTitle() {
        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )

        #expect(playcut.artworkCacheKey == "Test Artist-Test Album")
    }

    @Test("artworkCacheKey uses songTitle when releaseTitle is nil")
    func artworkCacheKeyUsesSongTitleWhenReleaseTitleNil() {
        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: nil
        )

        #expect(playcut.artworkCacheKey == "Test Artist-Test Song")
    }

    @Test("artworkCacheKey uses songTitle when releaseTitle is empty string")
    func artworkCacheKeyUsesSongTitleWhenReleaseTitleEmpty() {
        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: ""
        )

        #expect(playcut.artworkCacheKey == "Test Artist-Test Song")
    }

    @Test("artworkCacheKey is consistent for same content")
    func artworkCacheKeyConsistentForSameContent() {
        let playcut1 = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Song",
            labelName: nil,
            artistName: "Artist",
            releaseTitle: "Album"
        )

        let playcut2 = Playcut(
            id: 2,  // Different ID
            hour: 2000,  // Different hour
            chronOrderID: 2,  // Different chronOrderID
            songTitle: "Song",
            labelName: "Different Label",  // Different label
            artistName: "Artist",
            releaseTitle: "Album"
        )

        // Same artist and release should produce same cache key
        #expect(playcut1.artworkCacheKey == playcut2.artworkCacheKey)
    }

    @Test("artworkCacheKey differs for different artists")
    func artworkCacheKeyDiffersForDifferentArtists() {
        let playcut1 = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Song",
            labelName: nil,
            artistName: "Artist A",
            releaseTitle: "Album"
        )

        let playcut2 = Playcut(
            id: 2,
            hour: 1000,
            chronOrderID: 2,
            songTitle: "Song",
            labelName: nil,
            artistName: "Artist B",
            releaseTitle: "Album"
        )

        #expect(playcut1.artworkCacheKey != playcut2.artworkCacheKey)
    }

    @Test("artworkCacheKey differs for different releases")
    func artworkCacheKeyDiffersForDifferentReleases() {
        let playcut1 = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Song",
            labelName: nil,
            artistName: "Artist",
            releaseTitle: "Album A"
        )

        let playcut2 = Playcut(
            id: 2,
            hour: 1000,
            chronOrderID: 2,
            songTitle: "Song",
            labelName: nil,
            artistName: "Artist",
            releaseTitle: "Album B"
        )

        #expect(playcut1.artworkCacheKey != playcut2.artworkCacheKey)
    }
}
