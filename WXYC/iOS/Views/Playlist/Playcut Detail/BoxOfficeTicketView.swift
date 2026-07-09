//
//  BoxOfficeTicketView.swift
//  WXYC
//
//  The "Box Office" ticket: an amber-glass keepsake surfaced on a playcut when
//  the played artist has an upcoming Triangle-area show. A warm smoked-glass body
//  (the wallpaper glows through) meets an opaque cream stub; two notches are cut
//  clean through to the wallpaper at the perforation. Design is the approved
//  prototype in docs/ideas/touring-shows-box-office.html.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playlist
import SwiftUI
import Wallpaper

/// Renders an ``UpcomingShow`` as the Box Office ticket. All display strings come
/// from ``BoxOfficeTicketPresenter`` (unit-tested); this view is pure layout.
struct BoxOfficeTicketView: View {
    let show: UpcomingShow

    @Environment(\.openURL) private var openURL

    private var presenter: BoxOfficeTicketPresenter { BoxOfficeTicketPresenter(show) }

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
        .clipShape(ticketShape)
        .overlay { ticketShape.stroke(Palette.hairline, lineWidth: 1) }
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
            Text(show.venueName ?? "Live Show")
                .font(.title2).fontWeight(.heavy)
                .foregroundStyle(.white)
                .padding(.top, 16)
            if let city = show.venueCity {
                Text(city)
                    .font(.footnote)
                    .foregroundStyle(Palette.amberInk)
                    .padding(.top, 2)
            }
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
        .background { glassSurface(Rectangle()) }
    }

    /// A neutral frosted-glass surface for the ticket: real Liquid Glass on OS 26,
    /// `.ultraThinMaterial` as a fallback. No tint — the wallpaper glows through
    /// and the card reads as the app's standard glass, like the other sections.
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
                    .fill(Palette.amber)
                    .frame(width: 6, height: 6)
                    .shadow(color: Palette.amberLine, radius: 3.5)
                Text("PLAYING NEAR YOU")
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
                    .kerning(1.6)
                    .foregroundStyle(Palette.amberInk)
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
    /// neither is present.
    private var subline: Text? {
        var pieces: [String] = []
        if let support = show.supportArtists, !support.isEmpty { pieces.append("with \(support)") }
        if let age = show.ageRestriction, !age.isEmpty { pieces.append(age) }
        guard !pieces.isEmpty else { return nil }
        return Text(pieces.joined(separator: " · "))
    }

    // MARK: - Actions (outbound CTA per status)

    @ViewBuilder
    private var actions: some View {
        if presenter.isCancelled {
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
                    .modifier(CTAButtonStyle(filled: ctaFilled))
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

    /// Filled amber for a live purchase/RSVP; outlined for "see the venue page".
    private var ctaFilled: Bool {
        show.status == .onSale || show.status == .free
    }

    private var cancelNotice: some View {
        VStack(spacing: 6) {
            Text("This show has been cancelled.")
                .font(.subheadline)
                .foregroundStyle(Palette.cancelInk)
            if let url = presenter.ctaURL {
                Button { openURL(url) } label: {
                    HStack(spacing: 4) {
                        Text("See the venue's page")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.amberInk)
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

    // MARK: - Stub (cream keepsake)

    private var ticketStub: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("ADMIT ONE")
                    .font(.caption).fontWeight(.heavy)
                    .kerning(1.4)
                    .foregroundStyle(Palette.stubAccent)
                Text("GEN ADM\n\(presenter.ticketSerial)")
                    .font(.system(.caption2, design: .monospaced))
                    .kerning(0.8)
                    .foregroundStyle(Palette.stubFaint)
            }
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Text(presenter.stubWeekday)
                    .font(.system(.caption2, design: .monospaced))
                    .kerning(1.6)
                    .foregroundStyle(Palette.stubAccent)
                Text(presenter.stubDayNumber)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(Palette.stubInk)
                Text(presenter.stubMonth)
                    .font(.system(.caption2, design: .monospaced))
                    .kerning(1.6)
                    .foregroundStyle(Palette.stubFaint)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: stubHeight)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                MaterialView()
                glassSurface(Rectangle())
                // A whisper of separation so the stub reads as a distinct panel
                // from the body without reintroducing a colored fill.
                Color.white.opacity(0.05)
            }
        }
        .overlay(alignment: .top) {
            DashedLine()
                .stroke(Palette.perforation, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
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

/// The two CTA treatments: a filled amber gradient (buy/RSVP) or an amber
/// outline (see the venue page).
private struct CTAButtonStyle: ViewModifier {
    let filled: Bool

    func body(content: Content) -> some View {
        if filled {
            content
                .foregroundStyle(Palette.buttonText)
                .background(
                    LinearGradient(
                        colors: [Palette.amberLight, Palette.amber],
                        startPoint: .top, endPoint: .bottom
                    ),
                    in: .rect(cornerRadius: 13)
                )
        } else {
            content
                .foregroundStyle(Palette.amberInk)
                .background(Palette.amber.opacity(0.1), in: .rect(cornerRadius: 13))
                .overlay(
                    RoundedRectangle(cornerRadius: 13).stroke(Palette.amberLine, lineWidth: 1)
                )
        }
    }
}

// MARK: - Shapes

/// A rounded-rectangle ticket outline with two circular notches cut into the
/// side edges at the perforation line (`stubHeight` up from the bottom). Used as
/// the clip shape so the notches punch through to the wallpaper behind the card.
private struct TicketShape: Shape {
    let cornerRadius: CGFloat
    let stubHeight: CGFloat
    let notchRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var shape = Path(roundedRect: rect, cornerRadius: cornerRadius)
        let notchCenterY = rect.maxY - stubHeight
        let leftNotch = Path(ellipseIn: CGRect(
            x: rect.minX - notchRadius, y: notchCenterY - notchRadius,
            width: notchRadius * 2, height: notchRadius * 2
        ))
        let rightNotch = Path(ellipseIn: CGRect(
            x: rect.maxX - notchRadius, y: notchCenterY - notchRadius,
            width: notchRadius * 2, height: notchRadius * 2
        ))
        shape = shape.subtracting(leftNotch)
        shape = shape.subtracting(rightNotch)
        return shape
    }
}

/// A single horizontal line across the middle of its rect (for the dashed
/// perforation drawn along the top of the stub).
private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Palette

/// The ticket's warm palette, translated from the prototype's CSS tokens. Kept
/// file-private so it doesn't leak into the app-wide color system.
private enum Palette {
    static let amber = Color(hex: 0xFF8940)
    static let amberLight = Color(hex: 0xFF9D5C)
    static let amberInk = Color(hex: 0xFFC79A)
    static let amberLine = Color(hex: 0xFF8940, opacity: 0.55)

    static let ok = Color(hex: 0x34C759)
    static let okInk = Color(hex: 0xA6F0BD)
    static let soldout = Color(hex: 0xFF8F6B)
    static let soldoutInk = Color(hex: 0xFFC7B4)
    static let cancel = Color(hex: 0xFF6B6B)
    static let cancelInk = Color(hex: 0xFFB3B3)
    static let free = Color(hex: 0x4FD6C8)
    static let freeInk = Color(hex: 0xB8F0E8)

    static let inkDim = Color.white.opacity(0.72)

    // The stub is now the same neutral glass as the body, so its text is white
    // rather than the old dark-on-cream palette.
    static let stubInk = Color.white
    static let stubAccent = Color.white.opacity(0.82)
    static let stubFaint = Color.white.opacity(0.5)
    static let perforation = Color.white.opacity(0.25)

    static let hairline = Color.white.opacity(0.18)

    static let buttonText = Color(hex: 0x2A1400)
}

private extension Color {
    /// Builds an sRGB color from a `0xRRGGBB` literal.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
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

#Preview("Free") {
    BoxOfficeTicketPreviewStage(show: .previewFree)
}

#Preview("Sparse data") {
    BoxOfficeTicketPreviewStage(show: .previewSparse)
}

#Preview("In detail view") {
    BoxOfficeTicketDetailContextPreview()
}

/// Puts the ticket on a WXYC-like gradient so the glass/notch cut-throughs read.
private struct BoxOfficeTicketPreviewStage: View {
    let show: UpcomingShow

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x40498E), Color(hex: 0xAF3E79), Color(hex: 0xB64949)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            BoxOfficeTicketView(show: show)
                .padding()
        }
    }
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
    private let show = UpcomingShow.previewInContext

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x40498E), Color(hex: 0xAF3E79),
                    Color(hex: 0xB64949), Color(hex: 0xB34876),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    mockHeader
                        .padding(.top, 30)
                    BoxOfficeTicketView(show: show)
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

