//
//  LCDBarChartView.swift
//  PlayerHeaderView
//
//  Canvas-based GPU-accelerated LCD bar chart for audio visualization
//

import SwiftUI

// MARK: - Bar Data

/// Data model for a single bar in the chart
public struct BarData: Identifiable, Equatable {
    public var id: String { category }
    public let category: String
    public let value: Int
    /// When set, shows only a single segment at this position (for falling dot animation)
    public let singleDotPosition: Int?
    
    public init(category: String, value: Int, singleDotPosition: Int? = nil) {
        self.category = category
        self.value = value
        self.singleDotPosition = singleDotPosition
    }
}

// MARK: - LCD Bar Chart View

/// An LCD-style segmented bar chart view for audio visualization
/// Uses Canvas for GPU-accelerated rendering instead of SwiftUI Charts
struct LCDSpectrumAnalyzerView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let data: [BarData]
    let segmentsPerBar: Int
    let maxValue: Double
    let minBrightness: Double
    let maxBrightness: Double
    
    // Track previous active states to detect transitions
    @State private var previousActiveStates: [String: Set<Int>] = [:]
    @State private var transitioningSegments: [String: Set<Int>] = [:]
    @State private var animationProgress: Double = 1.0
    
    private static let saturation = 0.75
    private static let hue = 23.0 / 360.0
    private static let transitionDuration: Double = 0.25 // Fast animation
    
    init(
        data: [BarData],
        maxValue: Double,
        segmentsPerBar: Int = 8,
        minBrightness: Double = 0.80,
        maxBrightness: Double = 1.0
    ) {
        self.data = data
        self.maxValue = maxValue
        self.segmentsPerBar = segmentsPerBar
        self.minBrightness = minBrightness
        self.maxBrightness = maxBrightness
    }
    
    public var body: some View {
        Canvas { context, size in
            let barCount = data.count
            guard barCount > 0 else { return }
            
            // Inset drawing area to prevent glow clipping at edges
            let glowRadius: CGFloat = 3
            let inset = glowRadius + 1
            let drawingRect = CGRect(
                x: inset,
                y: inset,
                width: size.width - inset * 2,
                height: size.height - inset * 2
            )
            
            // Calculate dimensions within the inset area
            let horizontalGap: CGFloat = 3.5
            let verticalGap: CGFloat = 5.5
            let barWidth = (drawingRect.width - horizontalGap * CGFloat(barCount - 1)) / CGFloat(barCount)
            let segmentHeight = (drawingRect.height - verticalGap * CGFloat(segmentsPerBar - 1)) / CGFloat(segmentsPerBar)
            let cornerRadius: CGFloat = min(barWidth, segmentHeight) * 0.2
            
            for (barIndex, item) in data.enumerated() {
                let activeSegments = Int((Double(item.value) / maxValue) * Double(segmentsPerBar))
                let x = drawingRect.minX + CGFloat(barIndex) * (barWidth + horizontalGap)
                
                // Get previous active state for this bar
                let previousActive = previousActiveStates[item.id] ?? Set<Int>()
                
                for segmentIndex in 0..<segmentsPerBar {
                    // Determine if this segment is active
                    let isActive: Bool
                    if let dotPosition = item.singleDotPosition {
                        // Single dot mode - only light up the segment at dotPosition
                        isActive = segmentIndex == dotPosition && dotPosition >= 0
                    } else {
                        // Normal bar mode - light up all segments below activeSegments
                        isActive = segmentIndex < activeSegments
                    }
                    
                    // Check if this segment is transitioning from active to inactive
                    let isTransitioning = transitioningSegments[item.id]?.contains(segmentIndex) ?? false
                    
                    // Draw from bottom up (segment 0 at bottom)
                    let y = drawingRect.maxY - CGFloat(segmentIndex + 1) * (segmentHeight + verticalGap) + verticalGap
                    
                    let rect = CGRect(
                        x: x,
                        y: y,
                        width: barWidth,
                        height: segmentHeight
                    )
                    
                    let path = Path(roundedRect: rect, cornerRadius: cornerRadius)
                    
                    // Calculate brightness-scaled colors for this segment position
                    // If transitioning, interpolate between active and inactive brightness
                    let segmentColor = segmentColor(
                        isActive: isActive,
                        segmentIndex: segmentIndex,
                        isTransitioning: isTransitioning,
                        transitionProgress: animationProgress
                    )
                    let glowColor = glowColor(
                        for: segmentIndex,
                        isActive: isActive,
                        isTransitioning: isTransitioning,
                        transitionProgress: animationProgress
                    )
                    
                    // Draw glow/shadow for active segments or transitioning segments
                    if isActive || (isTransitioning && animationProgress > 0) {
                        var glowContext = context
                        let blurRadius = isActive ? glowRadius : glowRadius * (1.0 - animationProgress)
                        glowContext.addFilter(.blur(radius: blurRadius))
                        glowContext.fill(path, with: .color(glowColor))
                    } else {
                        var glowContext = context
                        glowContext.addFilter(.blur(radius: 1))
                        glowContext.fill(path, with: .color(glowColor))
                    }
                    
                    // Draw the segment
                    context.fill(path, with: .color(segmentColor))
                }
            }
        }
        .onChange(of: data) { oldData, newData in
            // Detect transitions and trigger animation
            var hasTransition = false
            var newPreviousStates: [String: Set<Int>] = [:]
            var newTransitioningSegments = transitioningSegments
            
            for item in newData {
                let activeSegments = Int((Double(item.value) / maxValue) * Double(segmentsPerBar))
                var activeSet = Set<Int>()
                
                if let dotPosition = item.singleDotPosition {
                    if dotPosition >= 0 {
                        activeSet.insert(dotPosition)
                    }
                } else {
                    for segmentIndex in 0..<activeSegments {
                        activeSet.insert(segmentIndex)
                    }
                }
                
                let previousActive = previousActiveStates[item.id] ?? Set<Int>()
                
                // Identify falling edges (turned off) and rising edges (turned on)
                let fallingEdges = previousActive.subtracting(activeSet)
                let risingEdges = activeSet.subtracting(previousActive)
                
                // Update transitioning segments
                var currentTransitioning = newTransitioningSegments[item.id] ?? Set<Int>()
                
                // Add new falling edges to transitioning set
                if !fallingEdges.isEmpty {
                    currentTransitioning.formUnion(fallingEdges)
                    hasTransition = true
                }
                
                // Remove any segments that turned back on (aborted transition)
                currentTransitioning.subtract(risingEdges)
                
                newTransitioningSegments[item.id] = currentTransitioning
                newPreviousStates[item.id] = activeSet
            }
            
            // Update states
            previousActiveStates = newPreviousStates
            transitioningSegments = newTransitioningSegments
            
            // Trigger animation if there's a transition
            if hasTransition {
                animationProgress = 0.0
                withAnimation(.easeOut(duration: Self.transitionDuration)) {
                    animationProgress = 1.0
                }
            }
        }
        .onAppear {
            // Initialize previous states
            var initialStates: [String: Set<Int>] = [:]
            for item in data {
                let activeSegments = Int((Double(item.value) / maxValue) * Double(segmentsPerBar))
                var activeSet = Set<Int>()
                
                if let dotPosition = item.singleDotPosition {
                    if dotPosition >= 0 {
                        activeSet.insert(dotPosition)
                    }
                } else {
                    for segmentIndex in 0..<activeSegments {
                        activeSet.insert(segmentIndex)
                    }
                }
                
                initialStates[item.id] = activeSet
            }
            previousActiveStates = initialStates
            animationProgress = 1.0
        }
    }
    
    /// Calculates brightness multiplier based on segment position (0 = bottom, segmentsPerBar-1 = top)
    /// Returns a value from minBrightness at top to maxBrightness at bottom for a gradient effect
    private func brightnessMultiplier(for segmentIndex: Int) -> Double {
        let brightnessSpan = maxBrightness - minBrightness
        let progress = Double(segmentIndex) / Double(max(segmentsPerBar - 1, 1))
        return maxBrightness - (brightnessSpan * progress)
    }
    
    private func segmentColor(isActive: Bool, segmentIndex: Int, isTransitioning: Bool = false, transitionProgress: Double = 1.0) -> Color {
        let multiplier = brightnessMultiplier(for: segmentIndex)
        
        let activeBrightness = colorScheme == .light ? 1.5 : 1.24
        let inactiveBrightness = colorScheme == .light ? 1.15 : 0.90
        
        let brightness: Double
        if isTransitioning {
            // Interpolate from active to inactive brightness during transition
            let progress = transitionProgress
            brightness = activeBrightness * (1.0 - progress) + inactiveBrightness * progress
        } else if isActive {
            brightness = activeBrightness
        } else {
            brightness = inactiveBrightness
        }
        
        return Color(hue: Self.hue, saturation: Self.saturation, brightness: brightness * multiplier)
    }
    
    private func glowColor(for segmentIndex: Int, isActive: Bool, isTransitioning: Bool = false, transitionProgress: Double = 1.0) -> Color {
        let multiplier = brightnessMultiplier(for: segmentIndex)
        let baseBrightness = 1.5 * multiplier
        
        let opacity: Double
        if isTransitioning {
            // Fade out glow during transition
            opacity = 0.6 * (1.0 - transitionProgress)
        } else if isActive {
            opacity = 0.6
        } else {
            opacity = 0.6
        }
        
        return Color(hue: Self.hue, saturation: Self.saturation, brightness: baseBrightness).opacity(opacity)
    }
}

