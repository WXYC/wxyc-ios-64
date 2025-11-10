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
import PostHog
import AppIntents
import Secrets
import Analytics

final class Provider: TimelineProvider, Sendable {
    let playlistService = PlaylistService()
    let artworkService = ArtworkService()
    
    init() {
        let POSTHOG_API_KEY = Secrets.posthogApiKey
        let POSTHOG_HOST = "https://us.i.posthog.com"
        let config = PostHogConfig(apiKey: POSTHOG_API_KEY, host: POSTHOG_HOST)
        PostHogSDK.shared.setup(config)
    }
    
    func placeholder(in context: Context) -> NowPlayingTimelineEntry {
        var nowPlayingItemsWithArtwork: [NowPlayingItem] = [
            NowPlayingItem.placeholder,
            NowPlayingItem.placeholder,
            NowPlayingItem.placeholder,
            NowPlayingItem.placeholder,
        ]
        
        let (nowPlayingItem, recentItems) = nowPlayingItemsWithArtwork.popFirst()

        return NowPlayingTimelineEntry(
            nowPlayingItem: nowPlayingItem,
            recentItems: recentItems,
            family: context.family
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping @Sendable (NowPlayingTimelineEntry) -> ()) {
        let family = context.family
        PostHogSDK.shared.capture(
            "getSnapshot",
            context: "NowPlayingWidget",
            additionalData: ["family" : String(describing: family)]
        )

        Task {
            let playlist = await playlistService.fetchPlaylist()
            let recentPlaycuts = playlist.playcuts
                .sorted(by: >)
                .prefix(4)

            var nowPlayingItemsWithArtwork = await recentPlaycuts.asyncFlatMap { playcut in
                NowPlayingItem(
                    playcut: playcut,
                    artwork: try? await self.artworkService.fetchArtwork(for: playcut)
                )
            }

            let (nowPlayingItem, recentItems) = nowPlayingItemsWithArtwork.popFirst()
            let entry = NowPlayingTimelineEntry(
                nowPlayingItem: nowPlayingItem,
                recentItems: recentItems,
                family: context.family
            )

            completion(entry)
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<Entry>) -> ()) {
        let family = context.family
        PostHogSDK.shared.capture(
            "getTimeline",
            context: "NowPlayingWidget",
            additionalData: ["family" : String(describing: family)]
        )

        Task {
            var nowPlayingItemsWithArtwork: [NowPlayingItem] = []

            if context.isPreview {
                nowPlayingItemsWithArtwork = [
                    NowPlayingItem.placeholder,
                    NowPlayingItem.placeholder,
                    NowPlayingItem.placeholder,
                    NowPlayingItem.placeholder,
                ]
            } else {
                let playlistService = PlaylistService()
                let artworkService = ArtworkService()

                let playlist = await playlistService.fetchPlaylist()
                var playcuts = playlist.playcuts
                    .sorted(by: >)
                playcuts = Array(playcuts.prefix(4))

                nowPlayingItemsWithArtwork = await playcuts.asyncFlatMap { playcut in
                    NowPlayingItem(
                        playcut: playcut,
                        artwork: try? await artworkService.fetchArtwork(for: playcut)
                    )
                }
            }

            nowPlayingItemsWithArtwork.sort(by: >)
            let (nowPlayingItem, recentItems) = nowPlayingItemsWithArtwork.popFirst()

            let entry = NowPlayingTimelineEntry(
                nowPlayingItem: nowPlayingItem,
                recentItems: recentItems,
                family: context.family
            )

            // Schedule the next update
            let fiveMinutes = Date.now.addingTimeInterval(5 * 60)
            let timeline = Timeline(entries: [entry], policy: .after(fiveMinutes))
            completion(timeline)
        }
    }
}

struct NowPlayingTimelineEntry: TimelineEntry {
    let date: Date = Date(timeIntervalSinceNow: 1)
    let artist: String
    let songTitle: String
    let artwork: Image?
    let recentItems: [NowPlayingItem]
    let family: WidgetFamily

    init(nowPlayingItem: NowPlayingItem, recentItems: [NowPlayingItem], family: WidgetFamily) {
        self.artist = nowPlayingItem.playcut.artistName
        self.songTitle = nowPlayingItem.playcut.songTitle
        
        if let artwork = nowPlayingItem.artwork {
            self.artwork = Image(uiImage: artwork)
        } else {
            self.artwork = nil
        }
        
        self.recentItems = recentItems
        self.family = family
    }
    
    static func placeholder(family: WidgetFamily) -> Self {
        NowPlayingTimelineEntry(
            nowPlayingItem: NowPlayingItem.placeholder,
            recentItems: [.placeholder, .placeholder, .placeholder],
            family: family
        )
    }
}

protocol NowPlayingWidgetEntryView: View {
    associatedtype Artwork: View
    
