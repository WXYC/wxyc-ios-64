//
//  TicketFeatureCTAView.swift
//  WXYC
//
//  The discovery CTA that teaches the Box Office ticket feature. It *is* a
//  ticket — it borrows the perforated ``TicketShape`` chrome and cream keepsake
//  stub — so it announces itself in its own form, stamped NEW. It sits under the
//  player like ``SiriTipView``/``ThemeTipView``: same `isVisible` + `onDismiss`
//  surface, dismissed by an X, no tap on the card. Its whole job is to explain
//  the torn stub (``OnTourRowBadge``) that touring artists already carry in the
//  feed, before the user passively encounters one. Design is the approved
//  prototype in docs/ideas/ticket-feature-cta.html.
//
//  Created by Jake Bromberg on 07/11/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import Wallpaper
import WXUI

/// A ticket-shaped announcement card teaching the Box Office ticket feature.
///
/// Purely presentational: the show/retire decision lives in
/// ``Playlist/TicketFeatureCTAPersistence`` and is evaluated by the host
/// (`PlaylistView`). This view only renders and reports its dismissal.
struct TicketFeatureCTAView: View {
    @Binding var isVisible: Bool
    private let copy: Copy
    private let onDismiss: () -> Void

    init(isVisible: Binding<Bool>, copy: Copy = .catchThemLive, onDismiss: @escaping () -> Void = { }) {
        self._isVisible = isVisible
        self.copy = copy
        self.onDismiss = onDismiss
    }

    // Ticket geometry — identical to ``BoxOfficeTicketView`` so the CTA reads as
    // the same object the feature will surface. `stubHeight` must match the
    // stub's rendered height so the notches land on the perforation.
    private let cornerRadius: CGFloat = 16
    private let stubHeight: CGFloat = 96
    private let notchRadius: CGFloat = 11

    private var ticketShape: TicketShape {
        TicketShape(cornerRadius: cornerRadius, stubHeight: stubHeight, notchRadius: notchRadius)
    }

    var body: some View {
        VStack(spacing: 0) {
            ticketBody
            ticketStub
        }
        // Warm smoked glass over the blurred wallpaper: the same MaterialView the
        // real ticket uses, an amber-brown cast so the announcement reads as its
        // own warmer object rather than a neutral section, then real Liquid Glass
        // on top (iOS 26+, `.ultraThinMaterial` fallback) so it carries the same
        // material language as ``BoxOfficeTicketView`` and every other glass
        // surface. The warm cast sits behind the clear glass, so the glass
        // refracts it rather than washing it out.
        .background {
            ZStack {
                MaterialView()
                LinearGradient(
                    colors: [Palette.bodyTop, Palette.bodyBottom],
                    startPoint: .top, endPoint: .bottom
                )
                Rectangle()
                    .fill(.clear)
                    .glassEffectClearIfAvailable(in: Rectangle())
            }
        }
        .clipShape(ticketShape)
        .overlay { ticketShape.stroke(Palette.amberLine, lineWidth: 1) }
        .shadow(color: Palette.glow, radius: 16, x: 0, y: 8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity),
            removal: .scale(scale: 0.95).combined(with: .opacity)
        ))
    }

    // MARK: - Body

    private var ticketBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Text(copy.headline)
                .font(.system(size: 25, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.top, 14)
            Text(copy.subtitle)
                .font(.footnote)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            howLine
                .padding(.top, 13)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 20, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.amber)
                Text("NEW")
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
                    .kerning(1.6)
                    .foregroundStyle(Palette.amberInk)
            }
            Spacer(minLength: 8)
            dismissButton
        }
    }

    private var dismissButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.25)) {
                isVisible = false
            }
            onDismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.65))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
    }

    /// The small monospace "how" line — teaches the gesture without turning the
    /// headline into an instruction.
    private var howLine: some View {
        HStack(spacing: 7) {
            Image(systemName: "ticket")
                .font(.system(size: 12, weight: .semibold))
            Text("Watch for the stub in your feed")
                .font(.system(.caption2, design: .monospaced))
                .kerning(0.4)
        }
        .foregroundStyle(Palette.amberInk)
    }

    // MARK: - Stub (cream keepsake + NEW stamp)

    private var ticketStub: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("ADMIT ONE")
                    .font(.caption).fontWeight(.heavy)
                    .kerning(1.4)
                    .foregroundStyle(Palette.stubAccent)
                Text("SHOWS NEAR YOU\nNOW IN THE APP")
                    .font(.system(.caption2, design: .monospaced))
                    .kerning(0.8)
                    .foregroundStyle(Palette.stubFaint)
            }
            Spacer(minLength: 0)
            newStamp
        }
        .padding(.horizontal, 18)
        .frame(height: stubHeight)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Palette.stubTop, Palette.stubBottom],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(alignment: .top) {
            DashedLine(approximateSegment: 5)
                .stroke(Palette.perforation, style: StrokeStyle(lineWidth: 2))
                .frame(height: 2)
        }
    }

    /// The rubber-stamp "NEW / FEATURE" roundel — the CTA flags itself where the
    /// real ticket prints the show's date.
    private var newStamp: some View {
        VStack(spacing: 3) {
            Text("NEW")
                .font(.system(size: 19, weight: .heavy))
                .kerning(1)
            Text("FEATURE")
                .font(.system(size: 7, design: .monospaced))
                .kerning(2)
                .foregroundStyle(Palette.stampFaint)
        }
        .foregroundStyle(Palette.stamp)
        .frame(width: 66, height: 66)
        .overlay(Circle().stroke(Palette.stamp.opacity(0.55), lineWidth: 2))
        .overlay(Circle().inset(by: 4).stroke(Palette.stampInner, lineWidth: 1))
        .rotationEffect(.degrees(-9))
        .accessibilityHidden(true)
    }
}

