//
//  BoxOfficeTicketView.swift
//  WXYC
//
//  The "Box Office" ticket: a keepsake surfaced on a playcut when the played
//  artist has an upcoming Triangle-area show. The body is a deep, frosted tint of
//  the theme accent; the stub is a near-clear "keepsake" window onto the
//  wallpaper. Both sit under one clear glass layer, so the perforation reads as a
//  single dashed line rather than two stacked glass rims, and two notches are cut
//  clean through to the wallpaper at the seam. Layout follows the prototype in
//  docs/ideas/touring-shows-box-office.html; the theme-tinted glass treatment
//  follows docs/ideas/ticket-tinted-glass.html.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import Playlist
import SwiftUI
import Wallpaper

/// Renders a ``Concert`` as the Box Office ticket. All display strings come
/// from ``BoxOfficeTicketPresenter`` (unit-tested); this view is pure layout.
///
/// The ticket's accent chrome and glass tint come from ``colors`` — the theme-
/// derived ``TicketColors`` the host passes down from
/// `themeConfiguration.effectiveTicketColors` — so the ticket belongs to the
/// active wallpaper rather than a fixed amber. Status semantics stay universal
/// (see the file-private `Palette`).
struct BoxOfficeTicketView: View {
    let show: Concert
    let colors: TicketColors

    /// When `true`, the outbound CTA is replaced with a gentle "this one's
    /// already happened" keepsake note. Only a shared deep link (#537) can land
    /// on a past show — the On Tour browse window is future-only — so this
    /// defaults to `false` for the in-app surfaces that only ever show it.
    var isPast: Bool = false

    @Environment(\.openURL) private var openURL

    private var presenter: BoxOfficeTicketPresenter { BoxOfficeTicketPresenter(show) }

    /// Dark, accent-tinted text for the light `accentInkColor`-filled CTA — the themed
    /// analogue of the old near-black-on-amber. The body ink is always light, so a
    /// low-brightness ink of the same hue reads on every theme.
    private var buttonInk: Color {
        let ink = colors.bodyInk.components
        return Color(hue: ink.hue / 360, saturation: min(1, ink.saturation + 0.15), brightness: 0.16)
    }

