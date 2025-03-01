//
// OpenNSFW.swift
//
// This file was automatically generated and should not be edited.
//

import CoreML


/// Model Prediction Input Type
@available(iOS 18.0, tvOS 11.0, watchOS 8.0, visionOS 1.0, *)
class OpenNSFWInput : MLFeatureProvider {

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

    @available(iOS 18.0, tvOS 11.0, watchOS 4.0, visionOS 1.0, *)
    convenience init(dataWith data: CGImage) throws {
        self.init(data: try MLFeatureValue(cgImage: data, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32BGRA, options: nil).imageBufferValue!)
    }

    @available(iOS 18.0, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
    convenience init(dataAt data: URL) throws {
        self.init(data: try MLFeatureValue(imageAt: data, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32BGRA, options: nil).imageBufferValue!)
    }

    @available(iOS 18.0, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
    func setData(with data: CGImage) throws  {
        self.data = try MLFeatureValue(cgImage: data, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32BGRA, options: nil).imageBufferValue!
    }

    @available(iOS 18.0, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
    func setData(with data: URL) throws  {
        self.data = try MLFeatureValue(imageAt: data, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32BGRA, options: nil).imageBufferValue!
    }

}


/// Model Prediction Output Type
@available(iOS 18.0, tvOS 11.0, watchOS 4.0, visionOS 1.0, *)
class OpenNSFWOutput : MLFeatureProvider {

    /// Source provided by CoreML
    private let provider : MLFeatureProvider

    /// prob as dictionary of strings to doubles
    var prob: [String : Double] {
        provider.featureValue(for: "prob")!.dictionaryValue as! [String : Double]
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

    init(prob: [String : Double], classLabel: String) {
        self.provider = try! MLDictionaryFeatureProvider(dictionary: ["prob" : MLFeatureValue(dictionary: prob as [AnyHashable : NSNumber]), "classLabel" : MLFeatureValue(string: classLabel)])
    }

    init(features: MLFeatureProvider) {
        self.provider = features
    }
}


/// Class for model loading and prediction
@available(iOS 18.0, tvOS 11.0, watchOS 4.0, visionOS 1.0, *)
class OpenNSFW {
    let model: MLModel

    /// URL of model assuming it was installed in the same bundle as this class
    class var urlOfModelInThisBundle : URL {
        let bundle = Bundle(for: self)
        return bundle.url(forResource: "OpenNSFW", withExtension:"mlmodelc")!
    }

    /**
        Construct OpenNSFW instance with an existing MLModel object.

        Usually the application does not use this initializer unless it makes a subclass of OpenNSFW.
        Such application may want to use `MLModel(contentsOfURL:configuration:)` and `OpenNSFW.urlOfModelInThisBundle` to create a MLModel object to pass-in.

        - parameters:
          - model: MLModel object
    */
    init(model: MLModel) {
        self.model = model
    }

    /**
        Construct OpenNSFW instance by automatically loading the model from the app's bundle.
    */
    @available(*, deprecated, message: "Use init(configuration:) instead and handle errors appropriately.")
    convenience init() {
        try! self.init(contentsOf: type(of:self).urlOfModelInThisBundle)
    }

    /**
        Construct a model with configuration

        - parameters:
           - configuration: the desired model configuration

        - throws: an NSError object that describes the problem
    */
    @available(iOS 18.0, tvOS 12.0, watchOS 5.0, visionOS 1.0, *)
    convenience init(configuration: MLModelConfiguration) throws {
        try self.init(contentsOf: type(of:self).urlOfModelInThisBundle, configuration: configuration)
    }

    /**
        Construct OpenNSFW instance with explicit path to mlmodelc file
        - parameters:
           - modelURL: the file url of the model

        - throws: an NSError object that describes the problem
    */
    convenience init(contentsOf modelURL: URL) throws {
        try self.init(model: MLModel(contentsOf: modelURL))
    }

    /**
        Construct a model with URL of the .mlmodelc directory and configuration

        - parameters:
           - modelURL: the file url of the model
           - configuration: the desired model configuration

        - throws: an NSError object that describes the problem
    */
    @available(iOS 18.0, tvOS 12.0, watchOS 5.0, visionOS 1.0, *)
    convenience init(contentsOf modelURL: URL, configuration: MLModelConfiguration) throws {
        try self.init(model: MLModel(contentsOf: modelURL, configuration: configuration))
    }

    /**
        Construct OpenNSFW instance asynchronously with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - configuration: the desired model configuration
          - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
    */
    @available(iOS 18.0, tvOS 14.0, watchOS 7.0, visionOS 1.0, *)
    class func load(configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (Swift.Result<OpenNSFW, Error>) -> Void) {
        load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration, completionHandler: handler)
    }

    /**
        Construct OpenNSFW instance asynchronously with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - configuration: the desired model configuration
    */
    @available(iOS 18.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    class func load(configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> OpenNSFW {
        try await load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration)
    }

    /**
        Construct OpenNSFW instance asynchronously with URL of the .mlmodelc directory with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - modelURL: the URL to the model
          - configuration: the desired model configuration
          - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
    */
    @available(iOS 18.0, tvOS 14.0, watchOS 7.0, visionOS 1.0, *)
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

    /**
        Construct OpenNSFW instance asynchronously with URL of the .mlmodelc directory with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - modelURL: the URL to the model
          - configuration: the desired model configuration
    */
    @available(iOS 18.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> OpenNSFW {
        let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
        return OpenNSFW(model: model)
    }

    /**
        Make a prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as OpenNSFWInput

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as OpenNSFWOutput
    */
    func prediction(input: OpenNSFWInput) throws -> OpenNSFWOutput {
        try prediction(input: input, options: MLPredictionOptions())
    }

    /**
        Make a prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as OpenNSFWInput
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as OpenNSFWOutput
    */
    func prediction(input: OpenNSFWInput, options: MLPredictionOptions) throws -> OpenNSFWOutput {
        let outFeatures = try model.prediction(from: input, options: options)
        return OpenNSFWOutput(features: outFeatures)
    }

    /**
        Make an asynchronous prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as OpenNSFWInput
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as OpenNSFWOutput
    */
    @available(iOS 18.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
    func prediction(input: OpenNSFWInput, options: MLPredictionOptions = MLPredictionOptions()) async throws -> OpenNSFWOutput {
        let outFeatures = try await model.prediction(from: input, options: options)
        return OpenNSFWOutput(features: outFeatures)
    }

    /**
        Make a prediction using the convenience interface

        It uses the default function if the model has multiple functions.

        - parameters:
            - data: color (kCVPixelFormatType_32BGRA) image buffer, 224 pixels wide by 224 pixels high

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as OpenNSFWOutput
    */
    func prediction(data: CVPixelBuffer) throws -> OpenNSFWOutput {
        let input_ = OpenNSFWInput(data: data)
        return try prediction(input: input_)
    }

    /**
        Make a batch prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - inputs: the inputs to the prediction as [OpenNSFWInput]
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as [OpenNSFWOutput]
    */
    @available(iOS 18.0, tvOS 12.0, watchOS 5.0, visionOS 1.0, *)
    func predictions(inputs: [OpenNSFWInput], options: MLPredictionOptions = MLPredictionOptions()) throws -> [OpenNSFWOutput] {
        let batchIn = MLArrayBatchProvider(array: inputs)
        let batchOut = try model.predictions(from: batchIn, options: options)
        var results : [OpenNSFWOutput] = []
        results.reserveCapacity(inputs.count)
        for i in 0..<batchOut.count {
            let outProvider = batchOut.features(at: i)
            let result =  OpenNSFWOutput(features: outProvider)
            results.append(result)
        }
        return results
    }
}
