import Testing
import Foundation
@testable import Playlist

// MARK: - Mock Feature Flag Provider

final class MockFeatureFlagProvider: FeatureFlagProvider {
    var flagValues: [String: Any] = [:]

    func getFeatureFlag(_ key: String) -> Any? {
        flagValues[key]
    }
}

// MARK: - PlaylistAPIVersion Tests

@Suite("PlaylistAPIVersion Tests")
struct PlaylistAPIVersionTests {

    /// Creates a fresh UserDefaults instance for isolated testing.
    private func makeTestDefaults() -> UserDefaults {
        let suiteName = "com.wxyc.test.PlaylistAPIVersionTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    @Test("Returns default version when no override and no feature flag")
    func defaultsToV1WhenNoOverrideOrFlag() {
        let mockProvider = MockFeatureFlagProvider()
        let defaults = makeTestDefaults()

        let version = PlaylistAPIVersion.loadActive(
            featureFlagProvider: mockProvider,
            defaults: defaults
        )

        #expect(version == .v1)
        #expect(version == PlaylistAPIVersion.defaultVersion)
    }

    @Test("Returns v2 when feature flag is set to v2")
    func returnsV2WhenFeatureFlagIsV2() {
        let mockProvider = MockFeatureFlagProvider()
        mockProvider.flagValues[PlaylistAPIVersion.featureFlagKey] = "v2"
        let defaults = makeTestDefaults()

        let version = PlaylistAPIVersion.loadActive(
            featureFlagProvider: mockProvider,
            defaults: defaults
        )

        #expect(version == .v2)
    }

    @Test("Returns v1 when feature flag is set to v1")
    func returnsV1WhenFeatureFlagIsV1() {
        let mockProvider = MockFeatureFlagProvider()
        mockProvider.flagValues[PlaylistAPIVersion.featureFlagKey] = "v1"
        let defaults = makeTestDefaults()

        let version = PlaylistAPIVersion.loadActive(
            featureFlagProvider: mockProvider,
            defaults: defaults
        )

        #expect(version == .v1)
    }

    @Test("Manual override takes priority over feature flag")
    func manualOverrideTakesPriority() {
        let mockProvider = MockFeatureFlagProvider()
        mockProvider.flagValues[PlaylistAPIVersion.featureFlagKey] = "v1"
        let defaults = makeTestDefaults()

        // Set manual override to v2
        PlaylistAPIVersion.v2.persist(to: defaults)

        let version = PlaylistAPIVersion.loadActive(
            featureFlagProvider: mockProvider,
            defaults: defaults
        )

        #expect(version == .v2)
    }

    @Test("Clearing override reverts to feature flag")
    func clearingOverrideRevertsToFeatureFlag() {
        let mockProvider = MockFeatureFlagProvider()
        mockProvider.flagValues[PlaylistAPIVersion.featureFlagKey] = "v2"
        let defaults = makeTestDefaults()

        // Set manual override to v1
        PlaylistAPIVersion.v1.persist(to: defaults)
        #expect(PlaylistAPIVersion.loadActive(featureFlagProvider: mockProvider, defaults: defaults) == .v1)

        // Clear override
        PlaylistAPIVersion.clearOverride(from: defaults)

        let version = PlaylistAPIVersion.loadActive(
            featureFlagProvider: mockProvider,
            defaults: defaults
        )

        #expect(version == .v2)
    }

    @Test("Invalid feature flag value falls back to default")
    func invalidFeatureFlagFallsBackToDefault() {
        let mockProvider = MockFeatureFlagProvider()
        mockProvider.flagValues[PlaylistAPIVersion.featureFlagKey] = "v3"  // Invalid
        let defaults = makeTestDefaults()

        let version = PlaylistAPIVersion.loadActive(
            featureFlagProvider: mockProvider,
            defaults: defaults
        )

        #expect(version == .v1)
    }

    @Test("Non-string feature flag value falls back to default")
    func nonStringFeatureFlagFallsBackToDefault() {
        let mockProvider = MockFeatureFlagProvider()
        mockProvider.flagValues[PlaylistAPIVersion.featureFlagKey] = true  // Boolean, not string
        let defaults = makeTestDefaults()

        let version = PlaylistAPIVersion.loadActive(
            featureFlagProvider: mockProvider,
            defaults: defaults
        )

        #expect(version == .v1)
    }

    @Test("Persist saves to UserDefaults correctly")
    func persistSavesToDefaults() {
        let defaults = makeTestDefaults()

        PlaylistAPIVersion.v2.persist(to: defaults)

        #expect(defaults.bool(forKey: "debug.isPlaylistAPIManuallySelected") == true)
        #expect(defaults.string(forKey: "debug.selectedPlaylistAPIVersion") == "v2")
    }

    @Test("ClearOverride removes from UserDefaults")
    func clearOverrideRemovesFromDefaults() {
        let defaults = makeTestDefaults()

        PlaylistAPIVersion.v2.persist(to: defaults)
        PlaylistAPIVersion.clearOverride(from: defaults)

        #expect(defaults.bool(forKey: "debug.isPlaylistAPIManuallySelected") == false)
        #expect(defaults.string(forKey: "debug.selectedPlaylistAPIVersion") == nil)
    }

    @Test("Feature flag key is correct")
    func featureFlagKeyIsCorrect() {
        #expect(PlaylistAPIVersion.featureFlagKey == "playlist_api_version")
    }

    @Test("All cases are identifiable")
    func allCasesAreIdentifiable() {
        for version in PlaylistAPIVersion.allCases {
            #expect(version.id == version.rawValue)
        }
    }

    @Test("Display names are set")
    func displayNamesAreSet() {
        #expect(PlaylistAPIVersion.v1.displayName == "v1 (Legacy)")
        #expect(PlaylistAPIVersion.v2.displayName == "v2 (Flowsheet)")
    }

    @Test("Short descriptions are set")
    func shortDescriptionsAreSet() {
        #expect(PlaylistAPIVersion.v1.shortDescription == "wxyc.info/playlists/recentEntries")
        #expect(PlaylistAPIVersion.v2.shortDescription == "api.wxyc.org/flowsheet")
    }
}
