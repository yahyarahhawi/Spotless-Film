//
//  ModelManager.swift
//  dust_remover
//
//  Service for loading and managing CoreML models
//

import Foundation
import CoreML

class ModelManager {
    
    static func loadUNetModel() throws -> MLModel {
        var dustModelURL: URL?
        
        // Try different file extensions
        dustModelURL = Bundle.main.url(forResource: "UNetDust", withExtension: "mlmodelc")
        if dustModelURL == nil {
            dustModelURL = Bundle.main.url(forResource: "UNetDust", withExtension: "mlpackage")
        }
        if dustModelURL == nil {
            dustModelURL = Bundle.main.url(forResource: "UNetDust", withExtension: nil)
        }
        
        guard let dustURL = dustModelURL else {
            throw ProcessingError.modelLoadFailed("UNet dust detection model not found in bundle")
        }
        
        print("Loading UNet model from: \(dustURL.path)")
        let model = try MLModel(contentsOf: dustURL)
        print("✅ UNet dust detection model loaded successfully")
        
        return model
    }
    
    static func loadLamaModel() throws -> MLModel {
        var lamaModelURL: URL?
        
        // Try different file extensions
        lamaModelURL = Bundle.main.url(forResource: "LaMa", withExtension: "mlmodelc")
        if lamaModelURL == nil {
            lamaModelURL = Bundle.main.url(forResource: "LaMa", withExtension: "mlpackage")
        }
        if lamaModelURL == nil {
            lamaModelURL = Bundle.main.url(forResource: "LaMa", withExtension: nil)
        }
        
        guard let lamaURL = lamaModelURL else {
            throw ProcessingError.modelLoadFailed("LaMa inpainting model not found in bundle")
        }
        
        print("Loading LaMa model from: \(lamaURL.path)")
        let model = try MLModel(contentsOf: lamaURL)
        print("✅ LaMa inpainting model loaded successfully")
        
        return model
    }
    
    static func loadModels() async -> (unet: MLModel?, lama: MLModel?, error: String?) {
        do {
            let unetModel = try loadUNetModel()
            let lamaModel = try loadLamaModel()
            
            // Debug model info
            print("UNet input: \(unetModel.modelDescription.inputDescriptionsByName)")
            print("UNet output: \(unetModel.modelDescription.outputDescriptionsByName)")
            print("LaMa input: \(lamaModel.modelDescription.inputDescriptionsByName)")
            print("LaMa output: \(lamaModel.modelDescription.outputDescriptionsByName)")
            
            return (unetModel, lamaModel, nil)
        } catch {
            let errorMessage = "Failed to load AI models: \(error.localizedDescription)"
            print("❌ \(errorMessage)")
            return (nil, nil, errorMessage)
        }
    }
}