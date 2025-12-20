//
//  Plugin.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
//

#if canImport(SwiftCompilerPlugin)
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct WallpaperMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        WallpaperMacro.self
    ]
}
#endif
