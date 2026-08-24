//
//  NowPlayingWidget.swift
//  WXYC
//
//  Main widget definition and configuration.
//
//  Created by Jake Bromberg on 01/12/22.
//  Copyright © 2022 WXYC. All rights reserved.
//

import AppIntents
import AppServices
import Caching
import SwiftUI
import WidgetKit
import WXYCIntents

// MARK: - Widget Definitions

struct NowPlayingWidget: Widget {
    let kind: String = "NowPlayingWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: NowPlayingWidgetIntent.self, provider: Provider()) { entry in
            content(for: entry)
        }
        .configurationDisplayName("WXYC Now Playing")
        .description("See what's playing on WXYC 89.3 FM.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
    
    @ViewBuilder
    private func content(for entry: NowPlayingTimelineEntry) -> some View {
        switch entry.family {
        case .systemSmall:
            SmallNowPlayingWidgetEntryView(entry: entry)
        case .systemMedium:
            MediumNowPlayingWidgetEntryView(entry: entry)
        default:
            LargeNowPlayingWidgetEntryView(entry: entry)
        }
    }
}

// MARK: - Widget Bundle

@main
struct NowPlayingWidgetBundle: WidgetBundle {
    /// Registers this process's AppIntents dependencies before any widget
    /// timeline or intent runs. Neither `NowPlayingWidgetIntent` nor
    /// `WidgetToggleWXYC` (this file's own AppIntents surface) touch
    /// `PlaycutEntityQuery`/`ConcertEntityQuery` directly, but this process
    /// links WXYCIntents — the same module the app links — so its compiled
    /// AppIntents metadata declares support for every `AppEntity`/`EntityQuery`
    /// WXYCIntents ships, including those two. The OS can route an external
    /// resolution request (Spotlight, Siri, Shortcuts) for either entity kind
    /// to whichever qualifying process is live, which may be this widget
    /// extension rather than the app. `Singletonia` — the app's composition
    /// root — never runs in this `.appex` process, so without this call that
    /// resolution would hit an unregistered `@Dependency` and trap (#751).
    /// Registers read-only/no-op defaults here, not the app's real Spotlight
    /// indexers or network fetcher.
    ///
    /// `AppIntentsDependenciesBootstrapTests` (nested under `ReindexHandlerTests`
    /// in `AppIntentsDependenciesTests.swift`) proves `registerForWidget()`
    /// itself runs every registration without throwing. It deliberately does
    /// NOT also assert that a subsequently-constructed `PlaycutEntityQuery`
    /// resolves without trapping — that was tried and reverted: it traps
    /// ("Test crashed with signal trap") both under a bare `swift test` run
    /// and under `xcodebuild test -scheme WXYC` against a real iOS
    /// Simulator, so it isn't a host-specific artifact — see that file's
    /// header for the full account. Whether a real, OS-driven resolution
    /// (as opposed to a directly-constructed instance) succeeds is therefore
    /// unverified by any automated test here and is a manual check: install
    /// the widget on a simulator/device, add "WXYC Now Playing" to a home
    /// screen, and confirm no crash in Console — filter for "AppDependency"
    /// to catch a silent respawn.
    init() {
        AppIntentsDependencies.registerForWidget()
    }

    var body: some Widget {
        NowPlayingControl()
        NowPlayingWidget()
    }
}

// MARK: - Control Widget

struct PlaybackStateProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        UserDefaults.wxyc.bool(forKey: UserDefaults.isPlayingKey)
    }
}

struct NowPlayingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "org.wxyc.control", provider: PlaybackStateProvider()) { isPlaying in
            ControlWidgetToggle(isOn: isPlaying, action: WidgetToggleWXYC(value: !isPlaying)) {
                Label {
                    Text("WXYC")
                } icon: {
                    Image(systemName: "radio")
                }
            }
        }
        .displayName("Play WXYC")
        .description("Toggle WXYC 89.3 FM playback.")
    }
}

// MARK: - Previews

#Preview("Large", as: .systemLarge) {
    NowPlayingWidget()
} timeline: {
    NowPlayingTimelineEntry.placeholder(family: .systemLarge)
}

#Preview("Medium", as: .systemMedium) {
    NowPlayingWidget()
} timeline: {
    NowPlayingTimelineEntry.placeholder(family: .systemMedium)
}

#Preview("Small", as: .systemSmall) {
    NowPlayingWidget()
} timeline: {
    NowPlayingTimelineEntry.placeholder(family: .systemSmall)
}

// MARK: - Empty State Previews

#Preview("Empty - Large", as: .systemLarge) {
    NowPlayingWidget()
} timeline: {
    NowPlayingTimelineEntry.emptyState(family: .systemLarge)
}

#Preview("Empty - Medium", as: .systemMedium) {
    NowPlayingWidget()
} timeline: {
    NowPlayingTimelineEntry.emptyState(family: .systemMedium)
}

#Preview("Empty - Small", as: .systemSmall) {
    NowPlayingWidget()
} timeline: {
    NowPlayingTimelineEntry.emptyState(family: .systemSmall)
}
