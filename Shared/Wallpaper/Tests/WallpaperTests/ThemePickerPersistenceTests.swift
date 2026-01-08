import Foundation
import Testing
@testable import Wallpaper

@Suite("ThemePickerPersistence")
@MainActor
struct ThemePickerPersistenceTests {

    /// Creates a fresh persistence instance with isolated UserDefaults for testing.
    private func makePersistence() -> ThemePickerPersistence {
        let defaults = UserDefaults(suiteName: "ThemePickerPersistenceTests-\(UUID().uuidString)")!
        return ThemePickerPersistence(defaults: defaults)
    }

    // MARK: - Picker Usage Tests

    @Test("Initially reports picker never used")
    func initiallyNeverUsed() {
        let persistence = makePersistence()

        #expect(persistence.hasEverUsedPicker == false)
    }

    @Test("Records picker usage")
    func recordsPickerUsage() {
        let persistence = makePersistence()

        persistence.recordPickerUsed()

        #expect(persistence.hasEverUsedPicker == true)
    }

    @Test("Recording picker usage is idempotent")
    func recordPickerUsageIdempotent() {
        let persistence = makePersistence()

        persistence.recordPickerUsed()
        persistence.recordPickerUsed()
        persistence.recordPickerUsed()

        #expect(persistence.hasEverUsedPicker == true)
    }

    // MARK: - Tip Visibility Tests

    @Test("Shows tip when never dismissed and never used picker")
    func showsTipInitially() {
        let persistence = makePersistence()

        #expect(persistence.shouldShowTip == true)
    }

    @Test("Hides tip after picker is used")
    func hidesTipAfterPickerUsed() {
        let persistence = makePersistence()

        persistence.recordPickerUsed()

        #expect(persistence.shouldShowTip == false)
    }

    @Test("Hides tip after dismissal within cooldown period")
    func hidesTipAfterRecentDismissal() {
        let persistence = makePersistence()

        persistence.recordTipDismissed()

        #expect(persistence.shouldShowTip == false)
        #expect(persistence.tipDismissedAt != nil)
    }

    @Test("Re-shows tip after cooldown expires if picker never used")
    func reShowsTipAfterCooldown() {
        let defaults = UserDefaults(suiteName: "ThemePickerPersistenceTests-\(UUID().uuidString)")!
        let persistence = ThemePickerPersistence(defaults: defaults)

        // Simulate dismissal beyond cooldown (91 days ago)
        let dismissedAt = Date().addingTimeInterval(-91 * 86400)
        defaults.set(dismissedAt, forKey: "themeTip.dismissedAt")

        #expect(persistence.shouldShowTip == true)
    }

    @Test("Does not re-show tip after cooldown if picker was used")
    func staysHiddenIfPickerUsed() {
        let defaults = UserDefaults(suiteName: "ThemePickerPersistenceTests-\(UUID().uuidString)")!
        let persistence = ThemePickerPersistence(defaults: defaults)

        // Simulate dismissal beyond cooldown (91 days ago)
        let dismissedAt = Date().addingTimeInterval(-91 * 86400)
        defaults.set(dismissedAt, forKey: "themeTip.dismissedAt")

        // But user has used the picker
        persistence.recordPickerUsed()

        #expect(persistence.shouldShowTip == false)
    }

    @Test("Does not re-show tip before cooldown expires")
    func staysHiddenBeforeCooldown() {
        let defaults = UserDefaults(suiteName: "ThemePickerPersistenceTests-\(UUID().uuidString)")!
        let persistence = ThemePickerPersistence(defaults: defaults)

        // Simulate dismissal before cooldown (89 days ago)
        let dismissedAt = Date().addingTimeInterval(-89 * 86400)
        defaults.set(dismissedAt, forKey: "themeTip.dismissedAt")

        #expect(persistence.shouldShowTip == false)
    }

    @Test("Cooldown boundary is exactly 90 days")
    func cooldownBoundary() {
        let defaults = UserDefaults(suiteName: "ThemePickerPersistenceTests-\(UUID().uuidString)")!
        let persistence = ThemePickerPersistence(defaults: defaults)

        // Exactly 90 days ago should re-show
        let dismissedAt = Date().addingTimeInterval(-90 * 86400)
        defaults.set(dismissedAt, forKey: "themeTip.dismissedAt")

        #expect(persistence.shouldShowTip == true)
    }

    // MARK: - Reset Tests

    @Test("Reset clears all state")
    func resetClearsAllState() {
        let persistence = makePersistence()

        persistence.recordPickerUsed()
        persistence.recordTipDismissed()
        #expect(persistence.hasEverUsedPicker == true)
        #expect(persistence.tipDismissedAt != nil)

        persistence.resetState()

        #expect(persistence.hasEverUsedPicker == false)
        #expect(persistence.tipDismissedAt == nil)
        #expect(persistence.shouldShowTip == true)
    }
}