    // Ticket geometry. `stubHeight` must match the stub's rendered height so the
    // notches land exactly on the perforation between body and stub.
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
        // Two-tone under ONE glass. The body is a deep, frosted tint of the theme
        // accent (MaterialView blur + gradient); the stub omits the MaterialView so
        // it reads as a near-clear "keepsake" window onto the wallpaper, carrying
        // only a whisper of tint. A single `glassSurface` spans both, so — as before
        // — there is one specular rim at the outer edge and the seam stays a lone
        // dashed line, with the notches punched clean through to the wallpaper.
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
                glassSurface(Rectangle())
            }
        }
        .clipShape(ticketShape)
        .overlay { ticketShape.stroke(colors.edgeColor, lineWidth: 1) }
        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
        // Cancelled reads as "dead" by desaturating the whole ticket — no stamp.
        .saturation(presenter.isCancelled ? 0.4 : 1)
        .brightness(presenter.isCancelled ? -0.04 : 0)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: show.status)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Body (warm smoked glass)

    private var ticketBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Text(show.venue.name)
                .font(.title2).fontWeight(.heavy)
                .foregroundStyle(.white)
                .padding(.top, 16)
            Text(show.venue.city)
                .font(.footnote)
                .foregroundStyle(colors.accentInkColor)
                .padding(.top, 2)
            statsRow
            if let subline {
                subline
                    .font(.footnote)
                    .foregroundStyle(Palette.inkDim)
                    .padding(.top, 12)
            }
            actions
                .padding(.top, 14)
        }
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 20, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The clear frosted-glass layer for the ticket: real Liquid Glass on OS 26,
    /// `.ultraThinMaterial` as a fallback. It carries no tint of its own — the
    /// theme tint sits in the gradient *behind* it (see `body`), so the glass
    /// refracts the tint rather than washing it out, one rim at the outer edge.
    @ViewBuilder
    private func glassSurface<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, *) {
            shape
                .fill(.clear)
                .glassEffect(.clear, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 7) {
                Circle()
                    .fill(colors.accentInkColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: colors.accentInkColor, radius: 3.5)
                Text("PLAYING NEAR YOU")
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
                    .kerning(1.6)
                    .foregroundStyle(colors.accentInkColor)
            }
            Spacer(minLength: 8)
            if let pill = presenter.statusPillText {
                statusPill(pill)
            }
        }
    }

    private func statusPill(_ text: String) -> some View {
        let colors = pillColors
        return Text(text.uppercased())
            .font(.system(.caption2, design: .monospaced))
            .fontWeight(.bold)
            .kerning(1)
            .foregroundStyle(colors.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(colors.fill))
            .overlay(Capsule().stroke(colors.border, lineWidth: 1))
            .fixedSize()
    }

    // MARK: - Stats (doors / show / price)

    private var statsRow: some View {
        let cells = statCells
        return Group {
            if !cells.isEmpty {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(cells) { cell in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(cell.key)
                                .font(.system(.caption2, design: .monospaced))
                                .kerning(1)
                                .foregroundStyle(.white.opacity(0.5))
                            Text(cell.value)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 16)
            }
        }
    }

    /// The stat cells that actually have data — an unpriced, time-less show shows
    /// no empty cells (matches the prototype's `.stats:empty { display:none }`).
    private var statCells: [StatCell] {
        var cells: [StatCell] = []
        if let doors = presenter.doorsLabel { cells.append(StatCell(key: "DOORS", value: doors)) }
        if let show = presenter.showLabel { cells.append(StatCell(key: "SHOW", value: show)) }
        if let price = presenter.priceLabel { cells.append(StatCell(key: "PRICE", value: price)) }
        return cells
    }

    /// "with <support> · <age>", omitting whichever pieces are absent. `nil` when
    /// neither is present. The string is built (and unit-tested) once on the
    /// presenter; the poster hero shares the same helper.
    private var subline: Text? {
        presenter.subline.map(Text.init)
    }

    // MARK: - Actions (outbound CTA per status)

    @ViewBuilder
    private var actions: some View {
        if isPast {
            passedNotice
        } else if presenter.isCancelled {
            cancelNotice
        } else if let url = presenter.ctaURL {
            VStack(spacing: 9) {
                Button {
                    openURL(url)
                } label: {
                    HStack(spacing: 9) {
                        Text(presenter.ctaLabel)
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.bold))
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .modifier(CTAButtonStyle(filled: ctaFilled, colors: colors, buttonInk: buttonInk))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(presenter.ctaLabel). \(presenter.ctaCaption)")

                Text(presenter.ctaCaption)
                    .font(.caption)
                    .foregroundStyle(Palette.inkDim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Filled amber for a live purchase/RSVP; outlined for the "see the
    /// venue/ticket page" statuses.
    private var ctaFilled: Bool {
        show.status == .onSale || show.status == .free
    }

    /// The keepsake note shown in place of the CTA when a shared link opens a
    /// show that has already happened (#537). A quiet dashed card in the ticket's
    /// own edge tint — not the red cancelled treatment, since nothing went wrong.
    private var passedNotice: some View {
        Text(presenter.passedShowNote)
            .font(.subheadline)
            .foregroundStyle(Palette.inkDim)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(13)
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(colors.edgeColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
    }

    private var cancelNotice: some View {
        VStack(spacing: 6) {
            Text("This show has been cancelled.")
                .font(.subheadline)
                .foregroundStyle(Palette.cancelInk)
            if let url = presenter.ctaURL {
                Button { openURL(url) } label: {
                    HStack(spacing: 4) {
                        Text(presenter.ctaLabel)
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.caption)
                    .foregroundStyle(colors.accentInkColor)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(13)
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Palette.cancel.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    // MARK: - Stub (content only; shares the ticket's panel)

    private var ticketStub: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("ADMIT ONE")
                    .font(.caption).fontWeight(.heavy)
                    .kerning(1.4)
                    .foregroundStyle(colors.stubInkColor)
                Text("GEN ADM\n\(presenter.ticketSerial)")
                    .font(.system(.caption2, design: .monospaced))
                    .kerning(0.8)
                    .foregroundStyle(colors.stubFaintColor)
            }
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Text(presenter.stubWeekday)
                    .font(.system(.caption2, design: .monospaced))
                    .kerning(1.6)
                    .foregroundStyle(colors.stubFaintColor)
                Text(presenter.stubDayNumber)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(colors.stubInkColor)
                Text(presenter.stubMonth)
                    .font(.system(.caption2, design: .monospaced))
                    .kerning(1.6)
                    .foregroundStyle(colors.stubFaintColor)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: stubHeight)
        .frame(maxWidth: .infinity)
        // The stub content draws no surface of its own — its near-clear tint and the
        // shared glass come from `body`. Its ink is the contrast-floored `stubInk`
        // (dark on light themes, white on dark) so it stays legible over the
        // keepsake window. The dashed line is the only mark at the seam.
        .overlay(alignment: .top) {
            DashedLine(approximateSegment: 5)
                .stroke(colors.perforationColor, style: StrokeStyle(lineWidth: 2))
                .frame(height: 2)
        }
    }

    private var pillColors: (fill: Color, border: Color, ink: Color) {
        switch show.status {
        case .onSale:
            return (Palette.ok.opacity(1.0), Palette.ok.opacity(0.5), Palette.okInk)
        case .soldOut:
            return (Palette.soldout.opacity(0.18), Palette.soldout.opacity(0.5), Palette.soldoutInk)
        case .cancelled:
            return (Palette.cancel.opacity(0.20), Palette.cancel.opacity(0.55), Palette.cancelInk)
        case .rescheduled:
            return (colors.accentInkColor.opacity(0.18), colors.accentInkColor.opacity(0.5), colors.accentInkColor)
        case .free:
            return (Palette.free.opacity(0.18), Palette.free.opacity(0.5), Palette.freeInk)
        case .unknown:
            return (.white.opacity(0.12), .white.opacity(0.3), Palette.inkDim)
        }
    }
}

// MARK: - Stat cell

/// One labeled value in the ticket's stats row (e.g. DOORS / 7 PM). Identifiable
/// by its key so `ForEach` can render only the present cells.
private struct StatCell: Identifiable {
    let key: String
    let value: String
    var id: String { key }
}

// MARK: - CTA button style

/// The two CTA treatments, both theme-tinted: a filled `accentInk` chip with dark
/// accent-tinted ink (buy / RSVP), or an outlined accent chip (see the venue
/// page). `accentInk` is always light, so `buttonInk` reads on the filled variant
/// in every theme.
private struct CTAButtonStyle: ViewModifier {
    let filled: Bool
    let colors: TicketColors
    let buttonInk: Color

    func body(content: Content) -> some View {
        if filled {
            content
                .foregroundStyle(buttonInk)
                .background(colors.accentInkColor, in: .rect(cornerRadius: 13))
        } else {
            content
                .foregroundStyle(colors.accentInkColor)
                .background(colors.accentInkColor.opacity(0.1), in: .rect(cornerRadius: 13))
                .overlay(
                    RoundedRectangle(cornerRadius: 13).stroke(colors.edgeColor, lineWidth: 1)
                )
        }
    }
}

// MARK: - Palette

/// The ticket's **status** palette — deliberately NOT theme-derived. On-sale
/// green, sold-out coral, cancelled red, and free teal read as universal signals
/// across every wallpaper; only the ticket's accent chrome and glass tint follow
/// the theme (see ``TicketColors``). Translated from the prototype's CSS into HSL
/// so the hue relationships read at a glance; trailing hex is the prototype value.
/// File-private so it doesn't leak into the app-wide color system.
private enum Palette {
    static let ok = Color(HSL(hue: 0.3753, saturation: 0.5857, lightness: 0.4922)) // #34C759
    static let okInk = Color(HSL(hue: 0.3851, saturation: 0.7115, lightness: 0.7961)) // #A6F0BD
    static let soldout = Color(HSL(hue: 0.0405, saturation: 1, lightness: 0.7098)) // #FF8F6B
    static let soldoutInk = Color(HSL(hue: 0.0422, saturation: 1, lightness: 0.8529)) // #FFC7B4
    static let cancel = Color(HSL(hue: 0, saturation: 1, lightness: 0.7098)) // #FF6B6B
    static let cancelInk = Color(HSL(hue: 0, saturation: 1, lightness: 0.851)) // #FFB3B3
    static let free = Color(HSL(hue: 0.4827, saturation: 0.6221, lightness: 0.5745)) // #4FD6C8
    static let freeInk = Color(HSL(hue: 0.4762, saturation: 0.6512, lightness: 0.8314)) // #B8F0E8

    /// Neutral secondary ink — plain white on the deep body tint reads in every theme.
    static let inkDim = Color.white.opacity(0.72)
}

// MARK: - Previews

#Preview("On Sale") {
    BoxOfficeTicketPreviewStage(show: .previewOnSale)
}

#Preview("Sold Out") {
    BoxOfficeTicketPreviewStage(show: .previewSoldOut)
}

#Preview("Cancelled") {
    BoxOfficeTicketPreviewStage(show: .previewCancelled)
}

#Preview("Rescheduled") {
    BoxOfficeTicketPreviewStage(show: .previewRescheduled)
}

#Preview("Free") {
    BoxOfficeTicketPreviewStage(show: .previewFree)
}

