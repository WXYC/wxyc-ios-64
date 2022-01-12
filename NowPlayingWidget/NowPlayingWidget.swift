//
//  NowPlayingWidget.swift
//  NowPlayingWidget
//
//  Created by Jake Bromberg on 1/13/22.
//  Copyright © 2022 WXYC. All rights reserved.
//

import WidgetKit
import SwiftUI
import Core

class Provider: TimelineProvider {
    var nowPlayingObservations: [Any] = []
    
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry.placeholder(family: context.family)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> ()) {
        Task {
            if let nowPlayingItem = await NowPlayingService.shared.fetch() {
                completion(NowPlayingEntry(nowPlayingItem, family: context.family))
            } else {
                completion(NowPlayingEntry.placeholder(family: context.family))
            }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        Task {
            if let nowPlayingItem = await NowPlayingService.shared.fetch() {
                let timeline = Timeline(entries: [NowPlayingEntry(nowPlayingItem, family: context.family)], policy: .atEnd)
                completion(timeline)
            } else {
                let timeline = Timeline(entries: [NowPlayingEntry.placeholder(family: context.family)], policy: .atEnd)
                completion(timeline)
            }
        }
    }
}

struct NowPlayingEntry: TimelineEntry {
    let date: Date = Date(timeIntervalSinceNow: 1)
    let artist: String
    let songTitle: String
    let artwork: UIImage?
    let family: WidgetFamily
    
    init(_ nowPlayingItem: NowPlayingItem, family: WidgetFamily) {
        self.artist = nowPlayingItem.playcut.artistName
        self.songTitle = nowPlayingItem.playcut.songTitle
        self.artwork = nowPlayingItem.artwork
        self.family = family
    }
    
    init(artist: String, songTitle: String, artwork: UIImage?, family: WidgetFamily) {
        self.artist = artist
        self.songTitle = songTitle
        self.artwork = artwork
        self.family = family
    }
    
    public static func placeholder(family: WidgetFamily) -> Self {
        NowPlayingEntry(artist: "WXYC 89.3 FM", songTitle: "Chapel Hill, NC", artwork: nil, family: family)
    }
}

protocol NowPlayingWidgetEntryView: View {
    var entry: NowPlayingEntry { get }
    var artwork: AnyView { get }
}

extension NowPlayingWidgetEntryView {
    var artwork: AnyView {
        if let artwork = entry.artwork {
            return AnyView(Image(uiImage: artwork).resizable().unredacted())
        } else {
            return AnyView(Self.defaultArtwork.unredacted())
        }
    }
    
    private static var defaultArtwork: some View {
        ZStack {
            Image(uiImage: #imageLiteral(resourceName: "background.pdf"))
            Image(uiImage: #imageLiteral(resourceName: "logo.pdf"))
        }
    }
}

struct SmallNowPlayingWidgetEntryView: NowPlayingWidgetEntryView {
    var entry: Provider.Entry

    var body: some View {
        ZStack(alignment: .bottom) {
            self.artwork
            
            VStack(alignment: .leading, spacing: 0.0) {
                Text(entry.artist)
                    .font(.headline)
                    .foregroundStyle(.foreground)
                    .padding(EdgeInsets(top: 5, leading: 0, bottom: 0, trailing: 0))
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)

                Text(entry.songTitle)
                    .font(.subheadline)
                    .foregroundStyle(.foreground)
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 5, trailing: 0))
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
            }
            .background(.ultraThinMaterial)
            .multilineTextAlignment(.leading)
        }
    }
}

struct MediumNowPlayingWidgetEntryView: NowPlayingWidgetEntryView {
    var entry: Provider.Entry

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            self.artwork
            
            VStack(alignment: .leading) {
                Text(entry.artist)
                    .font(.headline)
                    .foregroundStyle(.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.songTitle)
                    .font(.subheadline)
                    .foregroundStyle(.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .background(.ultraThickMaterial)
    }
}

struct LargeNowPlayingWidgetEntryView: NowPlayingWidgetEntryView {
    var entry: Provider.Entry

    var body: some View {
        ZStack(alignment: .bottom) {
            self.artwork
            
            VStack(alignment: .leading) {
                Text(entry.artist)
                    .font(.title)
                    .foregroundStyle(.foreground)
                    .padding(EdgeInsets(top: 5, leading: 0, bottom: 0, trailing: 0))
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)

                Text(entry.songTitle)
                    .font(.title2)
                    .foregroundStyle(.foreground)
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 5, trailing: 0))
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
            }
            .background(.ultraThinMaterial)
        }
    }
}

@main
struct NowPlayingWidget: Widget {
    let kind: String = "NowPlayingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry -> AnyView in
            switch entry.family {
            case .systemSmall:
                return AnyView(SmallNowPlayingWidgetEntryView(entry: entry))
            case .systemMedium:
                return AnyView(MediumNowPlayingWidgetEntryView(entry: entry))
            default:
                return AnyView(LargeNowPlayingWidgetEntryView(entry: entry))
            }
        }
        .configurationDisplayName("Now Playing")
        .description("Now playing on WXYC…")
    }
}
