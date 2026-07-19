//
//  TicketFeatureCTAView.swift
//  WXYC
//
//  The discovery CTA that teaches the Box Office ticket feature. It *is* a
//  ticket — it borrows the perforated ``TicketShape`` chrome and the theme-tinted
//  glass of ``BoxOfficeTicketView`` (a deep-tinted body over a near-clear
//  "keepsake" stub) — so it announces itself in its own form, stamped NEW. It
//  sits under the player like ``SiriTipView``/``ThemeTipView``: same `isVisible`
//  + `onDismiss` surface, dismissed by an X, no tap on the card. Its whole job is
//  to explain the torn stub (``OnTourRowBadge``) that touring artists already
//  carry in the feed, before the user passively encounters one. Layout follows
//  the prototype in docs/ideas/ticket-feature-cta.html; the theme-tinted glass
//  follows docs/ideas/ticket-tinted-glass.html.
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
/// (`PlaylistView`), which also passes the theme-derived ``colors``. This view
/// only renders and reports its dismissal.
struct TicketFeatureCTAView: View {
    @Binding var isVisible: Bool
    private let copy: Copy
    private let colors: TicketColors
    private let onDismiss: () -> Void

    init(
        isVisible: Binding<Bool>,
        colors: TicketColors,
        copy: Copy = .catchThemLive,
        onDismiss: @escaping () -> Void = { }
    ) {
        self._isVisible = isVisible
        self.colors = colors
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
        // Same two-tone-under-one-glass structure as ``BoxOfficeTicketView``: a
        // deep frosted accent tint over the MaterialView for the body, a near-clear
        // keepsake window (no MaterialView) for the stub, and one clear glass layer
        // over both — so the seam stays a single dashed line and the perforation
        // notches punch clean through to the wallpaper.
        .background {
            ZStack {
                VStack(spacing: 0) {
                    ZStack {
                        MaterialView()
                        LinearGradient(
                            colors: [colors.bodyTopColor, colors.bodyBottomColor],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                    LinearGradient(
                        colors: [colors.stubTopColor, colors.stubBottomColor],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: stubHeight)
                }
                Rectangle()
                    .fill(.clear)
                    .glassEffectClearIfAvailable(in: Rectangle())
            }
        }
        .clipShape(ticketShape)
        .overlay { ticketShape.stroke(colors.edgeColor, lineWidth: 1) }
        // A tight, dark depth shadow like the real ticket — deliberately NOT a wide
        // glow. A large blurred shadow would bleed into the concave perforation
        // notches, tinting those cutouts instead of letting the wallpaper show
        // clean through them.
        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
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
            Text(copy.subtitle)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            howLine
                .padding(.top, 13)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 20, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The headline sits where a "NEW" badge used to — it *is* the card's flag now,
    /// with the dismiss button pinned to the top-right corner.
    private var header: some View {
        HStack(alignment: .top) {
            Text(copy.headline)
                .font(.system(size: 25, weight: .heavy))
                .foregroundStyle(.white)
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
        .foregroundStyle(colors.accentInkColor)
    }

    // MARK: - Stub (near-clear keepsake + NEW stamp)

    private var ticketStub: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("ADMIT ONE")
                    .font(.caption).fontWeight(.heavy)
                    .kerning(1.4)
                    .foregroundStyle(colors.stubInkColor)
                Text("SHOWS NEAR YOU\nNOW IN THE APP")
                    .font(.system(.caption2, design: .monospaced))
                    .kerning(0.8)
                    .foregroundStyle(colors.stubFaintColor)
            }
            Spacer(minLength: 0)
            newStamp
        }
        .padding(.horizontal, 18)
        .frame(height: stubHeight)
        .frame(maxWidth: .infinity)
        // No background of its own — the near-clear stub tint and the shared glass
        // come from `body`. Ink is the contrast-floored `stubInk` so it reads over
        // the keepsake window on any wallpaper. The dashed line marks the seam.
        .overlay(alignment: .top) {
            DashedLine(approximateSegment: 5)
                .stroke(colors.perforationColor, style: StrokeStyle(lineWidth: 2))
                .frame(height: 2)
        }
    }

    /// The rubber-stamp "NEW / FEATURE" roundel — the CTA flags itself where the
    /// real ticket prints the show's date. Inked in the contrast-floored `stubInk`
    /// so it reads on the keepsake stub over any wallpaper.
    private var newStamp: some View {
        VStack {
            Text("NEW")
                .font(.system(size: 19, weight: .heavy))
                .kerning(1)
            Text("FEATURE")
                .font(.system(size: 7, design: .monospaced))
                .kerning(2)
                .foregroundStyle(colors.stubFaintColor)
        }
        .foregroundStyle(colors.stubInkColor)
        .frame(width: 66, height: 66)
        .overlay(Circle().stroke(colors.stubInkColor.opacity(0.55), lineWidth: 2))
        .overlay(Circle().inset(by: 4).stroke(colors.stubFaintColor.opacity(0.5), lineWidth: 1))
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

#Preview("Theme · WXYC 1983 (amber, dark wall)") {
    TicketFeatureCTAPreviewStage(copy: .catchThemLive, colors: .previewWXYC1983, lightWallpaper: false)
}

#Preview("Theme · Windowlight (low-sat, light wall)") {
    TicketFeatureCTAPreviewStage(copy: .catchThemLive, colors: .previewWindowlight, lightWallpaper: true)
}

/// Puts the CTA on a stand-in wallpaper so the glass, the notch cut-throughs, and
/// the near-clear stub read the way they will over a real wallpaper. The backdrop
/// tracks the theme's foreground (light wallpaper for `.dark` themes, dark for
/// `.light`) so the contrast-floored stub ink is judged on the right surface.
private struct TicketFeatureCTAPreviewStage: View {
    let copy: TicketFeatureCTAView.Copy
    var colors: TicketColors = .previewPlasticPulse
    var lightWallpaper: Bool = true

