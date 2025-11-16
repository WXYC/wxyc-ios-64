//
//  CassetteView.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/11/25.
//

import SwiftUI

#if os(macOS)
typealias UXImage = NSImage
#else
typealias UXImage = UIImage
#endif


struct CassetteView: View {
    var isPlaying: Bool = false
    
    var body: some View {
        cassetteBody()
    }
    
    @ViewBuilder
    private func cassetteBody() -> some View {
        GeometryReader { geometry in
            let imageNames = [
                "Cassette Left Arch",
                "Cassette Center",
                "Cassette Right Arch"
            ]
            let aspectRatios = imageNames.compactMap { name -> CGFloat? in
                guard let image = UXImage(named: name) else { return nil }
                return image.size.width / image.size.height
            }
            
            // Calculate dimensions based on available space
            // totalWidth = height * (aspectRatio1 + aspectRatio2 + aspectRatio3)
            // height = totalWidth / sum(aspectRatios)
            let totalAspectRatio = aspectRatios.reduce(0, +)
            // Calculate what height would be from available width
            let heightFromWidth = totalAspectRatio > 0 ? (geometry.size.width / totalAspectRatio).rounded() : 100
            // Use the minimum of available height and calculated height to respect constraints
            // When height is constrained by parent, geometry.size.height will be smaller
            let calculatedHeight = geometry.size.height > 0 
                ? min(geometry.size.height, heightFromWidth)
                : heightFromWidth
            
            HStack(alignment: .center, spacing: 0) {
                Image("Cassette Left Arch")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: calculatedHeight)
                    .anchorPreference(key: ItemBoundsKey.self, value: .bounds) { [0: $0] }  // index 0
                
                Image("Cassette Center")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fill)
                    .frame(height: calculatedHeight)
                    .anchorPreference(key: ItemBoundsKey.self, value: .bounds) { [1: $0] }  // index 1
                    .clipped()
                
                Image("Cassette Right Arch")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: calculatedHeight)
                    .anchorPreference(key: ItemBoundsKey.self, value: .bounds) { [2: $0] }  // index 2
                    .clipped()
            }
            // Center the overlay between the first's trailing and second's leading:
            .centerOverlay(between: 0, and: 1) { rects in
                reel(for: rects)
            }
             .centerOverlay(between: 1, and: 2) { rects in
                reel(for: rects)
            }
            .frame(width: calculatedHeight * totalAspectRatio, height: calculatedHeight)
            .background(
                Color(
                    red: 0.2094770372,
                    green: 0.1996150911,
                    blue: 0.2083641291
                )
            )
        }
    }
    
    @ViewBuilder
    private func reel(for rects: [Int: CGRect]) -> some View {
        if let centerRect = rects[1] {
            CassetteReel(
                isPlaying: isPlaying,
                size: centerRect.height / 2.25
            )
        } else {
            EmptyView()
        }
    }
}

struct CassetteReel: View {
    var isPlaying: Bool
    var size: CGFloat
    
    private let rotationDuration = -9.0
    @State private var accumulatedRotation = 0.0
    @State private var playStartDate: Date?
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Image("Cassette Reel")
                .resizable()
                .interpolation(.high)
                .aspectRatio(1, contentMode: .fit)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(
                    normalizedRotation(angle(at: timeline.date, considering: isPlaying))
                ))
        }
        .onAppear {
            if isPlaying {
                playStartDate = Date()
            }
        }
        .onChange(of: isPlaying) { previousValue, newValue in
            handlePlaybackChange(from: previousValue, to: newValue)
        }
    }
    
    private func handlePlaybackChange(from previousValue: Bool, to newValue: Bool) {
        let now = Date()
        if newValue && !previousValue {
            playStartDate = now
        } else if !newValue && previousValue {
            accumulatedRotation = normalizedRotation(angle(at: now, considering: previousValue))
            playStartDate = nil
        }
    }
    
    private func angle(at date: Date, considering playingState: Bool) -> Double {
        guard playingState, let startDate = playStartDate else {
            return accumulatedRotation
        }
        let elapsed = date.timeIntervalSince(startDate)
        let rotation = accumulatedRotation + (elapsed / rotationDuration) * 360.0
        return rotation
    }
    
    private func normalizedRotation(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 360.0)
        return remainder >= 0 ? remainder : remainder + 360.0
    }
}

internal struct ItemBoundsKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// 2) A view modifier that centers `overlay` between item i's trailing and item j's leading
struct CenterBetweenEdgesOverlay<Overlay: View>: ViewModifier {
    let i: Int        // index of the "left" item (use its trailing edge)
    let j: Int        // index of the "right" item (use its leading edge)
    
    @ViewBuilder var overlay: ([Int: CGRect]) -> Overlay
    
    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(ItemBoundsKey.self) { bounds in
                GeometryReader { proxy in
                    if let ai = bounds[i], let aj = bounds[j] {
                        let ri = proxy[ai]  // rect of item i
                        let rj = proxy[aj]  // rect of item j
                        // Midpoint between i.trailing and j.leading:
                        let x = (ri.maxX + rj.minX) / 2
                        // Convert all anchors to CGRect dictionary
                        let rects = bounds.mapValues { proxy[$0] }
                        overlay(rects)
                            // Position in the parent's coordinate space
                            .position(x: x, y: proxy.size.height / 2)
                    }
                }
            }
    }
}

extension View {
    /// Centers `overlay` between the trailing edge of item `i` and the leading edge of item `j` in the same HStack.
    /// The overlay closure receives a dictionary of item bounds [index: CGRect].
    func centerOverlay(between i: Int, and j: Int, @ViewBuilder _ overlay: @escaping ([Int: CGRect]) -> some View) -> some View {
        self.modifier(CenterBetweenEdgesOverlay(i: i, j: j, overlay: overlay))
    }
}

#Preview {
    VStack {
        CassetteView(isPlaying: true)
            .frame(height: 100)
        
        CassetteView(isPlaying: false)
            .frame(height: 100)
    }
}