    var entry: NowPlayingTimelineEntry { get }
    var artwork: Artwork { get }
}

extension NowPlayingWidgetEntryView {
    var artwork: some View {
        Group {
            if let artwork = entry.artwork {
                artwork
                    .resizable()
                    .frame(maxWidth: 800, maxHeight: 800)
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(5)
            } else {
                Image.logo
            }
        }
    }
    
    @ViewBuilder
    var background: some View {
        Image.background
        
        Color.darken
            .ignoresSafeArea()
    }
}

struct SmallNowPlayingWidgetEntryView: NowPlayingWidgetEntryView {
    var entry: Provider.Entry
    
    var body: some View {
        ZStack(alignment: .leading) {
            background
            
            VStack(alignment: .leading) {
                self.artwork
                
                Text(entry.artist)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text(entry.songTitle)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                PlayButton()
                    .background(Capsule().fill(Color.red))
                    .clipped()
            }
        }
        .containerBackground(Color.clear, for: .widget)
        .safeAreaPadding()
    }
}

struct PlayButton: View {
    @AppStorage("isPlaying", store: .wxyc)
    var isPlaying: Bool = UserDefaults.wxyc.bool(forKey: "isPlaying")
    
    var body: some View {
        Button(intent: intent) {
            Image(systemName: resourceName)
                .foregroundStyle(.white)
                .font(.caption)
                .fontWeight(.bold)
                .invalidatableContent()
            Text(text)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .invalidatableContent()
        }
        .onTapGesture {
            PostHogSDK.shared.capture(
                "play button tapped",
                context: "NowPlayingWidget"
            )
        }
    }
    
    var intent: any SystemIntent {
        ToggleWXYC()
    }
    
    var text: String {
        isPlaying ? "Pause" : "Play"
    }
    
    var resourceName: String {
        isPlaying ? "pause.fill" : "play.fill"
    }
}

struct MediumNowPlayingWidgetEntryView: NowPlayingWidgetEntryView {
    var entry: NowPlayingTimelineEntry
    
    var body: some View {
        ZStack(alignment: .leading) {
            background
            
            HStack(alignment: .center) {
                self.artwork
                    .cornerRadius(10)
                    .aspectRatio(contentMode: .fit)
                
                VStack(alignment: .leading) {
                    Text(entry.artist)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(entry.songTitle)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    PlayButton()
                        .background(Capsule().fill(Color.red))
                        .clipped()
                    
                }
            }
        }
        .safeAreaPadding()
        .containerBackground(Color.clear, for: .widget)
    }
}

struct Header: View {
    var entry: NowPlayingTimelineEntry
    
    var body: some View {
        HStack(alignment: .center) {
            ZStack {
                Group {
                    if let artwork = entry.artwork {
                        artwork
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(10)
                            .frame(width: 100, height: 100)
                    } else {
                        Image.logo
                            .frame(width: 100, height: 100, alignment: .leading)
                    }
                }
            }
            
            VStack(alignment: .leading) {
                Text(entry.artist)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text(entry.songTitle)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                                
                PlayButton()
                    .background(Capsule().fill(Color.red))
                    .clipped()
                    .frame(alignment: .bottom)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct RecentlyPlayedRow: View {
    let nowPlayingItem: NowPlayingItem
    let imageDimension: CGFloat = 45.0
    
    init(nowPlayingItem: NowPlayingItem) {
        self.nowPlayingItem = nowPlayingItem
    }
    
    var body: some View {
        HStack(alignment: .center) {
            artwork
            
            VStack(alignment: .leading) {
                Text(nowPlayingItem.playcut.artistName)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text(nowPlayingItem.playcut.songTitle)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.lighten)
        .cornerRadius(10)
        .clipped()
    }
    
    var artwork: some View {
        Group {
            if let artwork = nowPlayingItem.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(10)
                    .clipped()
                    .frame(
                        width: imageDimension,
                        height: imageDimension,
                        alignment: .leading
                    )
                    .padding(5)
            } else {
                Rectangle()
                    .fill(.darken)
                    .cornerRadius(10)
                    .clipped()
                    .frame(
                        width: imageDimension,
                        height: imageDimension,
                        alignment: .leading
                    )
                    .padding(5)
            }
        }
    }
}

struct LargeNowPlayingWidgetEntryView: NowPlayingWidgetEntryView {
    let entry: NowPlayingTimelineEntry
    
    init(entry: NowPlayingTimelineEntry) {
        self.entry = entry
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            background
            
            VStack(alignment: .leading, spacing: 10) {
                Spacer()
                
                Header(entry: entry)

                Text("Recently Played")
                    .font(.body.smallCaps().bold())
                    .foregroundStyle(.white)
                    .frame(maxHeight: .infinity, alignment: .top)
                
                ForEach(entry.recentItems, id: \.playcut.chronOrderID) { nowPlayingItem in
                    RecentlyPlayedRow(nowPlayingItem: nowPlayingItem)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                
                Spacer()
            }
            .safeAreaPadding()
        }
        .containerBackground(Color.clear, for: .widget)
    }
}

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
        .contentMarginsDisabled()
    }
}

@main
struct NowPlayingWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingControl()
        NowPlayingWidget()
    }
}

@available(iOSApplicationExtension 18.0, *)
struct NowPlayingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "org.wxyc.control", intent: PlayWXYC.self) { config in
            ControlWidgetButton(action: config) {
                Image(systemName: "pause.fill")
                    .foregroundStyle(.white)
                    .font(.caption)
                    .fontWeight(.bold)
            }
        }
    }
}

