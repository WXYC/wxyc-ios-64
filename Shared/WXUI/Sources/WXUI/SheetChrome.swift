//
//  SheetChrome.swift
//  WXUI
//
//  The `navigationTitle` + inline title-display-mode + "Done" toolbar button
//  duplicated across every sheet in the app — byte-identical in four DebugPanel
//  views, and the same shape (minus the platform guard, since those files are
//  already iOS-only) in three app sheets. One modifier instead of the repeated
//  stanza; the `#if os(iOS)` guard for inline mode lives inside it, so callers
//  never repeat the guard either.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

public extension View {
    /// Standard sheet chrome for a `NavigationStack`-wrapped sheet: sets the
    /// navigation title, forces inline title display on iOS (a no-op on
    /// platforms without the distinction), and — when `showsDoneButton` is
    /// `true` (the default) — adds a "Done" toolbar button at
    /// `.cancellationAction` that dismisses the sheet via `\.dismiss`.
    ///
    /// Pass `showsDoneButton: false` when the sheet already supplies its own
    /// dismiss control with a different placement or label (a "Cancel" /
    /// "Send" pair, say, or a leading control that would collide with the
    /// canon Done button's leading placement) — apply `sheetChrome` for the
    /// title/display-mode part and keep the sheet's own `.toolbar` for the
    /// rest.
    ///
    /// - Parameters:
    ///   - title: The sheet's navigation title.
    ///   - showsDoneButton: Whether to add the canon "Done" toolbar button.
    ///     Default `true`.
    func sheetChrome(title: String, showsDoneButton: Bool = true) -> some View {
        modifier(SheetChromeModifier(title: title, showsDoneButton: showsDoneButton))
    }
}

private struct SheetChromeModifier: ViewModifier {
    let title: String
    let showsDoneButton: Bool

    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
    }
}
