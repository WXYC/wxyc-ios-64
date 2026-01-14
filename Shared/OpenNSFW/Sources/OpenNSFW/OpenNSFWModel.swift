//
//  OpenNSFWModel.swift
//  OpenNSFW
//
//  CoreML model wrapper for NSFW classification.
//
//  Created by Jake Bromberg on 12/07/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import CoreML

/// Model Prediction Input Type


/// Model Prediction Output Type


/// Class for model loading and prediction
class OpenNSFW {
    let model: MLModel

    /// Construct OpenNSFW instance with an existing MLModel object.
    init(model: MLModel) {
        self.model = model
    }

    /// Construct OpenNSFW instance with explicit path to mlmodelc file

    /// Construct a model with URL of the .mlmodelc directory and configuration
    convenience init(contentsOf modelURL: URL, configuration: MLModelConfiguration) throws {
        try self.init(model: MLModel(contentsOf: modelURL, configuration: configuration))
    }

    /// Construct OpenNSFW instance asynchronously with URL of the .mlmodelc directory

    /// Construct OpenNSFW instance asynchronously with URL of the .mlmodelc directory

    /// Make a prediction using the structured interface

    /// Make a prediction using the structured interface with options

    /// Make an asynchronous prediction using the structured interface

    /// Make a prediction using the convenience interface

    /// Make a batch prediction using the structured interface
}
