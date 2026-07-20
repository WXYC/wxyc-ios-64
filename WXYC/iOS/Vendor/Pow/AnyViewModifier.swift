//
//  Vendored verbatim from Pow — https://github.com/EmergeTools/Pow
//  Copyright (c) 2023 Emerge Tools, Inc. MIT License. See LICENSE in this directory.
//

import SwiftUI

internal struct AnyViewModifier: ViewModifier {
    private var _body: (Content) -> AnyView

    init<Modifier: ViewModifier>(_ modifier: Modifier) {
        self._body = { content in
            AnyView(content.modifier(modifier))
        }
    }

    func body(content: Content) -> AnyView {
        _body(content)
    }
}

internal extension ViewModifier {
    func eraseToAnyViewModifier() -> AnyViewModifier {
        AnyViewModifier(self)
    }
}
