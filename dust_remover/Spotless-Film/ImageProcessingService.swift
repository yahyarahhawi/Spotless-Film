//
//  ImageProcessingService.swift
//  dust_remover
//
//  Service class for handling dust detection and removal operations
//

import Foundation
import AppKit
import CoreML
import Accelerate

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
        print("🔍 Starting dust removal process...")
        print("📏 Input image size: \(image.size)")
        print("📏 Input mask size: \(dustMask.size)")
        
        // Validate inputs
        guard image.size.width > 0 && image.size.height > 0 else {
            print("❌ Invalid image dimensions")
            throw ProcessingError.pixelBufferCreationFailed
        }
        
        guard dustMask.size.width > 0 && dustMask.size.height > 0 else {
            print("❌ Invalid mask dimensions")
            throw ProcessingError.pixelBufferCreationFailed
        }
        
        // Dilate the mask for better inpainting coverage
        let dilatedMask = dilateMask(dustMask) ?? dustMask // fallback to original mask if dilation fails
        
        // Resize for LaMa (exactly 800x800)
        let lamaSize = CGSize(width: 800, height: 800)
        let resizedForLama = image.resized(to: lamaSize)
        let resizedMaskForLama = dilatedMask.resized(to: lamaSize)
        
        print("🔍 Creating RGB pixel buffer for image...")
        guard let rgbPixelBuffer = resizedForLama.toCVPixelBufferRGB() else {
            print("❌ Failed to create RGB pixel buffer for image")
            throw ProcessingError.pixelBufferCreationFailed
        }
        print("✅ RGB pixel buffer created successfully")
        
        print("🔍 Creating grayscale pixel buffer for mask...")
        guard let maskPixelBuffer = resizedMaskForLama.toCVPixelBuffer() else {
            print("❌ Failed to create grayscale pixel buffer for mask")
            throw ProcessingError.pixelBufferCreationFailed
        }
        print("✅ Grayscale pixel buffer created successfully")
        
        print("🔍 Creating LaMa input...")
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
        guard let srcCG = mask.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let width = srcCG.width
        let height = srcCG.height

        // Create planar 8-bit buffer from CGImage using CoreGraphics (device gray)
        let bytesPerRow = width
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(srcCG, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let dataPtr = ctx.data else { return nil }

        var srcBuffer = vImage_Buffer(data: dataPtr, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
        var dstData = Data(count: height * width)
        dstData.withUnsafeMutableBytes { dstRaw in
            var dstBuffer = vImage_Buffer(data: dstRaw.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
            let kernel: [UInt8] = [1,1,1,1,1,1,1,1,1]
            kernel.withUnsafeBufferPointer { ptr in
                vImageDilate_Planar8(&srcBuffer, &dstBuffer, 0, 0, ptr.baseAddress!, 3, 3, vImage_Flags(kvImageEdgeExtend))
            }
        }

        guard let provider = CGDataProvider(data: dstData as CFData),
              let outCG = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }

        return NSImage(cgImage: outCG, size: mask.size)
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