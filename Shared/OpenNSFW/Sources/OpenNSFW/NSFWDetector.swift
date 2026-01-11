//
// https://github.com/OurBigAdventure/Swift_NSFW_Detector
//

#if canImport(UIKit) && canImport(Vision)
import CoreML
import Vision
import ImageIO
import Logger
import UIKit

public enum NSFW: Sendable {
    case sfw
    case nsfw
}

public enum NSFWAnalysisError: Error, Sendable {
    case invalidImage
    case coreMLError(_ error: any Error)
    case invalidObservationType
    case noObservations
    case unknown
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default:
            self = .up
            Log(.error, "Unknown UIImage Orientation. Set as .up by default.")
        }
    }
}

/// Returns the URL to the OpenNSFW model, checking the shared container first
/// (for widgets/extensions), then falling back to the main app bundle.
private func openNSFWModelURL() -> URL? {
    // Check shared container first (for widgets that don't have the model bundled)
    if let sharedURL = ModelSeeder.sharedModelURL,
       FileManager.default.fileExists(atPath: sharedURL.path) {
        return sharedURL
    }
    // Fall back to main app bundle (model is only included in main app target)
    return Bundle.main.url(forResource: "OpenNSFW", withExtension: "mlmodelc")
}

/// Performs NSFW detection on images using the OpenNSFW CoreML model.
/// This type is nonisolated to allow ML processing to run off the main actor.
public struct NSFWDetector: Sendable {
    public init() {}

    /// Analyzes a CGImage for NSFW content.
    /// - Parameters:
    ///   - cgImage: The image to analyze.
    ///   - orientation: The image orientation for proper analysis.
    /// - Returns: `.sfw` or `.nsfw` classification result.
    public func checkNSFW(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> NSFW {
        // Check for model availability - return permissive fallback if not found
        // (e.g., widget before main app seeds model to shared container)
        guard let modelURL = openNSFWModelURL() else {
            Log(.info, "OpenNSFW model not available, assuming SFW")
            return .sfw
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        let modelConfig = MLModelConfiguration()
        let model = try OpenNSFW(contentsOf: modelURL, configuration: modelConfig)
        let visionModel = try VNCoreMLModel(for: model.model)

        return try await withCheckedThrowingContinuation { continuation in
            let vnRequest = VNCoreMLRequest(model: visionModel) { request, error in
                if let error {
                    Log(.error, "VNCoreMLRequest Error: \(error.localizedDescription)")
                    continuation.resume(throwing: NSFWAnalysisError.coreMLError(error))
                    return
                }
                guard let observations = request.results as? [VNClassificationObservation] else {
                    Log(.error, "Unexpected result type from VNCoreMLRequest")
                    continuation.resume(throwing: NSFWAnalysisError.invalidObservationType)
                    return
                }
                guard let best = observations.first else {
                    Log(.error, "Unable to retrieve NSFW observation")
                    continuation.resume(throwing: NSFWAnalysisError.noObservations)
                    return
                }
                switch best.identifier {
                case "NSFW":
                    continuation.resume(returning: .nsfw)
                case "SFW":
                    continuation.resume(returning: .sfw)
                default:
                    continuation.resume(throwing: NSFWAnalysisError.unknown)
                }
            }

            do {
                try handler.perform([vnRequest])
            } catch {
                continuation.resume(throwing: NSFWAnalysisError.coreMLError(error))
            }
        }
    }
}

/// Convenience extension for UIImage that delegates to NSFWDetector.
public extension UIImage {
    /// Analyzes the image for NSFW content.
    /// The analysis runs off the main actor to avoid blocking the UI.
    func checkNSFW() async throws -> NSFW {
        guard let cgImage = self.cgImage?.copy() else {
            Log(.error, "Could not get CGImage from UIImage")
            throw NSFWAnalysisError.invalidImage
        }

        let orientation = CGImagePropertyOrientation(self.imageOrientation)

        // Run the detection off the main actor
        return try await Task.detached {
            try await NSFWDetector().checkNSFW(cgImage: cgImage, orientation: orientation)
        }.value
    }
}
#endif