extension NowPlayingItem {
    static var placeholder: NowPlayingItem {
        // Make NowPlayingItem circular iterator instead of Playcut
        return NowPlayingItem(
            playcut: playcutsIterator.next()!
        )
    }
    
    static var playcutsIterator = CircularIterator(playcuts)
    
    private static var _i: UInt64 = 0
    private static var i: UInt64 {
        defer { _i += 1 }
        return _i
    }
    
    static var playcuts = [
        Playcut(
            id: i,
            hour: i,
            chronOrderID: i,
            songTitle: "VI Scose Poise",
            labelName: nil,
            artistName: "Autechre",
            releaseTitle: "Confield"
        ),
        Playcut(
            id: i,
            hour: i,
            chronOrderID: i,
            songTitle: "Belleville",
            labelName: nil,
            artistName: "Laurel Halo",
            releaseTitle: "Atlas"
        ),
        Playcut(
            id: i,
            hour: i,
            chronOrderID: i,
            songTitle: "Bismillahi 'Rrahmani 'Rrahim",
            labelName: nil,
            artistName: "Harold Budd",
            releaseTitle: "Pavilion of Dreams"
        ),
        Playcut(
            id: i,
            hour: i,
            chronOrderID: i,
            songTitle: "Guinnevere",
            labelName: nil,
            artistName: "Miles Davis",
            releaseTitle: "Bitches Brew"
        )
    ]
    
    struct CircularIterator<Element>: IteratorProtocol {
        let sequence: any Sequence<Element>
        private var iterator: any IteratorProtocol<Element>
        
        init(_ sequence: any Sequence<Element>) {
            self.sequence = sequence
            self.iterator = sequence.makeIterator()
        }
        
        mutating func next() -> Element? {
            if let next = iterator.next() {
                return next
            } else {
                iterator = sequence.makeIterator()
                return iterator.next()
            }
        }
    }
}

extension RangeReplaceableCollection {
    mutating func popFirst() -> (Element, Self) {
        let first = removeFirst()
        return (first, self)
    }
}

extension Image {
    static var logo: some View {
        ZStack {
            Rectangle()
                .background(.white)
                .background(.ultraThinMaterial)
                .opacity(0.2)
            Image(ImageResource(name: "logo_small", bundle: .main))
                .renderingMode(.template)
                .resizable()
                .foregroundStyle(.white)
                .opacity(0.75)
                .blendMode(.colorDodge)
                .scaleEffect(0.85)
        }
        .aspectRatio(contentMode: .fit)
        .cornerRadius(10)
        .clipped()
    }
    
    static var background: some View {
        ZStack {
            Image(ImageResource(name: "background", bundle: .main))
                .resizable()
                .opacity(0.95)
            Rectangle()
                .foregroundStyle(.gray)
                .background(.gray)
                .background(.ultraThickMaterial)
                .opacity(0.18)
                .blendMode(.colorBurn)
                .saturation(0)
        }
        .ignoresSafeArea()
    }
}

extension Collection where Self: Sendable {
    public func asyncFlatMap<T>(_ transform: sending @escaping @isolated(any) (Element) async -> T) async -> [T] {
        await withTaskGroup(of: T.self) { group in
            for element in self {
                group.addTask {
                    await transform(element)
                }
            }
            
            var results: [T] = []
            for await result in group {
                results.append(result)
            }
            
            return results
        }
    }
}

extension ShapeStyle where Self == Color {
    static var darken: Color {
        Color(white: 0, opacity: 0.25)
    }

    static var lighten: Color {
        Color(white: 1, opacity: 0.25)
    }
}

#Preview(as: .systemLarge) {
    NowPlayingWidget()
} timeline: {
    NowPlayingTimelineEntry.placeholder(family: .systemLarge)
}
