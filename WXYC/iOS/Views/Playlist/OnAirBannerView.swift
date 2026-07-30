//
//  OnAirBannerView.swift
//  WXYC
//
//  Persistent banner that promotes the current DJ's sign-on to the top of the playlist.
//
//  Created by Jake Bromberg on 06/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreText
import Foundation
import Playlist
import SwiftUI
import WXUI

/// A banner surfacing the DJ currently on the air (or "Auto DJ") at the top of the playlist.
///
/// A white "ON AIR" eyebrow with a themed live indicator sits above the DJ's handle, rendered
/// directly over the wallpaper with no card chrome. The indicator color/glow, the handle's SF
/// Pro variable-font axes, and the vertical spacing all come from ``OnAirBannerTheme`` so the
/// debug controls can tune them live; ``OnAirBannerTheme/default`` is the shipping look.
struct OnAirBannerView: View {
    /// The DJ's name, e.g. "DJ HOUNDSTOOTH", or "Auto DJ" when nobody is signed on.
    let headline: String

    /// Tunable design parameters: indicator color/glow, handle font variation, and spacing.
    var theme: OnAirBannerTheme = .default

    /// When set, tapping the banner invokes this — used to present the debug controls sheet.
    /// `nil` in release, so the banner is inert.
    var onDebugTapped: (() -> Void)? = nil

    /// When set, a "say hi" chip is shown beside the handle; tapping it invokes
    /// this to present the Request Line. `nil` when the booth isn't inviting
    /// conversation (automation, or an unnamed/unknown DJ), so the chip is a
    /// presence indicator — it never appears on a guess.
    var onRequestLine: (() -> Void)? = nil

    /// The point size of the DJ handle. Fixed (not Dynamic Type) so the handle
    /// yields to a long name by narrowing its width axis, never by shrinking.
    private static let handleFontSize: CGFloat = 24

    /// A hair of slack subtracted from the measured available width so sub-pixel
    /// differences between the CoreText measurement and SwiftUI's line-breaking
    /// can't push the last glyph onto a second line.
    private static let fitSafetyInset: CGFloat = 3

    /// The width available to the handle, captured from layout — the banner row
    /// minus the say-hi chip and its gap. Drives the adaptive width solve.
    @State private var handleAvailableWidth: CGFloat = 0

    /// When the current one-shot grade wave began, or `nil` when the handle is at
    /// rest. While set, the handle renders per-letter and animates; the stop task
    /// clears it once the wave completes so the resting handle costs nothing.
    @State private var waveStart: Date?

    /// Identifies the active wave run so a stale stop task can't clear a newer
    /// replay's animation out from under it.
    @State private var waveRunID = 0

    /// The pending "return to rest" task for the active wave, cancelled when a new
    /// wave supersedes it.
    @State private var waveStopTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow

            // Handle and chip share one row, center-aligned, so the chip lines up
            // with the DJ handle — not with the taller eyebrow-plus-handle block.
            HStack(alignment: .center, spacing: 8) {
                // The handle greedily fills the row; the chip is a fixed trailing
                // element (no Spacer — a Spacer would compete with the handle's
                // maxWidth and corrupt the width we measure for it).
                handleTapTarget
                    // Measure the exact space the handle may occupy — the row
                    // minus the chip and the 8pt gap. The frame fills that space
                    // regardless of the handle's own (condensed) width, so there's
                    // no feedback into the width solve.
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { newWidth in
                        handleAvailableWidth = newWidth
                    }

                if let onRequestLine {
                    RequestLineChip(action: onRequestLine, tint: .green.opacity(theme.requestLineTintOpacity))
                }
            }
            .padding(.top, theme.onAirSpacing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("On air. \(headline)")
    }

    /// The white "ON AIR" eyebrow with its themed live indicator, on its own row
    /// above the handle so it doesn't skew the chip's vertical alignment.
    private var eyebrow: some View {
        HStack(spacing: 8) {
            OnAirIndicator(size: 8, color: theme.indicatorColor, blurRadius: theme.indicatorBlurRadius)

            Text("ON AIR")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(.white)
        }
    }

