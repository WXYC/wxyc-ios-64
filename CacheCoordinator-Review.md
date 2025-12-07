# CacheCoordinator Review

## Overall Assessment

The CacheCoordinator is a well-intentioned caching layer with actor-based concurrency, but it has **several critical bugs** and design issues that need attention.

---

## Critical Issues

### 1. **Broken Purge Logic** (Lines 102-123)
The `purgeRecords()` method has multiple serious problems:

**a) Type Erasure Bug**: Line 108 decodes all records as `CachedRecord<String>`, which will fail for any non-string cached values:
```swift
let record: CachedRecord<String> = try self.decode(value: value, forKey: key)
```
This means purging will fail for most of your cached data and you're catching/ignoring those errors.

**b) Inverted Logic**: Line 109 purges records with `lifespan == .distantFuture`:
```swift
if record.isExpired || record.lifespan == .distantFuture {
```
Why would you delete records that should last forever? This seems backwards.

**c) Actor Isolation Violation**: The method is `nonisolated` but accesses `self.cache` and creates a Task. The cache operations happen outside the actor's isolation domain, potentially causing race conditions.

### 2. **Unsafe Error Logging** (Line 86)
```swift
Log(.error, "\(try Self.decoder.decode(CachedRecord<String>.self, from: value))")
```
This unguarded `try` can crash. It's attempting to decode as String for debugging, but this will fail for non-string types.

### 3. **Dead Code** (Lines 126-203)
Large block of `#if false` code should be removed entirely—it's confusing and adds maintenance burden.

---

## Design Issues

### 4. **Missing Public API**
No way to:
- Check if a key exists without throwing
- Clear specific keys
- Clear all cache
- Get cache statistics
- Check expiration without retrieving value

### 5. **Poor Error Handling Strategy**
- Only one error case (`noCachedResult`) used for multiple scenarios
- No distinction between "not found", "expired", "decode failed"
- Callers can't differentiate cache miss from corrupted data

### 6. **Logging is Too Verbose** (Line 55)
Every cache set logs, which could spam logs in production:
```swift
Log(.info, "Setting value for key \(key)...")
```

### 7. **No Documentation**
Public API lacks doc comments explaining:
- What lifespan values mean (0 = no expiration? negative values?)
- Thread safety guarantees
- Error handling contract

---

## Minor Issues

### 8. **Static Singleton Anti-pattern** (Line 7)
```swift
public static let AlbumArt = CacheCoordinator(cache: DiskCache())
```
This hardcodes DiskCache and makes testing difficult. Consider dependency injection.

### 9. **Inconsistent Access Control**
- `init` is `internal` but there's a public static instance
- Seems like init should be public for testability

### 10. **PostHog Special Case** (Line 87-96)
```swift
if Value.self != CachedRecord<MultisourceArtworkService.Error>.self {
```
This tight coupling to a specific type is a code smell.

---

## Recommendations

### Immediate Fixes (Critical):
1. Fix `purgeRecords()` to handle generic types properly (use metadata or type-erased approach)
2. Remove the `.distantFuture` purge logic or fix if inverted
3. Wrap the unsafe `try` on line 86 in do-catch
4. Make `purgeRecords()` properly isolated to the actor

### High Priority:
5. Add public methods for cache management (clear, remove, exists)
6. Create more specific error types
7. Remove dead code (#if false block)
8. Add comprehensive documentation

### Nice to Have:
9. Add cache size limits
10. Add cache eviction policies (LRU, etc.)
11. Add metrics/statistics
12. Make logging configurable/less verbose