// MARK: - Copy

extension TicketFeatureCTAView {
    /// The card's changeable words. The body leads with the reward; the "how"
    /// line stays constant. Three variants were prototyped — the app ships
    /// ``catchThemLive``; the others exist for side-by-side preview.
    struct Copy: Sendable, Equatable {
        let headline: String
        let subtitle: String

        /// Lead with the payoff — names the reward first (shipped).
        static let catchThemLive = Copy(
            headline: "Catch them live.",
            subtitle: "When an artist you hear is playing around the Triangle, a stub appears under their track — tap it for the full ticket."
        )

        /// Lead with the marker — teaches the visual cue the feed already shows.
        static let stubMeansInTown = Copy(
            headline: "A stub means they're in town.",
            subtitle: "Tracks marked with a ticket stub have a show near you."
        )

        /// Lead with the locality — most specific to WXYC's world.
        static let playingTheTriangle = Copy(
            headline: "They're playing the Triangle.",
            subtitle: "When someone you hear has a show near you, you'll find it in the track."
        )
    }
}

// MARK: - Palette

/// The CTA's warm palette. Unlike ``BoxOfficeTicketView``'s single-hue amber
/// family, this mixes amber, cream, and brown that don't share a hue, so the
/// tokens read most clearly as their source hex rather than as HSL. Trailing hex
/// is the prototype value. File-private so it doesn't leak app-wide.
private enum Palette {
    // Warm smoked-glass body — rgba over the blurred wallpaper.
    static let bodyTop = Color(red: 48 / 255, green: 32 / 255, blue: 20 / 255).opacity(0.52) // #302014
    static let bodyBottom = Color(red: 26 / 255, green: 17 / 255, blue: 11 / 255).opacity(0.58) // #1A110B

    static let amber = Color(red: 1, green: 137 / 255, blue: 64 / 255) // #FF8940
    static let amberInk = Color(red: 1, green: 199 / 255, blue: 154 / 255) // #FFC79A
    static let amberLine = Color(red: 1, green: 137 / 255, blue: 64 / 255).opacity(0.55) // amber @55%
    static let glow = Color(red: 1, green: 137 / 255, blue: 64 / 255).opacity(0.35)

    static let inkDim = Color.white.opacity(0.72)

    // Cream keepsake stub + brown ink.
    static let stubTop = Color(red: 243 / 255, green: 234 / 255, blue: 215 / 255) // #F3EAD7
    static let stubBottom = Color(red: 234 / 255, green: 221 / 255, blue: 194 / 255) // #EADDC2
    static let stubAccent = Color(red: 181 / 255, green: 96 / 255, blue: 31 / 255) // #B5601F
    static let stubFaint = Color(red: 110 / 255, green: 83 / 255, blue: 52 / 255) // #6E5334
    static let perforation = Color(red: 150 / 255, green: 96 / 255, blue: 40 / 255).opacity(0.5) // #966028 @50%

    // NEW/FEATURE stamp.
    static let stamp = Color(red: 181 / 255, green: 96 / 255, blue: 31 / 255) // #B5601F
    static let stampFaint = Color(red: 138 / 255, green: 102 / 255, blue: 54 / 255) // #8A6636
    static let stampInner = Color(red: 181 / 255, green: 96 / 255, blue: 31 / 255).opacity(0.28)
}

// MARK: - Previews

#Preview("Catch them live") {
    TicketFeatureCTAPreviewStage(copy: .catchThemLive)
}

#Preview("A stub means they're in town") {
    TicketFeatureCTAPreviewStage(copy: .stubMeansInTown)
}

#Preview("They're playing the Triangle") {
    TicketFeatureCTAPreviewStage(copy: .playingTheTriangle)
}

/// Puts the CTA on a WXYC-like gradient so the glass, the notch cut-throughs, and
/// the cream stub read the way they will over a real wallpaper.
private struct TicketFeatureCTAPreviewStage: View {
    let copy: TicketFeatureCTAView.Copy

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 48 / 255, green: 60 / 255, blue: 114 / 255), // #303C72
                    Color(red: 175 / 255, green: 62 / 255, blue: 121 / 255), // #AF3E79
                    Color(red: 182 / 255, green: 73 / 255, blue: 73 / 255), // #B64949
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            TicketFeatureCTAView(isVisible: .constant(true), copy: copy)
                .padding()
        }
    }
}
