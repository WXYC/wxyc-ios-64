//
//  MusicService+UI.swift
//  Metadata
//
//  SwiftUI presentation affordances (icon, colour, link-handling) for the canonical
//  Core.MusicService enum. Lives in Metadata so Core stays SwiftUI-free.
//
//  Created by Jake Bromberg on 05/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import SwiftUI

extension MusicService {
    /// Asset-catalog name for the service's brand icon. Only meaningful when `hasCustomIcon` is true.
    public var iconName: String {
        switch self {
        case .spotify: "spotify"
        case .appleMusic: "applemusic"
        case .youtubeMusic: "youtubemusic"
        case .bandcamp: "bandcamp"
        case .soundcloud: "soundcloud"
        case .unknown: ""
        }
    }

    /// SF Symbol fallback used when there is no custom brand asset for the service.
    public var systemIcon: String {
        switch self {
        case .spotify: "music.note"
        case .appleMusic: "music.note"
        case .youtubeMusic: "play.rectangle.fill"
        case .bandcamp: "music.quarternote.3"
        case .soundcloud: "waveform"
        case .unknown: "questionmark.circle"
        }
    }

    /// Brand colour used as the streaming-link button's background.
    public var color: Color {
        switch self {
        case .spotify: Color(red: 0.11, green: 0.73, blue: 0.33)
        case .appleMusic: Color(red: 0.98, green: 0.18, blue: 0.33)
        case .youtubeMusic: Color(red: 1.0, green: 0.0, blue: 0.0)
        case .bandcamp: Color(red: 0.38, green: 0.76, blue: 0.87)
        case .soundcloud: Color(red: 1.0, green: 0.33, blue: 0.0)
        case .unknown: Color.gray
        }
    }

    /// Whether the streaming-link UI should render the bundled brand asset (`iconName`) instead of `systemIcon`.
    public var hasCustomIcon: Bool {
        switch self {
        case .spotify, .appleMusic, .bandcamp: true
        case .youtubeMusic, .soundcloud, .unknown: false
        }
    }

    /// Services whose links point at search pages rather than direct deep links should open in
    /// an in-app Safari sheet so query parameters survive (Universal Link handoff would strip them).
    public var opensInBrowser: Bool {
        switch self {
        case .spotify, .appleMusic, .youtubeMusic, .bandcamp, .unknown: false
        case .soundcloud: true
        }
    }
}
