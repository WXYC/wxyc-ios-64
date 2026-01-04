import Foundation
import Testing
@testable import Wallpaper

@Suite("ThermalProfile")
struct ThermalProfileTests {

    @Test("Default profile has max quality")
    func defaultProfile() {
        let profile = ThermalProfile(shaderId: "test")

        #expect(profile.fps == 60.0)
        #expect(profile.scale == 1.0)
        #expect(profile.thermalMomentum == 0)
        #expect(profile.sampleCount == 0)
        #expect(profile.isStabilized == false)
        #expect(profile.sessionsToStability == nil)
    }

    @Test("Values are clamped to valid ranges")
    func valuesClamped() {
        let profile = ThermalProfile(
            shaderId: "test",
            fps: 100,  // Above max
            scale: 0.1  // Below min
        )

        #expect(profile.fps == 60.0)
        #expect(profile.scale == 0.5)
    }

    @Test("Update increments sample count")
    func updateIncrementsSampleCount() {
        var profile = ThermalProfile(shaderId: "test")

        profile.update(fps: 55, scale: 0.9)
        #expect(profile.sampleCount == 1)

        profile.update(fps: 50, scale: 0.8)
        #expect(profile.sampleCount == 2)
    }

    @Test("isAtMaxQuality returns correct value")
    func isAtMaxQuality() {
        let maxProfile = ThermalProfile(shaderId: "test", fps: 60, scale: 1.0)
        #expect(maxProfile.isAtMaxQuality)

        let throttledProfile = ThermalProfile(shaderId: "test", fps: 45, scale: 0.8)
        #expect(!throttledProfile.isAtMaxQuality)
    }

    @Test("markStabilized sets fields correctly")
    func markStabilized() {
        var profile = ThermalProfile(shaderId: "test")
        profile.update(fps: 55, scale: 0.9)
        profile.update(fps: 50, scale: 0.85)
        profile.update(fps: 50, scale: 0.85)

        profile.markStabilized()

        #expect(profile.isStabilized)
        #expect(profile.sessionsToStability == 3)
    }

    @Test("markStabilized only works once")
    func markStabilizedOnlyOnce() {
        var profile = ThermalProfile(shaderId: "test")
        profile.update(fps: 55, scale: 0.9)
        profile.markStabilized()

        let firstValue = profile.sessionsToStability

        profile.update(fps: 50, scale: 0.85)
        profile.markStabilized()

        #expect(profile.sessionsToStability == firstValue)
    }

    @Test("Profile is Codable")
    func codable() throws {
        let original = ThermalProfile(
            shaderId: "pool_tiles",
            fps: 45,
            scale: 0.75,
            thermalMomentum: 0.5,
            sampleCount: 10,
            sessionsToStability: 5,
            isStabilized: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ThermalProfile.self, from: data)

        #expect(decoded == original)
    }
}
