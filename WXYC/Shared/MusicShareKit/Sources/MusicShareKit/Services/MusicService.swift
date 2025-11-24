//
//  MusicService.swift
//  MusicShareKit
//
//  Created by Jake Bromberg on 11/24/25.
//

import Foundation

public protocol MusicService {
    var identifier: MusicServiceIdentifier { get }
    
    /// Check if this service can handle the given URL
    func canHandle(url: URL) -> Bool
    
    /// Parse the URL and extract metadata to create a MusicTrack
    func parse(url: URL) -> MusicTrack?
    
    /// Fetch artwork URL for the track (async)
    func fetchArtwork(for track: MusicTrack) async throws -> URL?
}