    /// The DJ handle, filling the space left of the chip, wrapped in the debug
    /// tap target when one is provided. The debug tap covers only the handle so
    /// the say-hi chip beside it stays a separate control (no Button-in-Button).
    @ViewBuilder
    private var handleTapTarget: some View {
        if let onDebugTapped {
            Button(action: onDebugTapped) { handle }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            handle
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var handle: some View {
        handleContent
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .lineSpacing(theme.handleLineSpacing)
            // One line when condensing; a wrap is the last resort for a handle
            // so long it overflows even at the width floor.
            .lineLimit(theme.adaptiveWidth ? 2 : nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Play the wave once when the handle first appears and again whenever
            // it changes to a new DJ. `waveReplayToken` is the debug replay hook.
            .onAppear { playWave() }
            .onChange(of: headline) { playWave() }
            .onChange(of: theme.waveReplayToken) { playWave() }
    }

    /// The handle's letters: a single `Text` at rest, or a per-letter row driven
    /// by the grade wave while it plays. The wave touches only the metric-neutral
    /// grade axis, so both paths lay out at the same width — the resting `Text`
    /// keeps SwiftUI's kerning and wrapping, and the animated row pins each letter
    /// to its kerned advance so it matches that width and nothing reflows when the
    /// two swap. Advances are measured once here, not per frame, since grade
    /// leaves them unchanged.
    @ViewBuilder
    private var handleContent: some View {
        if theme.waveEnabled, let waveStart {
            let width = effectiveWidthAxis
            let characters = Array(headline.uppercased())
            let advances = handleCharacterAdvances(for: headline.uppercased(), font: handleCTFont(width: width))
            TimelineView(.animation) { context in
                wavingHandle(
                    characters: characters,
                    widthAxis: width,
                    advances: advances,
                    progress: waveProgress(now: context.date, start: waveStart)
                )
            }
        } else {
            Text(headline)
                .font(handleFont)
        }
    }

    /// The handle rendered one `Text` per character, each at its own grade for the
    /// given wave `progress`. Every letter shares `widthAxis` (and every other
    /// axis) so only grade differs, and each cell is pinned to its kerned
    /// `advance`, so the row's total width equals the resting handle's — the wave
    /// can't make it breathe. When advances are unavailable (a handle that doesn't
    /// shape one glyph per character), the cells fall back to their natural widths.
    private func wavingHandle(
        characters: [Character],
        widthAxis: Double,
        advances: [CGFloat]?,
        progress: Double
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(characters.indices, id: \.self) { index in
                Text(String(characters[index]))
                    .font(Font(handleCTFont(
                        width: widthAxis,
                        grade: wave.grade(
                            characterIndex: index,
                            count: characters.count,
                            progress: progress
                        )
                    )))
                    // Draw the glyph at its natural size, but reserve exactly its
                    // kerned advance for layout, so a grade-thinned letter can't
                    // shrink its cell and shift the row.
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: advances.map { $0[index] }, alignment: .leading)
            }
        }
    }

    /// The grade wave configured from the theme, resting at the handle's own grade
    /// so the animation begins and ends at the normal display look.
    private var wave: HandleGradeWave {
        HandleGradeWave(
            baseGrade: theme.handleVariation.grade,
            depth: theme.waveDepth,
            crestHalfWidth: theme.waveCrestHalfWidth,
            repetitions: theme.waveRepetitions,
            spacing: theme.waveSpacing
        )
    }

    /// The full run time of the wave: each crest's sweep stays
    /// ``OnAirBannerTheme/waveDuration`` long, and the crest train spans
    /// ``HandleGradeWave/normalizedSpan`` sweeps — so extra repetitions lengthen
    /// the animation while tighter spacing (overlap) shortens it.
    private var waveTotalDuration: TimeInterval {
        theme.waveDuration * wave.normalizedSpan
    }

    /// Elapsed fraction of the whole (possibly repeating) wave, clamped to `0...1`.
    /// The wave model folds this into the individual sweeps.
    private func waveProgress(now: Date, start: Date) -> Double {
        guard waveTotalDuration > 0 else { return 1 }
        return min(max(now.timeIntervalSince(start) / waveTotalDuration, 0), 1)
    }

    /// Starts the one-shot wave: mark it running so the handle renders per-letter,
    /// then schedule a return to the resting `Text` once the duration elapses.
    /// A no-op when the wave is disabled or has no duration.
    private func playWave() {
        guard theme.waveEnabled, theme.waveDuration > 0 else {
            waveStart = nil
            return
        }
        waveRunID += 1
        let runID = waveRunID
        waveStart = .now
        waveStopTask?.cancel()
        waveStopTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(waveTotalDuration))
            // Only retire this run — a newer replay may already be playing.
            if waveRunID == runID { waveStart = nil }
        }
    }

    /// The DJ handle font, rendered across SF Pro's four variable-font axes from
    /// the theme — with the width axis narrowed by ``effectiveWidthAxis`` so a
    /// long handle stays on one line at full point size.
    private var handleFont: Font {
        Font(handleCTFont(width: effectiveWidthAxis))
    }

    /// The width axis to render the handle at: the theme's base (expanded) width
    /// when the name fits or adaptive fitting is off, otherwise the largest axis
    /// down to ``OnAirBannerTheme/handleWidthFloor`` at which it fits one line.
    private var effectiveWidthAxis: Double {
        guard theme.adaptiveWidth, handleAvailableWidth > 0 else {
            return theme.handleVariation.width
        }
        return fittedWidthAxis(
            availableWidth: handleAvailableWidth - Self.fitSafetyInset,
            baseAxis: theme.handleVariation.width,
            floor: theme.handleWidthFloor,
            measure: { handleLineWidth(widthAxis: $0) }
        )
    }

    /// The rendered one-line width of the (uppercased) handle at a candidate
    /// width axis, measured with CoreText — no SwiftUI layout pass required.
    private func handleLineWidth(widthAxis: Double) -> CGFloat {
        let font = handleCTFont(width: widthAxis)
        let attributed = NSAttributedString(
            string: headline.uppercased(),
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// A `CTFont` for the handle at the given width axis (and, for the wave, an
    /// overridden grade), holding the theme's other axes fixed.
    ///
    /// SwiftUI exposes only discrete `Font.Weight`, so we set the raw
    /// `kCTFontVariationAttribute` on a copy of the system font to drive weight,
    /// width, optical size, and grade continuously, then bridge to SwiftUI.
    ///
    /// - Parameter grade: A per-letter grade for the wave; `nil` keeps the theme's
    ///   grade (the resting look and the width-fit measurement).
    private func handleCTFont(width: Double, grade: Double? = nil) -> CTFont {
        var variation = theme.handleVariation
        variation.width = width
        if let grade { variation.grade = grade }
        let base = CTFontCreateUIFontForLanguage(.system, Self.handleFontSize, nil)
            ?? CTFontCreateWithName("SFPro-Regular" as CFString, Self.handleFontSize, nil)
        let attributes: [CFString: Any] = [kCTFontVariationAttribute: variation.variationDictionary]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateCopyWithAttributes(base, Self.handleFontSize, nil, descriptor)
    }
}

/// The "say hi" affordance shown beside a named DJ's handle: a compact,
/// glass-capsule button that opens the Request Line. Its presence is the signal
/// — it appears only when a human is on the board and the booth is reachable.
struct RequestLineChip: View {
    let action: () -> Void

    /// The glass tint. Its opacity controls how transparent the capsule
    /// background is (from solid at 1.0 to clear glass at 0) — the text and icon
    /// keep their own opaque `.foregroundStyle(.white)`, so they're unaffected.
    var tint: Color = .green

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Request")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .textCase(.uppercase)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            // Green ties the chip to the live "ON AIR" indicator and the phone /
            // call-the-booth semantics it shares; the tint's opacity is the
            // background transparency, tunable via the debug controls.
            .glassEffectClearTintedInteractiveIfAvailable(tint: tint, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Make a request to the DJ")
        .accessibilityHint("Opens the Request Line to request a song or call the booth")
        .accessibilityIdentifier("banner.requestLine")
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 24) {
            OnAirBannerView(headline: "DJ HOUNDSTOOTH", onRequestLine: {})
            OnAirBannerView(headline: "Auto DJ")
        }
        .padding()
    }
    .background(.black)
}