    var body: some View {
        ZStack {
            (lightWallpaper ? Self.lightBackdrop : Self.darkBackdrop)
                .ignoresSafeArea()
            TicketFeatureCTAView(isVisible: .constant(true), colors: colors, copy: copy)
                .padding()
        }
    }

    /// Dark stand-in wallpaper for `.light`-foreground themes.
    static let darkBackdrop = LinearGradient(
        colors: [
            Color(red: 48 / 255, green: 60 / 255, blue: 114 / 255), // #303C72
            Color(red: 175 / 255, green: 62 / 255, blue: 121 / 255), // #AF3E79
            Color(red: 182 / 255, green: 73 / 255, blue: 73 / 255), // #B64949
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Light stand-in wallpaper for `.dark`-foreground themes (the common case).
    static let lightBackdrop = LinearGradient(
        colors: [
            Color(red: 0.80, green: 0.86, blue: 0.95),
            Color(red: 0.86, green: 0.82, blue: 0.93),
            Color(red: 0.95, green: 0.86, blue: 0.80),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// Authored ticket samples so previews match on-device, now that the palette is
/// fully authored (nothing derived from the accent).
private extension TicketColors {
    /// A teal keepsake (like The Plastic Pulse) over a dark wallpaper.
    static let previewPlasticPulse = TicketColors.resolve(
        foreground: .light,
        manifest: TicketPalette(
            bodyTop: HSBAlpha(hue: 185, saturation: 0.45, brightness: 0.32, alpha: 0.52),
            bodyBottom: HSBAlpha(hue: 190, saturation: 0.55, brightness: 0.20, alpha: 0.60),
            stub: HSBAlpha(hue: 185, saturation: 0.22, brightness: 0.92, alpha: 0.12),
            bodyInk: HSBAlpha(hue: 185, saturation: 0.20, brightness: 1.00, alpha: 1),
            edge: HSBAlpha(hue: 185, saturation: 0.50, brightness: 0.85, alpha: 0.48)
        ),
        override: nil
    )

    /// An amber keepsake (like WXYC 1983) over a dark wallpaper.
    static let previewWXYC1983 = TicketColors.resolve(
        foreground: .light,
        manifest: TicketPalette(
            bodyTop: HSBAlpha(hue: 28, saturation: 0.55, brightness: 0.34, alpha: 0.55),
            bodyBottom: HSBAlpha(hue: 24, saturation: 0.62, brightness: 0.22, alpha: 0.62),
            stub: HSBAlpha(hue: 30, saturation: 0.30, brightness: 0.92, alpha: 0.12),
            bodyInk: HSBAlpha(hue: 33, saturation: 0.30, brightness: 1.00, alpha: 1),
            edge: HSBAlpha(hue: 30, saturation: 0.55, brightness: 0.85, alpha: 0.50)
        ),
        override: nil
    )

    /// The neutral default over a *light* wallpaper — exercises the dark stub ink.
    static let previewWindowlight = TicketColors.resolve(
        foreground: .dark, manifest: nil, override: nil
    )
}
