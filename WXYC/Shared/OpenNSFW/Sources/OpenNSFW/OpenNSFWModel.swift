//
// OpenNSFWModel.swift
//
// CoreML model wrapper for OpenNSFW classification.
// Based on auto-generated code from Xcode, but manually included
// to avoid bundling the model with the package.
//

import CoreML

/// Model Prediction Input Type
class OpenNSFWInput: MLFeatureProvider {
    /// data as color (kCVPixelFormatType_32BGRA) image buffer, 224 pixels wide by 224 pixels high
    var data: CVPixelBuffer

    var featureNames: Set<String> { ["data"] }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        if featureName == "data" {
            return MLFeatureValue(pixelBuffer: data)
        }
        return nil
    }

    init(data: CVPixelBuffer) {
        self.data = data
    }

    convenience init(dataWith data: CGImage) throws {
        self.init(data: try MLFeatureValue(cgImage: data, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32BGRA, options: nil).imageBufferValue!)
    }

    convenience init(dataAt data: URL) throws {
        self.init(data: try MLFeatureValue(imageAt: data, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32BGRA, options: nil).imageBufferValue!)
    }

    func setData(with data: CGImage) throws {
        self.data = try MLFeatureValue(cgImage: data, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32BGRA, options: nil).imageBufferValue!
    }

    func setData(with data: URL) throws {
        self.data = try MLFeatureValue(imageAt: data, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32BGRA, options: nil).imageBufferValue!
    }
}


/// Model Prediction Output Type
class OpenNSFWOutput: MLFeatureProvider {
    /// Source provided by CoreML
    private let provider: MLFeatureProvider

    /// prob as dictionary of strings to doubles
    var prob: [String: Double] {
        provider.featureValue(for: "prob")!.dictionaryValue as! [String: Double]
    }

    /// classLabel as string value
    var classLabel: String {
        provider.featureValue(for: "classLabel")!.stringValue
    }

    var featureNames: Set<String> {
        provider.featureNames
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        provider.featureValue(for: featureName)
    }

    init(prob: [String: Double], classLabel: String) {
        self.provider = try! MLDictionaryFeatureProvider(dictionary: [
            "prob": MLFeatureValue(dictionary: prob as [AnyHashable: NSNumber]),
            "classLabel": MLFeatureValue(string: classLabel)
        ])
    }

    init(features: MLFeatureProvider) {
        self.provider = features
    }
}


/// Class for model loading and prediction
class OpenNSFW {
    let model: MLModel

    /// Construct OpenNSFW instance with an existing MLModel object.
    init(model: MLModel) {
        self.model = model
    }

    /// Construct OpenNSFW instance with explicit path to mlmodelc file
    convenience init(contentsOf modelURL: URL) throws {
        try self.init(model: MLModel(contentsOf: modelURL))
    }

    /// Construct a model with URL of the .mlmodelc directory and configuration
    convenience init(contentsOf modelURL: URL, configuration: MLModelConfiguration) throws {
        try self.init(model: MLModel(contentsOf: modelURL, configuration: configuration))
    }

    /// Construct OpenNSFW instance asynchronously with URL of the .mlmodelc directory
    class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (Swift.Result<OpenNSFW, Error>) -> Void) {
        MLModel.load(contentsOf: modelURL, configuration: configuration) { result in
            switch result {
            case .failure(let error):
                handler(.failure(error))
            case .success(let model):
                handler(.success(OpenNSFW(model: model)))
            }
        }
    }

    /// Construct OpenNSFW instance asynchronously with URL of the .mlmodelc directory
    class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> OpenNSFW {
        let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
        return OpenNSFW(model: model)
    }

    /// Make a prediction using the structured interface
    func prediction(input: OpenNSFWInput) throws -> OpenNSFWOutput {
        try prediction(input: input, options: MLPredictionOptions())
    }

    /// Make a prediction using the structured interface with options
    func prediction(input: OpenNSFWInput, options: MLPredictionOptions) throws -> OpenNSFWOutput {
        let outFeatures = try model.prediction(from: input, options: options)
        return OpenNSFWOutput(features: outFeatures)
    }

    /// Make an asynchronous prediction using the structured interface
    func prediction(input: OpenNSFWInput, options: MLPredictionOptions = MLPredictionOptions()) async throws -> OpenNSFWOutput {
        let outFeatures = try await model.prediction(from: input, options: options)
        return OpenNSFWOutput(features: outFeatures)
    }

    /// Make a prediction using the convenience interface
    func prediction(data: CVPixelBuffer) throws -> OpenNSFWOutput {
        let input_ = OpenNSFWInput(data: data)
        return try prediction(input: input_)
    }

    /// Make a batch prediction using the structured interface
    func predictions(inputs: [OpenNSFWInput], options: MLPredictionOptions = MLPredictionOptions()) throws -> [OpenNSFWOutput] {
        let batchIn = MLArrayBatchProvider(array: inputs)
        let batchOut = try model.predictions(from: batchIn, options: options)
        var results: [OpenNSFWOutput] = []
        results.reserveCapacity(inputs.count)
        for i in 0..<batchOut.count {
            let outProvider = batchOut.features(at: i)
            let result = OpenNSFWOutput(features: outProvider)
            results.append(result)
        }
        return results
    }
}
