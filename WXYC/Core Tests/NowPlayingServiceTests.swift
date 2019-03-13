//
//  NowPlayingServiceTests.swift
//  WXYCTests
//
//  Created by Jake Bromberg on 2/11/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import XCTest
import UI
import Spring
@testable import Core

enum Fixture {
    static let playcut1 = Playcut(
        id: 1768545,
        hour: 1518408000000,
        chronOrderID: 146173021,
        songTitle: "Dancing Queen",
        labelName: "Atlantic",
        artistName: "ABBA",
        releaseTitle: "Dancing queen 7"
    )
    
    static let playcut2 = Playcut(
        id: 1768705,
        hour: 1518444000000,
        chronOrderID: 146179020,
        songTitle: "Left Fields",
        labelName: "INTERNATIONAL ANTHEM RECORDING COMPANY",
        artistName: "Makaya McCraven",
        releaseTitle: "Highly Rare"
    )
}

final class TestWebSession: WebSession {
    var playcutFixtures: [Playcut] = [Fixture.playcut1]
    
    func request(url: URL) -> Future<Data> {
        let result = self.future(atIndex: self.currentIndex)
        currentIndex = (currentIndex + 1) % self.playcutFixtures.endIndex
        
        return result
    }
    
    // MARK: Private

    private var currentIndex = 0

    private func future(atIndex: Int) -> Future<Data> {
        let encoder = JSONEncoder()
        let data = try! encoder.encode(self.playcutFixtures[self.currentIndex])
        return Promise(value: data)
    }
    
}

final class TestDefaults: Defaults {
    var store = [String:Any?]()
    
    func object(forKey defaultName: String) -> Any? {
        guard defaultName == "playcut" else {
            fatalError()
        }
        
        return self.store[defaultName] as Any?
    }
    
    func set(_ value: Any?, forKey defaultName: String) {
        self.store[defaultName] = value
    }
}

struct TestObserver: NowPlayingServiceObserver {
    let updatePlaycut: (Result<Playcut>) -> ()
    let updateArtwork: (Result<UIImage>) -> ()

    func updateWith(playcutResult: Result<Playcut>) {
        updatePlaycut(playcutResult)
    }
    
    func updateWith(artworkResult: Result<UIImage>) {
        updateArtwork(artworkResult)
    }
}

class NowPlayingServiceTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testSuccessfullyRetrievingFromCache() {
        let webSession = TestWebSession()
        let cache = TestDefaults()
        let cacheCoordinator = Cache(cache: cache)
        cacheCoordinator.set(value: Fixture.playcut1, for: CacheKey.playcut, lifespan: DefaultLifespan)
        
        let playlistService = PlaylistService(cacheCoordinator: cacheCoordinator, webSession: webSession)
        let observer = TestObserver(updatePlaycut: <#T##(Result<Playcut>) -> ()#>, updateArtwork: <#T##(Result<UIImage>) -> ()#>)
        
        let nowPlayingService = NowPlayingService(
            playlistService: playlistService,
            artworkService: ArtworkService.shared,
            initialObservers: []
        )
        
        nowPlayingService
        nowPlayingService.getPlaycut().observe { result in
            guard case .success(let playcut) = result else {
                fatalError()
            }
            
            XCTAssertEqual(playcut, Fixture.playcut1)
        }
    }
    
    func testExpiredCache() {
        let webSession = TestWebSession()
        let cache = TestDefaults()
        let cacheCoordinator = Cache(cache: cache)
        
        let playlistService = PlaylistService(cacheCoordinator: cacheCoordinator, webSession: webSession)
        
        let nowPlayingService = NowPlayingService(
            playlistService: playlistService,
            artworkService: ArtworkService.shared,
            initialObservers: []
        )

        _ = nowPlayingService.getPlaycut()
    }
    
    func testGettingTwoDifferentPlaycuts() {
        let playcutObserver = TestNowPlayingServiceObserver()

        let nowPlayingService = self.createNowPlayingService()
        _ = nowPlayingService(
            service: nowPlayingService,
            artworkService: ArtworkService(),
            initialObservers: [playcutObserver]
        )

        _ = nowPlayingService.getPlaycut()
        
        guard let playcutResult = playcutObserver.playcutResult else {
            XCTFail()
            return
        }
        
        guard case .success(let playcut) = playcutResult else {
            XCTFail()
            return
        }

        XCTAssertNotEqual(playcut.songTitle, RadioStation.WXYC.name)
        XCTAssertNotEqual(playcut.songTitle, RadioStation.WXYC.secondaryName)
    }
    
    func createNowPlayingService() -> NowPlayingService {
        let webSession = TestWebSession()
        webSession.playcutFixtures = [Fixture.playcut1, Fixture.playcut2]
        
        let cache = TestDefaults()
        let cacheCoordinator = Cache(cache: cache)
        cacheCoordinator[Core.CacheKey.playcut] = Fixture.playcut1

        let nowPlayingService = NowPlayingService(
            cacheCoordinator: cacheCoordinator,
            webSession: webSession
        )
        
        return nowPlayingService
    }
    
    func testExpiredCacheWithSamePlaycutResult() {
        
    }
}
