//
//  ImageProcessingService.swift
//  dust_remover
//
//  Service class for handling dust detection and removal operations
//

import Foundation
import AppKit
import CoreML

class ImageProcessingService {
    
    // MARK: - Dust Detection
    
    static func detectDust(in image: NSImage, using model: MLModel) async throws -> MLMultiArray {
        // Resize image to UNet requirements (1024x1024)
        let unetSize = CGSize(width: 1024, height: 1024)
        let resizedImage = image.resized(to: unetSize)
        
        guard let pixelBuffer = resizedImage.toCVPixelBuffer() else {
            throw ProcessingError.pixelBufferCreationFailed
        }
        
        let input = UNetDustInput(input: pixelBuffer)
        let unetModel = UNetDust(model: model)
        
        let prediction = try await unetModel.prediction(input: input)
        return prediction.output
    }
    
    // MARK: - Dust Removal
    
    static func removeDust(from image: NSImage, using dustMask: NSImage, with lamaModel: MLModel) async throws -> NSImage {
        // Dilate the mask for better inpainting coverage
        guard let dilatedMask = dilateMask(dustMask) else {
            throw ProcessingError.maskProcessingFailed
        }
        
        // Resize for LaMa (exactly 800x800)
        let lamaSize = CGSize(width: 800, height: 800)
        let resizedForLama = image.resized(to: lamaSize)
        let resizedMaskForLama = dilatedMask.resized(to: lamaSize)
        
        guard let rgbPixelBuffer = resizedForLama.toCVPixelBufferRGB(),
              let maskPixelBuffer = resizedMaskForLama.toCVPixelBuffer() else {
            throw ProcessingError.pixelBufferCreationFailed
        }
        
        let lamaInput = LaMaInput(image: rgbPixelBuffer, mask: maskPixelBuffer)
        let lama = LaMa(model: lamaModel)
        
        print("🚀 Running LaMa inpainting...")
        let lamaOutput = try await lama.prediction(input: lamaInput)
        
        guard let resultImage = NSImage(cvPixelBuffer: lamaOutput.output) else {
            throw ProcessingError.outputProcessingFailed
        }
        
        // Resize back to original image size
        return resultImage.resized(to: image.size)
    }
    
    // MARK: - Mask Processing
    
    static func createBinaryMask(from multiArray: MLMultiArray, threshold: Float) -> NSImage? {
        let shape = multiArray.shape
        guard shape.count == 4,
              let width = shape[3] as? Int,
              let height = shape[2] as? Int else {
            print("❌ Unexpected MultiArray shape: \(shape)")
            return nil
        }
        
        let dataPointer = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
        var maskData = Data(count: width * height)
        
        maskData.withUnsafeMutableBytes { ptr in
            let buffer = ptr.bindMemory(to: UInt8.self)
            for i in 0..<(width * height) {
                let value = dataPointer[i]
                buffer[i] = value > threshold ? 255 : 0
            }
        }
        
        guard let dataProvider = CGDataProvider(data: maskData as CFData),
              let cgImage = CGImage(width: width, height: height,
                                  bitsPerComponent: 8, bitsPerPixel: 8,
                                  bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                  provider: dataProvider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent) else {
            print("❌ Failed to create CGImage from mask data")
            return nil
        }
        
        return NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
    }
    
    static func dilateMask(_ mask: NSImage) -> NSImage? {
        guard let cgImage = mask.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        guard let colorSpace = cgImage.colorSpace,
              let context = CGContext(data: nil, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height)
        
        // Simple dilation: expand white pixels by 1 pixel in all directions
        var dilatedData = Data(count: width * height)
        dilatedData.withUnsafeMutableBytes { ptr in
            let dilatedBuffer = ptr.bindMemory(to: UInt8.self)
            
            for y in 0..<height {
                for x in 0..<width {
                    let index = y * width + x
                    var maxValue: UInt8 = 0
                    
                    // Check 3x3 neighborhood
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let nx = x + dx
                            let ny = y + dy
                            
                            if nx >= 0 && nx < width && ny >= 0 && ny < height {
                                let neighborIndex = ny * width + nx
                                maxValue = max(maxValue, buffer[neighborIndex])
                            }
                        }
                    }
                    
                    dilatedBuffer[index] = maxValue
                }
            }
        }
        
        guard let dataProvider = CGDataProvider(data: dilatedData as CFData),
              let dilatedCGImage = CGImage(width: width, height: height,
                                         bitsPerComponent: 8, bitsPerPixel: 8,
                                         bytesPerRow: width,
                                         space: colorSpace,
                                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                         provider: dataProvider, decode: nil,
                                         shouldInterpolate: false, intent: .defaultIntent) else {
            return nil
        }
        
        return NSImage(cgImage: dilatedCGImage, size: CGSize(width: width, height: height))
    }
}

// MARK: - Processing Errors

enum ProcessingError: LocalizedError {
    case modelLoadFailed(String)
    case pixelBufferCreationFailed
    case maskProcessingFailed
    case outputProcessingFailed
    
    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let message):
            return "Model loading failed: \(message)"
        case .pixelBufferCreationFailed:
            return "Failed to create pixel buffer"
        case .maskProcessingFailed:
            return "Failed to process dust mask"
        case .outputProcessingFailed:
            return "Failed to process output"
        }
    }
}