#Preview("Unknown status") {
    BoxOfficeTicketPreviewStage(show: .previewUnknown)
}

#Preview("Sparse data") {
    BoxOfficeTicketPreviewStage(show: .previewSparse)
}

#Preview("Passed show (deep link)") {
    BoxOfficeTicketPreviewStage(show: .previewOnSale, isPast: true)
}

#Preview("Theme · WXYC 1983 (amber, dark wall)") {
    BoxOfficeTicketPreviewStage(show: .previewOnSale, colors: .previewWXYC1983, lightWallpaper: false)
}

#Preview("Theme · Windowlight (low-sat, light wall)") {
    BoxOfficeTicketPreviewStage(show: .previewOnSale, colors: .previewWindowlight, lightWallpaper: true)
}

#Preview("In detail view") {
    BoxOfficeTicketDetailContextPreview()
}

/// Puts the ticket on a stand-in wallpaper so the glass, the notch cut-throughs,
/// and — crucially — the near-clear stub read. The backdrop tracks the theme's
/// foreground: a light wallpaper for `foreground: .dark` themes (most of them), a
/// dark one for `.light` themes, so the contrast-floored stub ink is judged
/// against the kind of surface it will actually sit on.
private struct BoxOfficeTicketPreviewStage: View {
    let show: Concert
    var colors: TicketColors = .previewPlasticPulse
    var lightWallpaper: Bool = true
    var isPast: Bool = false

