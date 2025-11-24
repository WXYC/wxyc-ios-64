//
//  MusicServiceRegistry.swift
//  Request Share Extension
//
//  Created by Jake Bromberg on 11/24/25.
//

import Foundation

class MusicServiceRegistry {
    static let shared = MusicServiceRegistry()
    
    private let services: [MusicService]
    
    private init() {
        services = [
            AppleMusicService(),
            SpotifyService(),
            BandcampService(),
            YouTubeMusicService(),
            SoundCloudService()
        ]
    }
    
    func identifyService(for url: URL) -> MusicService? {
        return services.first { $0.canHandle(url: url) }
    }
    
    func parse(url: URL) -> MusicTrack? {
        guard let service = identifyService(for: url) else {
            return nil
        }
        return service.parse(url: url)
    }
}

