//
//  VenueMapView.swift
//  WXYC
//
//  The non-interactive venue map atop the Concert Detail's "Where" card. The
//  backend `Venue` carries no coordinates, so the map geocodes the presenter's
//  `venueSearchQuery` through `MKLocalSearch` (Triangle-biased) and drops a
//  marker; results are cached per venue slug so re-opening a detail never
//  re-geocodes. While resolving it shows the card's placeholder fill; if the
//  lookup fails it collapses to nothing, leaving the "Where" card as it was
//  before the map existed.
//
//  Created by Jake Bromberg on 07/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import MapKit
import SwiftUI

/// A small, tap-through map locating a ``Venue`` by search query.
struct VenueMapView: View {

    /// The venue to locate; ``Venue/slug`` keys the geocode cache.
    let venue: Venue

    /// The plain-text geocoding query (`BoxOfficeTicketPresenter.venueSearchQuery`).
    let searchQuery: String

    /// Invoked when the resolved map is tapped (the detail opens directions).
    let onTap: () -> Void

    private enum Resolution: Equatable {
        case resolving
        case resolved(CLLocationCoordinate2D)
        case failed

        static func == (lhs: Resolution, rhs: Resolution) -> Bool {
            switch (lhs, rhs) {
            case (.resolving, .resolving), (.failed, .failed): true
            case let (.resolved(a), .resolved(b)): a.latitude == b.latitude && a.longitude == b.longitude
            default: false
            }
        }
    }

    @State private var resolution: Resolution = .resolving

    private static let mapHeight: CGFloat = 150

    /// Resolved coordinates by venue slug, for the app's lifetime. Venues are a
    /// small fixed set (~21 Triangle rooms), so this never grows meaningfully.
    @MainActor private static var geocodeCache: [String: CLLocationCoordinate2D] = [:]

    /// The Triangle, roughly — biases `MKLocalSearch` so a bare venue name
    /// resolves to the local room, not a same-named venue elsewhere.
    private static let triangleRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.93, longitude: -78.90),
        span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
    )

    var body: some View {
        switch resolution {
        case .resolving:
            placeholder
                .task(id: venue.slug) { await resolve() }
        case .resolved(let coordinate):
            resolvedMap(coordinate)
        case .failed:
            EmptyView()
        }
    }

    /// The card fill while the venue resolves, so the "Where" card doesn't jump
    /// from text-only to text-plus-map in the common (cached) case.
    private var placeholder: some View {
        Rectangle()
            .fill(.white.opacity(0.04))
            .frame(height: Self.mapHeight)
            .overlay {
                ProgressView()
                    .tint(.white.opacity(0.4))
            }
    }

    private func resolvedMap(_ coordinate: CLLocationCoordinate2D) -> some View {
        Button(action: onTap) {
            Map(
                initialPosition: .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                    )
                ),
                interactionModes: []
            ) {
                Marker(venue.name, coordinate: coordinate)
                    .tint(.red)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .environment(\.colorScheme, .dark)
            .frame(height: Self.mapHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Map of \(venue.name). Opens directions.")
    }

    private func resolve() async {
        if let cached = Self.geocodeCache[venue.slug] {
            resolution = .resolved(cached)
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchQuery
        request.region = Self.triangleRegion
        request.resultTypes = [.pointOfInterest, .address]
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let coordinate = response.mapItems.first?.placemark.coordinate else {
                resolution = .failed
                return
            }
            Self.geocodeCache[venue.slug] = coordinate
            resolution = .resolved(coordinate)
        } catch {
            resolution = .failed
        }
    }
}