    var body: some View {
        ZStack {
            (lightWallpaper ? Self.lightBackdrop : Self.darkBackdrop)
                .ignoresSafeArea()
            BoxOfficeTicketView(show: show, colors: colors, isPast: isPast)
                .padding()
        }
    }

    /// Dark stand-in wallpaper for `.light`-foreground themes.
    static let darkBackdrop = LinearGradient(
        colors: [
            Color(HSL(hue: 0.6474, saturation: 0.3786, lightness: 0.4039)), // #40498E
            Color(HSL(hue: 0.913, saturation: 0.4768, lightness: 0.4647)), // #AF3E79
            Color(HSL(hue: 0, saturation: 0.4275, lightness: 0.5)), // #B64949
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Light stand-in wallpaper for `.dark`-foreground themes (the common case).
    static let lightBackdrop = LinearGradient(
        colors: [
            Color(HSL(hue: 0.58, saturation: 0.45, lightness: 0.82)),
            Color(HSL(hue: 0.72, saturation: 0.40, lightness: 0.80)),
            Color(HSL(hue: 0.08, saturation: 0.55, lightness: 0.82)),
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

/// Recreates `PlaycutDetailView`'s section stack — a faithful mock header, the
/// ticket slotted in right after it, then two placeholder sibling section cards
/// in the app's standard `.opacity(0.1)` container — so the ticket can be judged
/// *in context* against normal sections. Preview-only; touches no production
/// detail view. When the data source is wired, this is the layout the real
/// `BoxOfficeTicketView(show:)` drops into (see `PlaycutDetailView` line ~55).
private struct BoxOfficeTicketDetailContextPreview: View {
    private let playcut = Playcut(
        id: 1, hour: 0, chronOrderID: 1, timeCreated: 0,
        songTitle: "Method Actor",
        labelName: "Ninja Tune",
        artistName: "Nilüfer Yanya",
        releaseTitle: "My Method Actor"
    )
    private let show = Concert.previewInContext

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(HSL(hue: 0.6474, saturation: 0.3786, lightness: 0.4039)), // #40498E
                    Color(HSL(hue: 0.913, saturation: 0.4768, lightness: 0.4647)), // #AF3E79
                    Color(HSL(hue: 0, saturation: 0.4275, lightness: 0.5)), // #B64949
                    Color(HSL(hue: 0.9283, saturation: 0.4263, lightness: 0.4922)), // #B34876
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    mockHeader
                        .padding(.top, 30)
                    // WXYC 1983 (foreground `.light`) so the stub's white ink reads
                    // on this dark stand-in wallpaper.
                    BoxOfficeTicketView(show: show, colors: .previewWXYC1983)
                    mockSection(title: "Add it to your library", tiles: 4)
                    mockSection(title: "More Info", tiles: 2)
                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
            }
        }
    }

    /// Mirrors `PlaycutHeaderSection`: centered artwork placeholder, then
    /// title / artist / release.
    private var mockHeader: some View {
        VStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.12))
                .frame(width: 220, height: 220)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 54))
                        .foregroundStyle(.white.opacity(0.35))
                )
                .shadow(radius: 20, x: 0, y: 10)
                .padding(.bottom, 16)
            VStack(spacing: 4) {
                Text(playcut.songTitle).font(.title2).fontWeight(.bold)
                Text(playcut.artistName).font(.title3)
                if let release = playcut.releaseTitle {
                    Text(release).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
        }
    }

    /// A placeholder standing in for a real section (streaming links, more info),
    /// using the same `.detailSectionHeader` style + `.opacity(0.1)` container so
    /// the ticket's distinct material reads as intentionally different.
    private func mockSection(title: String, tiles: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.smallCaps())
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(0..<tiles, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.14))
                        .frame(height: 46)
                }
            }
        }
        .foregroundStyle(.white)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.1)))
    }
}

