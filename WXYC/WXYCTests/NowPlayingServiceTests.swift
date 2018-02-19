//
//  NowPlayingServiceTests.swift
//  WXYCTests
//
//  Created by Jake Bromberg on 2/11/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import XCTest
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
    func request(url: URL) -> Future<Data> {
        print(">>>>>", url)
        return Future()
    }
}

final class TestDefaults: Defaults {
    var playcut: Playcut? = nil
    
    func object(forKey defaultName: String) -> Any? {
        guard defaultName == "playcut" else {
            fatalError()
        }
        
        return self.playcut
    }
    
    func set(_ value: Any?, forKey defaultName: String) {
        print(">>>>>", value, defaultName)
        UserDefaults.standard.setValue(value, forKey: defaultName)
    }
}

final class TestCache: Cachable {
    private let defaults: Defaults
    
    public init(defaults: Defaults) {
        self.defaults = defaults
    }
    
    public subscript<Key: RawRepresentable, Value: Codable>(_ key: Key) -> Value? where Key.RawValue == String {
        get {
            return self[key, defaultLifespan]
        }
        set {
            self[key, defaultLifespan] = newValue
        }
    }
    
    public subscript<Key: RawRepresentable, Value: Codable>(
        key: Key,
        lifespan: TimeInterval
        ) -> Value? where Key.RawValue == String {
        get {
            guard let encodedCachedRecord = self.defaults.object(forKey: key.rawValue) as? Data else {
                return nil
            }
            
            let decoder = JSONDecoder()
            
            guard let cachedRecord = try? decoder.decode(CachedRecord<Value>.self, from: encodedCachedRecord) else {
                return nil
            }
            
            guard !cachedRecord.isExpired else {
                return nil
            }
            
            return cachedRecord.value
        }
        set {
            if let newValue = newValue {
                let cachedRecord = CachedRecord(value: newValue, lifespan: lifespan)
                
                let encoder = JSONEncoder()
                let encodedCachedRecord = try? encoder.encode(cachedRecord)
                
                self.defaults.set(encodedCachedRecord, forKey: key.rawValue)
            } else {
                self.defaults.set(nil, forKey: key.rawValue)
            }
        }
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
        let defaults = TestDefaults()
        defaults.playcut = Fixture.playcut1
        
        let nowPlayingService = NowPlayingService(
            cache: Cache(defaults: defaults),
            webSession: webSession
        )
        
        nowPlayingService.getCurrentPlaycut().observe { result in
            guard case .success(let playcut) = result else {
                fatalError()
            }
            
            XCTAssertEqual(playcut, Fixture.playcut1)
        }
    }
    
    func testExpiredCache() {
        let webSession = TestWebSession()
        let defaults = TestDefaults()
        let cache = TestCache(defaults: defaults)
        
        let nowPlayingService = NowPlayingService(
            cache: cache,
            webSession: webSession
        )
        
        _ = nowPlayingService.getCurrentPlaycut()
    }
    
    func testGettingTwoDifferentPlaycuts() {
        let webSession = TestWebSession()
        let defaults = TestDefaults()
        defaults.playcut = Fixture.playcut1
        
        let nowPlayingService = NowPlayingService(
            cache: Cache(defaults: defaults),
            webSession: webSession
        )
        
        nowPlayingService.getCurrentPlaycut().observe { result in
            guard case .success(let playcut) = result else {
                fatalError()
            }
            
            XCTAssertEqual(playcut, Fixture.playcut1)
        }
    }
    
    
}
