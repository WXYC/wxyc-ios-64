//
// https://github.com/OurBigAdventure/Swift_NSFW_Detector
//

import UIKit
import CoreML
import Vision
import ImageIO

enum NSFW {
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

extension UIImage {
    enum AnalysisError: Error {
        case InvalidImage
        case CoreMLError(_ error: Error)
        case InvalidObservationType
        case NoObservations
        case Unknown
    }
    
    func checkNSFW() async throws -> NSFW {
        guard let ciImage = CIImage(image: self) else {
            Log(.error, "🧨 Could not create CIImage")
            throw AnalysisError.InvalidImage
        }
        let orientation = CGImagePropertyOrientation(self.imageOrientation)
        let handler = VNImageRequestHandler(ciImage: ciImage, orientation: orientation, options: [:])
        let modelConfig = MLModelConfiguration()
        let model = try OpenNSFW(configuration: modelConfig)
        let NSFWmodel = try VNCoreMLModel(for: model.model)
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSFW, any Error>) in
            let vnRequest = VNCoreMLRequest(model: NSFWmodel, completionHandler: { request, error in
                if let error = error {
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
