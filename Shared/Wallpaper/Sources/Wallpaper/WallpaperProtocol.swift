//
//  WallpaperProtocol.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import SwiftUI

/// Minimum interface required for a wallpaper to be handled by the registry
public protocol Wallpaper: Identifiable {
    associatedtype WallpaperView: View
    associatedtype DebugControls: View
    
    var id: String { get }
    var displayName: String { get }
    
    func makeView() -> WallpaperView
    func makeDebugControls() -> DebugControls?
    func reset()
}

extension Wallpaper {
    public var id: String { String(describing: type(of: self)) }
}
