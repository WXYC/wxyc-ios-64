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

final class Provider: TimelineProvider, Sendable {
    func placeholder(in context: Context) -> NowPlayingTimelineEntry {
        let nowPlayingItem = NowPlayingItem.placeholder
        
        let recentItemsWithArtwork = [
            NowPlayingItem.placeholder,
            NowPlayingItem.placeholder,
            NowPlayingItem.placeholder,
        ]
        
        return NowPlayingTimelineEntry(
            nowPlayingItem: nowPlayingItem,
            recentItems: recentItemsWithArtwork,
            family: context.family
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping @Sendable (NowPlayingTimelineEntry) -> ()) {
        let family = context.family
        PostHogSDK.shared.capture(
            "nowplayingwidget getsnapshot",
            properties: ["family" : String(describing: family)]
        )
        
        Task {
            let playlist = await PlaylistService.shared.fetchPlaylist()
            var playcuts = playlist.playcuts
                .sorted(by: >)
            playcuts = Array(playcuts.prefix(4))
            
            var nowPlayingItemsWithArtwork = await withTaskGroup(of: NowPlayingItem.self) { group -> [NowPlayingItem] in
                var results = [NowPlayingItem]()
                for playcut in playcuts {
                    group.addTask {
                        if let artwork = await ArtworkService.shared.getArtwork(for: playcut) {
                            return NowPlayingItem(playcut: playcut, artwork: artwork)
                        }
                        
                        return NowPlayingItem(playcut: playcut)
                    }
                }
                
                for await updated in group {
                    results.append(updated)
                }
                
                return results
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
            "nowplayingwidget gettimeline",
            properties: ["family" : String(describing: family)]
        )
        
        Task {
            let playlist = await PlaylistService.shared.fetchPlaylist()
            var playcuts = playlist.playcuts
                .sorted(by: >)
            playcuts = Array(playcuts.prefix(4))
            
            var nowPlayingItemsWithArtwork: [NowPlayingItem] = []
            
            if context.isPreview {
                nowPlayingItemsWithArtwork = [
                    NowPlayingItem.placeholder,
                    NowPlayingItem.placeholder,
                    NowPlayingItem.placeholder,
                    NowPlayingItem.placeholder,
                ]
            } else {
                nowPlayingItemsWithArtwork = await withTaskGroup(of: NowPlayingItem.self) { group -> [NowPlayingItem] in
                    var results = [NowPlayingItem]()
                    for playcut in playcuts {
                        group.addTask {
                            if let artwork = await ArtworkService.shared.getArtwork(for: playcut) {
                                return NowPlayingItem(playcut: playcut, artwork: artwork)
                            }
                            
                            return NowPlayingItem(playcut: playcut)
                        }
                    }
                    
                    for await updated in group {
                        results.append(updated)
                    }
                    
                    return results
                }
            }
            
            nowPlayingItemsWithArtwork.sort(by: >)
            let (nowPlayingItem, recentItems) = nowPlayingItemsWithArtwork.popFirst()
            
            let entry = NowPlayingTimelineEntry(
                nowPlayingItem: nowPlayingItem,
                recentItems: Array(recentItems),
                family: context.family
            )
            
            // Schedule the next update
            let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdateDate))
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

    init(nowPlayingItem: NowPlayingItem, recentItems: [NowPlayingItem] = [], family: WidgetFamily) {
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
    
    public static func placeholder(family: WidgetFamily) -> Self {
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

extension Color {
    init(white: CGFloat, opacity: CGFloat = 1) {
        self.init(red: white, green: white, blue: white, opacity: opacity)
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
        .background(.darken)
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
                        .task {
                            print("foreach npi: \(nowPlayingItem.playcut.chronOrderID)")
                        }
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
    @Environment(\.widgetFamily) var family: WidgetFamily
    
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
    static var i: UInt64 = 0
    
    static var placeholder: NowPlayingItem {
        defer { i += 1 }
        return NowPlayingItem(
            playcut: Playcut(
                id: i,
                hour: i,
                chronOrderID: i,
                songTitle: "Chapel Hill, NC",
                labelName: nil,
                artistName: "WXYC 89.3 FM",
                releaseTitle: nil
            )
        )
    }
}

extension RangeReplaceableCollection {
    mutating func popFirst() -> (Element, Self) {
        let first = removeFirst()
        return (first, self)
    }
    
    func sorted<T: Comparable>(by keyPath: KeyPath<Element, T>, comparator: (T, T) -> Bool = (<)) -> [Element] {
        sorted { e1, e2 in
            comparator(e1[keyPath: keyPath], e2[keyPath: keyPath])
        }
    }
}

extension Image {
    static var logo: some View {
        Group {
            Rectangle()
                .background(.ultraThinMaterial)
            Image(ImageResource(name: "logo_small", bundle: .main))
                .resizable()
                .scaleEffect(0.85)
        }
        .aspectRatio(contentMode: .fit)
        .cornerRadius(10)
        .clipped()
    }
    
    static var background: some View {
        Image(ImageResource(name: "background", bundle: .main))
            .resizable()
            .background(.ultraThinMaterial)
            .ignoresSafeArea()
    }
}

extension ShapeStyle where Self == Color {
    static var darken: Color {
        Color(white: 0, opacity: 0.25)
    }
}

#Preview(as: .systemLarge) {
    NowPlayingWidget()
} timeline: {
    NowPlayingTimelineEntry.placeholder(family: .systemLarge)
}