private extension UpcomingShow {
    static func preview(
        eventName: String = "Jessica Pratt",
        artist: String? = "Jessica Pratt",
        status: ShowStatus,
        priceMin: Double? = 22,
        priceMax: Double? = 25,
        doorsTime: String? = "19:00:00",
        showTime: String? = "20:00:00",
        supportArtists: String? = "Julie Byrne",
        ageRestriction: String? = "All Ages",
        venueName: String? = "Cat's Cradle",
        venueCity: String? = "Carrboro"
    ) -> UpcomingShow {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))
            ?? Date(timeIntervalSince1970: 1_785_898_800)
        return UpcomingShow(
            id: 4821,
            eventName: eventName,
            artist: artist,
            supportArtists: supportArtists,
            venueName: venueName,
            venueCity: venueCity,
            date: date,
            doorsTime: doorsTime,
            showTime: showTime,
            status: status,
            priceMin: priceMin,
            priceMax: priceMax,
            ticketURL: URL(string: "https://www.etix.com/ticket/p/jessica-pratt"),
            sourceURL: URL(string: "https://catscradle.com/event/jessica-pratt"),
            ageRestriction: ageRestriction
        )
    }

    static let previewOnSale = preview(status: .onSale)
    static let previewSoldOut = preview(status: .soldOut)
    static let previewCancelled = preview(status: .cancelled)
    static let previewFree = preview(status: .free, priceMin: nil, priceMax: nil)
    static let previewSparse = preview(
        status: .unknown,
        priceMin: nil, priceMax: nil,
        doorsTime: nil, showTime: nil,
        supportArtists: nil, ageRestriction: nil,
        venueCity: nil
    )

    /// The show for the in-detail-view mockup — the same artist as the mock
    /// playcut (Nilüfer Yanya), playing Cat's Cradle.
    static let previewInContext = preview(
        eventName: "Nilüfer Yanya",
        artist: "Nilüfer Yanya",
        status: .onSale,
        supportArtists: "Tapir!"
    )
}
