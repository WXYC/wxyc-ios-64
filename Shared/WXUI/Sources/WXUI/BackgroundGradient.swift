//
//  BackgroundGradient.swift
//  WXUI
//
//  Created by Jake Bromberg on 11/25/25.
//

import SwiftUI

public struct WXYCBackground: ShapeStyle {
    public init() {}
    
    public func resolve(in environment: EnvironmentValues) -> Gradient {
        environment.colorScheme == .light ? Self.wxycBackgroundLight : Self.wxycBackgroundDark
    }
    
    private static var wxycBackgroundLight: Gradient {
        .init(stops: [
            .init(color: Color(red: 126/255, green: 133/255, blue: 193/255), location: 0.0),
            .init(color: Color(red: 126/255, green: 133/255, blue: 193/255), location: 0.08),
            .init(color: Color(red: 226/255, green: 125/255, blue: 178/255), location: 0.66),
            .init(color: Color(red: 233/255, green: 140/255, blue: 140/255), location: 0.72),
            .init(color: Color(red: 230/255, green: 161/255, blue: 191/255), location: 1.0)
        ])
    }
    
    private static var wxycBackgroundDark: Gradient {
        .init(
            stops: [
                .init(
                    color: Color(
                        hue: 0.649,
                        saturation: 0.547,
                        brightness: 0.557,
                        opacity: 1.0
                    ),
                    location: 0.0
                ),
                .init(
                    color: Color(
                        hue: 0.649,
                        saturation: 0.547,
                        brightness: 0.557,
                        opacity: 1.0
                    ),
                    location: 0.08
                ),
                .init(
                    color: Color(
                        hue: 0.913,
                        saturation: 0.647,
                        brightness: 0.686,
                        opacity: 1.0
                    ),
                    location: 0.66
                ),
                .init(
                    color: Color(
                        hue: 0.000,
                        saturation: 0.599,
                        brightness: 0.714,
                        opacity: 1.0
                    ),
                    location: 0.72
                ),
                .init(
                    color: Color(
                        hue: 0.928,
                        saturation: 0.600,
                        brightness: 0.702,
                        opacity: 1.0
                    ),
                    location: 1.0
                )
            ]
        )
    }
}

