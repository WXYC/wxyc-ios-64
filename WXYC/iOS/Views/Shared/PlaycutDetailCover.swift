//
//  PlaycutDetailCover.swift
//  WXYC
//
//  The standard playcut detail presentation shared by `RootTabView` (the
//  flowsheet's row -> detail zoom) and `LikedTabView` (the Liked row -> detail
//  zoom): a `.fullScreenCover(item:)` paired with `.navigationTransition(.zoom)`
//  rather than a plain sheet, so the tapped row's drag-to-dismiss survives (a
//  plain `.fullScreenCover` alone drops it). Both call sites used to duplicate
//  this pairing, the `.environment(appState)` re-injection comment included
//  verbatim, since each tab keeps its own private `selectedPlaycut` state.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

extension View {
    /// Presents the standard playcut detail card: a full-screen cover that the
    /// selected row zooms into, keyed on `selection` and animated through
    /// `namespace`. Callers own their own `selection` state (each tab keeps its
    /// presentation private) and pass the same `Namespace.ID` their rows used for
    /// `.matchedTransitionSource(id:in:)`.
    func playcutDetailCover(
        selection: Binding<PlaycutSelection?>,
        in namespace: Namespace.ID
    ) -> some View {
        modifier(PlaycutDetailCoverModifier(selection: selection, namespace: namespace))
    }
}

private struct PlaycutDetailCoverModifier: ViewModifier {
    @Binding var selection: PlaycutSelection?
    let namespace: Namespace.ID
    @Environment(Singletonia.self) private var appState

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $selection) { selection in
                PlaycutDetailView(playcut: selection.playcut, artwork: selection.artwork)
                    .navigationTransition(.zoom(sourceID: selection.transitionID, in: namespace))
                    // The cover hosts the detail in a separate presentation context, so
                    // the `@Environment(Singletonia.self)` it reads has to be re-injected
                    // here — the old inline `.overlaySheet` shared this tree and got it
                    // for free. Without this, the zoom-transition presentation bridge
                    // traps force-unwrapping the missing observable.
                    .environment(appState)
            }
    }
}
