//
//  BackgroundMesh.swift
//  WXUI
//
//  Created by Jake Bromberg on 11/25/25.
//

import SwiftUI

public struct WXYCMeshAnimation: View {
    public init() {}
    
    public var body: some View {
        meshGradient
    }
    
    static let palette: [Color] = [
        .indigo,
        .orange,
        .pink,
        .purple,
        .yellow,
        .blue,
        .green,
    ]
    
    // Generate colors once at initialization
    static let gradientColors: [Color] = (0..<16).map { _ in
        palette.randomElement()!
    }
    
    public var meshGradient: TimelineView<AnimationTimelineSchedule, MeshGradient> {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSince1970
            let offsetX = Float(sin(time)) * 0.25
            let offsetY = Float(cos(time)) * 0.25

            MeshGradient(
                width: 4,
                height: 4,
                points: [
                    [0.0, 0.0], [0.3, 0.0], [0.7, 0.0], [1.0, 0.0],
                    [0.0, 0.3], [0.2 + offsetX, 0.4 + offsetY], [0.7 + offsetX, 0.2 + offsetY], [1.0, 0.3],
                    [0.0, 0.7], [0.3 + offsetX, 0.8], [0.7 + offsetX, 0.6], [1.0, 0.7],
                    [0.0, 1.0], [0.3, 1.0], [0.7, 1.0], [1.0, 1.0]
                ],
                colors: Self.gradientColors
            )
        }
    }
}

extension WXYCMeshAnimation: ShapeStyle {
    
}
