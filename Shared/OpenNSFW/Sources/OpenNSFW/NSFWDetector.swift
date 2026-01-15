//
//  NSFWDetector.swift
//  OpenNSFW
//
//  NSFW content detection using CoreML model. Uses an actor to cache the
//  model instance, eliminating repeated loading warnings.
//
//  Created by Jake Bromberg on 03/21/24.
//  Copyright © 2024 WXYC. All rights reserved.
//

#if canImport(Vision)
import CoreML
import Vision
import Logger

public enum NSFW: Sendable {
    case sfw
    case nsfw
}

public enum NSFWAnalysisError: Error, Sendable {
    case modelNotFound
    case coreMLError(_ error: any Error)
    case invalidObservationType
    case noObservations
    case unknown
}

/// Returns the URL to the OpenNSFW model, checking the shared container first
/// (for widgets/extensions), then falling back to the main app bundle.
private func openNSFWModelURL() -> URL? {
    // Check shared container first (seeded by main app for extensions)
    if let sharedURL = ModelSeeder.sharedModelURL,
       FileManager.default.fileExists(atPath: sharedURL.path) {
        return sharedURL
    }
    // Fall back to the bundle (main app or widget)
    return Bundle.main.url(forResource: "OpenNSFW", withExtension: "mlmodelc")
}

/// Actor that caches the loaded CoreML model and performs classification.
/// Keeping the model inside the actor avoids Sendable issues with VNCoreMLModel.
/// Loading the model once eliminates the "precisionRecallCurves" warnings
/// that occur each time the model is loaded.
public actor NSFWClassifier {
    private let model: VNCoreMLModel

    public init() throws {
        guard let modelURL = openNSFWModelURL() else {
            throw NSFWAnalysisError.modelNotFound
        }

        let modelConfig = MLModelConfiguration()
        let openNSFWModel = try OpenNSFW(contentsOf: modelURL, configuration: modelConfig)
        self.model = try VNCoreMLModel(for: openNSFWModel.model)
        Log(.info, "OpenNSFW model loaded")
    }

    public func classify(cgImage: CGImage) throws -> NSFW {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        var classificationResult: Result<NSFW, any Error>?

        let vnRequest = VNCoreMLRequest(model: model) { request, error in
            if let error {
                Log(.error, "VNCoreMLRequest Error: \(error.localizedDescription)")
                classificationResult = .failure(NSFWAnalysisError.coreMLError(error))
                return
            }
            guard let observations = request.results as? [VNClassificationObservation] else {
                Log(.error, "Unexpected result type from VNCoreMLRequest")
                classificationResult = .failure(NSFWAnalysisError.invalidObservationType)
                return
            }
            guard let best = observations.first else {
                Log(.error, "Unable to retrieve NSFW observation")
                classificationResult = .failure(NSFWAnalysisError.noObservations)
                return
            }
            switch best.identifier {
            case "NSFW":
                classificationResult = .success(.nsfw)
            case "SFW":
                classificationResult = .success(.sfw)
            default:
                classificationResult = .failure(NSFWAnalysisError.unknown)
            }
        }

        try handler.perform([vnRequest])

        guard let result = classificationResult else {
            throw NSFWAnalysisError.unknown
        }

        return try result.get()
    }
}

#endif
