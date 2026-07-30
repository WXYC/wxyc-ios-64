//
//  UserNotificationTourAlertScheduler.swift
//  WXYC
//
//  Dev-only concrete `TourAlertScheduling` backed by `UNUserNotificationCenter`.
//  Requests alert/sound authorization lazily on the first post (so an unrelated
//  cold launch never prompts), presents the banner even while the app is
//  foregrounded (so the alert is visible during testing without locking the
//  device), and stashes the concert id in `userInfo` for a future tap-to-open.
//
//  Compiled only into Debug builds — the whole "artist on tour" alert feature is
//  dev-only for now, and the `#if DEBUG` fence here (plus the matching fence
//  around the wiring in `Singletonia`) is what keeps it out of TestFlight/App
//  Store binaries. Local notifications need no push entitlement or Info.plist
//  key, so this adds no project/entitlement surface.
//
//  Created by Jake Bromberg on 07/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if DEBUG
import AppServices
import Foundation
import Logger
import UserNotifications

/// Posts tour alerts to the system notification center. `@MainActor`-isolated so
/// it is `Sendable` (satisfying ``TourAlertScheduling``) while still conforming to
/// the `@objc` `UNUserNotificationCenterDelegate`.
@MainActor
final class UserNotificationTourAlertScheduler: NSObject, TourAlertScheduling {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        // Retained by the owning coordinator (in turn retained by `Singletonia`),
        // which matters because `center.delegate` is a weak reference.
        center.delegate = self
    }

    func post(_ alert: TourAlert) async {
        guard await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.userInfo = ["concertID": alert.concertID]

        // `identifier` keyed on the concert so a re-add replaces rather than
        // stacks; `trigger: nil` delivers immediately.
        let request = UNNotificationRequest(
            identifier: "tour-alert-\(alert.concertID)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            Log(.warning, "Tour alert post failed: \(error)")
        }
    }

    /// Requests `[.alert, .sound]` authorization the first time it's needed and
    /// reports whether alerts may be presented. Never re-prompts once decided.
    private func ensureAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}

extension UserNotificationTourAlertScheduler: UNUserNotificationCenterDelegate {
    /// Present the banner even while the app is foregrounded, so a tour alert is
    /// visible during testing without locking the device.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
#endif
