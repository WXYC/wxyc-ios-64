
import XCTest
@testable import Core

final class DiskCacheReproductionTests: XCTestCase {
    var cache: DiskCache!
    var fileManager: FileManager!
    var cacheDirectory: URL!
    
    override func setUp() {
        super.setUp()
        cache = DiskCache()
        fileManager = FileManager.default
        cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
    }
    
    override func tearDown() {
        cache = nil
        fileManager = nil
        super.tearDown()
    }
    
    func testCorruptedFileHandling() async throws {
        let key = "corrupted_file"
        let fileURL = cacheDirectory.appendingPathComponent(key)
        
        // 1. Create a file that is not valid Data (e.g. a directory pretending to be a file, or just garbage)
        // Actually, any file content is valid Data.
        // To simulate "corruption" that causes Data(contentsOf:) to fail, we can make it unreadable?
        // Or we can simulate the "decoding" failure at the CacheCoordinator level.
        
        // Let's test that DiskCache.object(for:) returns nil if the file exists but we can't read it.
        // It's hard to simulate "unreadable" without changing permissions, which might be tricky in simulator.
        
        // Instead, let's verify that CacheCoordinator handles decoding errors by NOT deleting the file?
        // Wait, CacheCoordinator.value(for:) throws if decoding fails.
        // It does NOT delete the file.
        // So the file stays in cache.
        // Next time app launches, it reads the SAME bad file, fails again.
        // This matches the "persistent" symptom.
        
        // Let's verify this behavior.
        
        let badData = "Not a JSON".data(using: .utf8)!
        await cache.set(object: badData, for: key, lifespan: nil)
        
        // Verify we can read it back as Data
        let retrievedData = await cache.object(for: key)
        XCTAssertEqual(retrievedData, badData)
        
        // Now try to decode it as a Playlist using CacheCoordinator logic (simulated)
        // CacheCoordinator code:
        /*
         let value = try self.decode(data: data, forKey: key, as: Value.self)
         */
        
        // If decoding fails, CacheCoordinator throws.
        // It does NOT call cache.set(nil) to remove it.
        
        // So the fix should be in CacheCoordinator (or DiskCache) to remove the file if it's invalid.
        // But CacheCoordinator doesn't know if it's "invalid" or just "wrong type".
        // However, for a specific key, the type should be constant.
        
        // If I change DiskCache to delete the file on read error, that only helps if Data(contentsOf:) fails.
        // If Data(contentsOf:) succeeds but JSONDecoder fails, DiskCache doesn't know.
        
        // So I should modify CacheCoordinator to delete the cache entry if decoding fails.
    }
}
