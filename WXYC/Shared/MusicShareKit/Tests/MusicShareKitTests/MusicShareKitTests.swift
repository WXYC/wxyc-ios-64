import XCTest
@testable import MusicShareKit

final class MusicShareKitTests: XCTestCase {
    
    func testAppleMusicURLParsing() {
        let service = AppleMusicService()
        let url = URL(string: "https://music.apple.com/us/album/some-album/1234567890")!
        
        XCTAssertTrue(service.canHandle(url: url))
        
        let track = service.parse(url: url)
        XCTAssertNotNil(track)
        XCTAssertEqual(track?.service, .appleMusic)
    }
    
    func testSpotifyURLParsing() {
        let service = SpotifyService()
        let url = URL(string: "https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh")!
        
        XCTAssertTrue(service.canHandle(url: url))
        
        let track = service.parse(url: url)
        XCTAssertNotNil(track)
        XCTAssertEqual(track?.service, .spotify)
    }
    
    func testBandcampURLParsing() {
        let service = BandcampService()
        let url = URL(string: "https://someartist.bandcamp.com/track/some-track")!
        
        XCTAssertTrue(service.canHandle(url: url))
        
        let track = service.parse(url: url)
        XCTAssertNotNil(track)
        XCTAssertEqual(track?.service, .bandcamp)
        XCTAssertEqual(track?.artist, "Someartist")
    }
    
    func testYouTubeMusicURLParsing() {
        let service = YouTubeMusicService()
        let url = URL(string: "https://music.youtube.com/watch?v=dQw4w9WgXcQ")!
        
        XCTAssertTrue(service.canHandle(url: url))
        
        let track = service.parse(url: url)
        XCTAssertNotNil(track)
        XCTAssertEqual(track?.service, .youtubeMusic)
        XCTAssertEqual(track?.identifier, "dQw4w9WgXcQ")
    }
    
    func testSoundCloudURLParsing() {
        let service = SoundCloudService()
        let url = URL(string: "https://soundcloud.com/some-artist/some-track")!
        
        XCTAssertTrue(service.canHandle(url: url))
        
        let track = service.parse(url: url)
        XCTAssertNotNil(track)
        XCTAssertEqual(track?.service, .soundcloud)
    }
}
