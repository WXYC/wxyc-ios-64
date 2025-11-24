//
//  MusicServiceRegistry.swift
//  MusicShareKit
//
//  Created by Jake Bromberg on 11/24/25.
//

import Foundation

public final class MusicServiceRegistry: Sendable {
    public static let shared = MusicServiceRegistry()
    
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
    
    public func identifyService(for url: URL) -> MusicService? {
        return services.first { $0.canHandle(url: url) }
    }
    
    public func parse(url: URL) -> MusicTrack? {
        guard let service = identifyService(for: url) else {
            return nil
        }
        return service.parse(url: url)
    }
}

