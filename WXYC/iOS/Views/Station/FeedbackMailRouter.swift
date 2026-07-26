//
//  FeedbackMailRouter.swift
//  WXYC
//
//  Decides how a "Send feedback" tap reaches the user's mail. When the device
//  has a configured Mail account we present the in-app MFMailComposeViewController;
//  when it doesn't (`canSendMail()` is false), presenting that controller aborts
//  inside SwiftUI's sheet hosting on iOS 26 — a null dynamic-cast fatalError in
//  UICorePlatformViewHost.init while the form sheet's presentation transition is
//  beginning. So we instead hand the address to the system via a mailto: URL,
//  which any registered mail handler (or the Mail app's add-account prompt) can
//  pick up. Kept free of MessageUI so the decision is unit-testable: the caller
//  passes `canSendMail` in.
//
//  Created by Jake Bromberg on 07/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Where a feedback-email tap should be delivered.
enum FeedbackMailRoute: Equatable {
    /// The device can compose mail in-app; present the embedded composer.
    case inAppComposer
    /// The device can't compose in-app; hand the address off to the system via
    /// a `mailto:` URL.
    case externalMailto(URL)
}

/// Pure routing for the Station tab's "Send feedback" flow.
enum FeedbackMailRouter {
    /// The address every feedback path targets.
    static let recipient = "feedback@wxyc.org"

    /// The message shown when the device can neither compose in-app nor open a
    /// `mailto:` URL (no Mail account and no registered handler). It names the
    /// address in plain text so the tap isn't a dead end — the user still sees
    /// where to reach us instead of nothing happening.
    static var noMailHandlerMessage: String {
        "You can email us at \(recipient)."
    }

    /// Chooses the delivery route for a feedback email.
    /// - Parameters:
    ///   - canSendMail: The result of `MFMailComposeViewController.canSendMail()`
    ///     at the call site. `false` means presenting the in-app composer would
    ///     crash, so we fall back to `mailto:`.
    ///   - subject: The pre-filled subject line, shared with the in-app composer
    ///     so both paths read identically.
    static func route(canSendMail: Bool, subject: String) -> FeedbackMailRoute {
        canSendMail ? .inAppComposer : .externalMailto(mailtoURL(subject: subject))
    }

    /// Builds a `mailto:` URL for the feedback address with a pre-filled,
    /// percent-encoded subject. `URLComponents` always yields a URL for a
    /// well-formed address and query, so the coalescing branch is unreachable
    /// in practice and exists only to avoid a force-unwrap.
    static func mailtoURL(subject: String) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        return components.url ?? URL(string: "mailto:\(recipient)") ?? URL(filePath: "/")
    }
}
