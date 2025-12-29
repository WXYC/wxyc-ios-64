import Caching
import Core
import Logger

/// Service that extracts and caches color palettes from images.
public actor ColorPaletteService {

    public enum Error: Swift.Error, Codable {
        case extractionFailed
    }

    private let extractor: DominantColorExtractor
    private let generator: PaletteGenerator
    private let cacheCoordinator: CacheCoordinator

    /// In-flight task deduplication.
    private var inflightTasks: [String: Task<ColorPalette?, Never>] = [:]

    public init(cacheCoordinator: CacheCoordinator = .AlbumArt) {
        self.extractor = DominantColorExtractor()
        self.generator = PaletteGenerator()
        self.cacheCoordinator = cacheCoordinator
    }

    /// Fetches or generates a color palette for the given image and cache key.
    /// - Parameters:
    ///   - image: The source image.
    ///   - cacheKey: A unique identifier for caching (typically artist-album).
    ///   - mode: The palette generation mode.
    /// - Returns: The generated ColorPalette.
    public func palette(
        for image: Image,
        cacheKey: String,
        mode: PaletteMode
    ) async throws -> ColorPalette {
        let fullCacheKey = "palette_\(mode.rawValue)_\(cacheKey)"

        // Check for existing in-flight task
        if let existingTask = inflightTasks[fullCacheKey],
           let value = await existingTask.value {
            return value
        }

        // Check cache first
        if let cached: ColorPalette = try? await cacheCoordinator.value(for: fullCacheKey) {
            Log(.info, "Palette cache hit for \(fullCacheKey)")
            return cached
        }

        // Create new task
        let task = Task<ColorPalette?, Never> {
            defer { Task { self.removeTask(for: fullCacheKey) } }
            return await self.generateAndCachePalette(
                from: image,
                cacheKey: fullCacheKey,
                mode: mode
            )
        }

        inflightTasks[fullCacheKey] = task

        if let value = await task.value {
            return value
        } else {
            throw Error.extractionFailed
        }
    }

    /// Generates palettes for all modes at once (useful for UI that shows mode picker).
    public func allPalettes(
        for image: Image,
        cacheKey: String
    ) async throws -> [PaletteMode: ColorPalette] {
        // Extract dominant color once
        guard let dominantColor = extractor.extractDominantColor(from: image) else {
            throw Error.extractionFailed
        }

        var results: [PaletteMode: ColorPalette] = [:]

        // Generate all palettes
        for mode in PaletteMode.allCases {
            let palette = generator.generatePalette(from: dominantColor, mode: mode)
            results[mode] = palette

            // Cache each palette
            let fullCacheKey = "palette_\(mode.rawValue)_\(cacheKey)"
            await cacheCoordinator.set(value: palette, for: fullCacheKey, lifespan: .thirtyDays)
        }

        return results
    }

    // MARK: - Private

    private func generateAndCachePalette(
        from image: Image,
        cacheKey: String,
        mode: PaletteMode
    ) async -> ColorPalette? {
        guard let dominantColor = extractor.extractDominantColor(from: image) else {
            Log(.error, "Failed to extract dominant color for \(cacheKey)")
            return nil
        }

        let palette = generator.generatePalette(from: dominantColor, mode: mode)

        // Cache the result
        await cacheCoordinator.set(value: palette, for: cacheKey, lifespan: .thirtyDays)

        Log(.info, "Generated and cached palette for \(cacheKey)")
        return palette
    }

    private func removeTask(for key: String) {
        inflightTasks[key] = nil
    }
}
