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
            Log(.error, "🧨 Unknown UIImage Orientation. Set as .up by default.")
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

public extension UIImage {
    enum AnalysisError: Error {
        case InvalidImage
        case CoreMLError(_ error: Error)
        case InvalidObservationType
        case NoObservations
        case Unknown
        case ModelNotFound
    }
    
    func checkNSFW() async throws -> NSFW {
        guard let ciImage = CIImage(image: self) else {
            Log(.error, "🧨 Could not create CIImage")
            throw AnalysisError.InvalidImage
        }
        
        // Check for model availability - return permissive fallback if not found
        // (e.g., widget before main app seeds model to shared container)
        guard let modelURL = openNSFWModelURL() else {
            Log(.info, "OpenNSFW model not available, assuming SFW")
            return .sfw
        }
        
        let orientation = CGImagePropertyOrientation(self.imageOrientation)
        let handler = VNImageRequestHandler(ciImage: ciImage, orientation: orientation, options: [:])
        let modelConfig = MLModelConfiguration()
        let model = try OpenNSFW(contentsOf: modelURL, configuration: modelConfig)
        let NSFWmodel = try VNCoreMLModel(for: model.model)
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSFW, any Error>) in
            let vnRequest = VNCoreMLRequest(model: NSFWmodel, completionHandler: { request, error in
                if let error {
                    Log(.error, "🧨 VNCoreMLRequest Error: \(error.localizedDescription)")
                    continuation.resume(throwing: AnalysisError.CoreMLError(error))
                }
                guard let observations = request.results as? [VNClassificationObservation] else {
                    Log(.error, "🧨 Unexpected result type from VNCoreMLRequest")
                    continuation.resume(throwing: AnalysisError.InvalidObservationType)
                    return
                }
                guard let best = observations.first else {
                    Log(.error, "🧨 Unable to retrieve NSFW observation")
                    continuation.resume(throwing: AnalysisError.NoObservations)
                    return
                }
                switch best.identifier {
                case "NSFW":
                    continuation.resume(returning: .nsfw)
                case "SFW": continuation.resume(returning: .sfw)
                default: continuation.resume(throwing: AnalysisError.Unknown)
                }
            })
            
            do {
                try handler.perform([vnRequest])
            } catch {
                continuation.resume(throwing: AnalysisError.CoreMLError(error))
            }
        }
    }
}
#endif