private extension Concert {
    static func preview(
        headliningArtistRaw: String = "Jessica Pratt",
        status: ShowStatus,
        priceMin: Double? = 22,
        priceMax: Double? = 25,
        doorsHour: Int? = 19,
        showHour: Int? = 20,
        supportingArtistsRaw: [String] = ["Julie Byrne"],
        ageRestriction: String? = "All Ages",
        venueName: String = "Cat's Cradle",
        venueCity: String = "Carrboro",
        eventURL: URL? = URL(string: "https://catscradle.com/event/jessica-pratt")
    ) -> Concert {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let startsOn = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))
            ?? Date(timeIntervalSince1970: 1_785_898_800)
        let doorsAt = doorsHour.flatMap { calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: $0)) }
        let startsAt = showHour.flatMap { calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: $0)) }
        return Concert(
            id: 4821,
            venue: Venue(id: 3, slug: "cats-cradle", name: venueName, city: venueCity, state: "NC", address: nil),
            startsOn: startsOn,
            startsAt: startsAt,
            doorsAt: doorsAt,
            headliningArtistRaw: headliningArtistRaw,
            supportingArtistsRaw: supportingArtistsRaw,
            ticketURL: URL(string: "https://www.etix.com/ticket/p/jessica-pratt"),
            eventURL: eventURL,
            priceMin: priceMin,
            priceMax: priceMax,
            ageRestriction: ageRestriction,
            status: status
        )
    }

    static let previewOnSale = preview(status: .onSale)
    static let previewSoldOut = preview(status: .soldOut)
    static let previewCancelled = preview(status: .cancelled)
    static let previewRescheduled = preview(status: .rescheduled)
    static let previewFree = preview(status: .free, priceMin: nil, priceMax: nil)
    static let previewUnknown = preview(status: .unknown)
    static let previewSparse = preview(
        status: .unknown,
        priceMin: nil, priceMax: nil,
        doorsHour: nil, showHour: nil,
        supportingArtistsRaw: [], ageRestriction: nil,
        eventURL: nil
    )

    /// The show for the in-detail-view mockup — the same artist as the mock
    /// playcut (Nilüfer Yanya), playing Cat's Cradle.
    static let previewInContext = preview(
        headliningArtistRaw: "Nilüfer Yanya",
        status: .onSale,
        supportingArtistsRaw: ["Tapir!"]
    )
}
