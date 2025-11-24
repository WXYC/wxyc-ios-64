import Testing
@testable import MusicShareKit

@Test func appleMusicURLParsing() async throws {
    let service = AppleMusicService()
    let url = URL(string: "https://music.apple.com/us/album/some-album/1234567890")!
    
    #expect(service.canHandle(url: url) == true)
    
    let track = service.parse(url: url)
    #expect(track != nil)
    #expect(track?.service == .appleMusic)
}

@Test func spotifyURLParsing() async throws {
    let service = SpotifyService()
    let url = URL(string: "https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh")!
    
    #expect(service.canHandle(url: url) == true)
    
    let track = service.parse(url: url)
    #expect(track != nil)
    #expect(track?.service == .spotify)
}

@Test func bandcampURLParsing() async throws {
    let service = BandcampService()
    let url = URL(string: "https://someartist.bandcamp.com/track/some-track")!
    
    #expect(service.canHandle(url: url) == true)
    
    let track = service.parse(url: url)
    #expect(track != nil)
    #expect(track?.service == .bandcamp)
    #expect(track?.artist == "Someartist")
}

@Test func youTubeMusicURLParsing() async throws {
    let service = YouTubeMusicService()
    let url = URL(string: "https://music.youtube.com/watch?v=dQw4w9WgXcQ")!
    
    #expect(service.canHandle(url: url) == true)
    
    let track = service.parse(url: url)
    #expect(track != nil)
    #expect(track?.service == .youtubeMusic)
    #expect(track?.identifier == "dQw4w9WgXcQ")
}

@Test func soundCloudURLParsing() async throws {
    let service = SoundCloudService()
    let url = URL(string: "https://soundcloud.com/some-artist/some-track")!
    
    #expect(service.canHandle(url: url) == true)
    
    let track = service.parse(url: url)
    #expect(track != nil)
    #expect(track?.service == .soundcloud)
}

