import Foundation
import Testing
@testable import Wallpaper

@Suite("ThermalProfileStore")
@MainActor
struct ThermalProfileStoreTests {

    /// Creates a fresh store with isolated UserDefaults for testing.
    func makeTestStore() -> ThermalProfileStore {
        let defaults = UserDefaults(suiteName: "ThermalProfileStoreTests-\(UUID().uuidString)")!
        return ThermalProfileStore(defaults: defaults)
    }

    @Test("Load returns default profile for new shader")
    func loadNewShader() {
        let store = makeTestStore()

        let profile = store.load(shaderId: "new_shader")

        #expect(profile.shaderId == "new_shader")
        #expect(profile.wallpaperFPS == 60.0)
        #expect(profile.scale == 1.0)
        #expect(profile.lod == 1.0)
    }

    @Test("Save and load roundtrip")
    func saveAndLoad() {
        let store = makeTestStore()

        var profile = ThermalProfile(shaderId: "test_shader", wallpaperFPS: 45, scale: 0.8, lod: 0.7)
        profile.thermalMomentum = 0.3
        profile.sampleCount = 5

        store.save(profile)

        // Clear memory cache to force disk read
        store.clearMemoryCache()

        let loaded = store.load(shaderId: "test_shader")

        #expect(loaded.wallpaperFPS == 45)
        #expect(loaded.scale == 0.8)
        #expect(loaded.lod == 0.7)
        #expect(loaded.thermalMomentum == 0.3)
        #expect(loaded.sampleCount == 5)
    }

    @Test("cachedProfile returns nil before load")
    func cachedProfileBeforeLoad() {
        let store = makeTestStore()

        let cached = store.cachedProfile(for: "uncached")

        #expect(cached == nil)
    }

    @Test("cachedProfile returns profile after load")
    func cachedProfileAfterLoad() {
        let store = makeTestStore()

        _ = store.load(shaderId: "cached")
        let cached = store.cachedProfile(for: "cached")

        #expect(cached != nil)
        #expect(cached?.shaderId == "cached")
    }

    @Test("Remove deletes profile")
    func removeProfile() {
        let store = makeTestStore()

        var profile = ThermalProfile(shaderId: "to_delete", wallpaperFPS: 30, scale: 0.6)
        store.save(profile)

        store.remove(shaderId: "to_delete")
        store.clearMemoryCache()

        let loaded = store.load(shaderId: "to_delete")

        // Should get default profile back
        #expect(loaded.wallpaperFPS == 60.0)
        #expect(loaded.scale == 1.0)
    }

    @Test("Multiple shaders are independent")
    func multipleShaders() {
        let store = makeTestStore()

        let profile1 = ThermalProfile(shaderId: "shader1", wallpaperFPS: 30, scale: 0.6)
        let profile2 = ThermalProfile(shaderId: "shader2", wallpaperFPS: 45, scale: 0.8)

        store.save(profile1)
        store.save(profile2)
        store.clearMemoryCache()

        let loaded1 = store.load(shaderId: "shader1")
        let loaded2 = store.load(shaderId: "shader2")

        #expect(loaded1.wallpaperFPS == 30)
        #expect(loaded2.wallpaperFPS == 45)
    }
}
