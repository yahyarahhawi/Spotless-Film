//
//  ContentView.swift
//  dust_remover
//
//  Created by Yahya Rahhawi on 8/1/25.
//

import SwiftUI
import CoreML
import Vision
import AppKit
import PhotosUI
import VideoToolbox

struct ContentView: View {
    // MARK: - State Variables
    @State private var selectedImage: NSImage?
    @State private var processedImage: NSImage?
    @State private var rawPrediction: MLMultiArray?
    @State private var isLoading = false
    @State private var showingImagePicker = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var threshold: Float = 0.05
    @State private var processingTime: Double = 0
    @State private var model: MLModel?
    @State private var lamaModel: MLModel?
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.2, green: 0.15, blue: 0.3),
                    Color(red: 0.15, green: 0.1, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            HStack(spacing: 24) {
                // Left Panel - Controls
                VStack(spacing: 24) {
                    headerCard
                    importCard
                    if selectedImage != nil {
                        processCard
                    }
                    if rawPrediction != nil {
                        sensitivityCard
                    }
                    if processedImage != nil {
                        exportCard
                    }
                            Spacer()
                }
                .frame(width: 350)
                
                // Right Panel - Image Display
                imageDisplayCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(24)
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { _, _ in
            resetProcessing()
        }
        .onAppear {
            loadModel()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "Unknown error occurred")
        }
    }
    
    // MARK: - UI Components
    
    private var headerCard: some View {
        GlassCard {
            VStack(spacing: 16) {
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                VStack(spacing: 4) {
                    Text("Film Dust Removal")
                        .font(.title2)
                        .fontWeight(.semibold)
                                .foregroundColor(.white)
                    
                    Text("AI-powered dust removal with LaMa inpainting")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var importCard: some View {
        GlassCard {
            VStack(spacing: 16) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(.cyan)
                        
                        Button(action: {
                            showingImagePicker = true
                        }) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("Import Image")
                    }
                    .font(.headline)
                                .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.cyan.opacity(0.8), .blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                                .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                        }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(isLoading ? 0.95 : 1.0)
                .animation(.spring(response: 0.3), value: isLoading)
                    }
        }
    }
                    
    private var processCard: some View {
        GlassCard {
                        VStack(spacing: 16) {
                if let selectedImage = selectedImage {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Image Loaded")
                                    .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        
                        HStack {
                            Text("Size:")
                                .foregroundColor(.white.opacity(0.7))
                            Text("\(Int(selectedImage.size.width)) × \(Int(selectedImage.size.height))")
                                .font(.monospaced(.caption)())
                                .foregroundColor(.cyan)
                            Spacer()
                        }
                        
                            Button(action: processImage) {
                                HStack {
                                    if isLoading {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                    Image(systemName: "wand.and.stars")
                                    }
                                Text(isLoading ? "Processing..." : "Process Image")
                                }
                            .font(.headline)
                                .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: isLoading ? 
                                        [.gray.opacity(0.6), .gray.opacity(0.8)] :
                                        [.orange.opacity(0.8), .red.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                                .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                            }
                        .buttonStyle(PlainButtonStyle())
                            .disabled(isLoading)
                    }
                }
            }
        }
    }
    
    private var sensitivityCard: some View {
        GlassCard {
            VStack(spacing: 16) {
                                    HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.purple)
                    Text("Removal Sensitivity")
                                            .font(.headline)
                        .foregroundColor(.white)
                                        Spacer()
                }
                                        
                VStack(spacing: 12) {
                    HStack {
                        Text("Very High")
                                                .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text(String(format: "%.3f", threshold))
                            .font(.monospaced(.callout)())
                            .foregroundColor(.purple)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("Very Low")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    ZStack {
                        Capsule()
                            .fill(.white.opacity(0.1))
                            .frame(height: 8)
                        
                        GeometryReader { geometry in
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple, .pink, .orange],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: CGFloat(threshold / 0.1) * geometry.size.width,
                                    height: 8
                                )
                        }
                        .frame(height: 8)
                        
                        Slider(value: $threshold, in: 0.0...0.1, step: 0.001)
                            .accentColor(.clear)
                            .onChange(of: threshold) { _ in
                                updateThresholdedImage()
                            }
                    }
                }
            }
        }
    }
    
    private var exportCard: some View {
        GlassCard {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundColor(.green)
                    Text("Export")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                }
                
                if processingTime > 0 {
                    HStack {
                        Text("Processed in")
                            .foregroundColor(.white.opacity(0.7))
                        Text("\(String(format: "%.2f", processingTime))s")
                            .font(.monospaced(.caption)())
                            .foregroundColor(.green)
                        Spacer()
                    }
                }
                
                                    Button(action: saveProcessedImage) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save Image")
                    }
                    .font(.headline)
                                            .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.green.opacity(0.8), .mint.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                                            .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private var imageDisplayCard: some View {
        GlassCard {
            VStack(spacing: 16) {
                // Header
                HStack {
                    if let _ = processedImage {
                        Image(systemName: "sparkles.tv.fill")
                            .foregroundColor(.orange)
                        Text("Dust-Free Result")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    } else if let _ = selectedImage {
                        Image(systemName: "photo")
                            .foregroundColor(.blue)
                        Text("Original Image")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "photo.artframe")
                            .foregroundColor(.white.opacity(0.5))
                        Text("No Image Selected")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                }
                
                // Image Display Area
                ZStack {
                    // Background pattern when no image
                    if selectedImage == nil && processedImage == nil {
                        VStack(spacing: 20) {
                            Image(systemName: "photo.artframe")
                                .font(.system(size: 80, weight: .ultraLight))
                                .foregroundColor(.white.opacity(0.3))
                            
                            VStack(spacing: 8) {
                                Text("Import an image to get started")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white.opacity(0.8))
                                
                                Text("Supported formats: PNG, JPEG, TIFF")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Display current image
                        let imageToShow = processedImage ?? selectedImage
                        
                        if let image = imageToShow {
                            GeometryReader { geometry in
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                                    .background(.white.opacity(0.05))
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(.white.opacity(0.1), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(8)
        }
    }
    
    // MARK: - Helper Functions
    
    private func resetProcessing() {
        processedImage = nil
        rawPrediction = nil
    }
    
    // MARK: - Core ML Functions
    
    private func loadModel() {
        do {
            // Load UNet dust detection model
            var dustModelURL: URL?
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
            model = try MLModel(contentsOf: dustURL)
            print("✅ UNet dust detection model loaded successfully")
            
            // Load LaMa inpainting model
            var lamaModelURL: URL?
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
            lamaModel = try MLModel(contentsOf: lamaURL)
            print("✅ LaMa inpainting model loaded successfully")
            
            // Debug model info
            if let model = model {
                print("UNet input: \(model.modelDescription.inputDescriptionsByName)")
                print("UNet output: \(model.modelDescription.outputDescriptionsByName)")
            }
            
            if let lamaModel = lamaModel {
                print("LaMa input: \(lamaModel.modelDescription.inputDescriptionsByName)")
                print("LaMa output: \(lamaModel.modelDescription.outputDescriptionsByName)")
            }
            
        } catch {
            errorMessage = "Failed to load AI models: \(error.localizedDescription)"
            showingError = true
            print("❌ Failed to load models: \(error)")
        }
    }
    
    private func processImage() {
        guard let selectedImage = selectedImage, let model = model, let lamaModel = lamaModel else {
            errorMessage = "Models not loaded or no image selected"
            showingError = true
            return
        }
        
        isLoading = true
        let startTime = CFAbsoluteTimeGetCurrent()
        
        Task {
            do {
                let (inpaintedResult, rawPred) = try await processImageWithModel(image: selectedImage, model: model, lamaModel: lamaModel)
                
                await MainActor.run {
                    rawPrediction = rawPred
                    processedImage = inpaintedResult
                    processingTime = CFAbsoluteTimeGetCurrent() - startTime
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Processing failed: \(error.localizedDescription)"
                    showingError = true
                    isLoading = false
                }
            }
        }
    }
    
    private func processImageWithModel(image: NSImage, model: MLModel, lamaModel: MLModel) async throws -> (NSImage, MLMultiArray) {
        let originalSize = image.size
        print("Processing image of size: \(originalSize)")
        
        // Step 1: Dust Detection with UNet
        print("🔍 Step 1: Dust detection with UNet...")
        
        // Convert to grayscale for dust detection
        let grayscaleImage = image.toGrayscale()
        
        // Resize to 1024x1024 for processing
        print("🔄 Resizing image to 1024x1024 for dust detection")
        let resizedImage = grayscaleImage.resized(to: CGSize(width: 1024, height: 1024))
        
        // Convert to pixel buffer
        guard let pixelBuffer = resizedImage.toCVPixelBuffer() else {
            throw ProcessingError.pixelBufferCreationFailed
        }
        
        print("✅ Created pixel buffer: 1024x1024")
        
        // Run through UNet model
        let inputName = model.modelDescription.inputDescriptionsByName.keys.first ?? "input"
        let inputFeature = MLFeatureValue(pixelBuffer: pixelBuffer)
        let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: inputFeature])
        
        print("🤖 Running UNet dust detection...")
        let output = try await model.prediction(from: provider)
        
        // Get output (MultiArray)
        guard let outputMultiArray = output.featureValue(for: "output")?.multiArrayValue else {
            throw ProcessingError.outputProcessingFailed
        }
        
        print("✅ UNet dust detection complete")
        
        // Debug output
        debugRawMultiArrayOutput(outputMultiArray)
        
        // Step 2: Create dilated mask
        print("🎯 Step 2: Creating dilated mask for inpainting...")
        
        // Apply threshold and dilation to create mask
        guard let maskImage = applyThresholdToMultiArray(outputMultiArray, threshold: threshold) else {
            throw ProcessingError.outputProcessingFailed
        }
        
        // Resize mask back to original dimensions
        let finalMaskImage = maskImage.resized(to: originalSize)
        
        // Step 3: LaMa Inpainting
        print("🎨 Step 3: LaMa inpainting to remove dust...")
        
        // Use LaMa to inpaint the original image with the dilated mask
        guard let inpaintedImage = try await performLaMaInpainting(originalImage: image, maskImage: finalMaskImage) else {
            // If LaMa fails, return the mask for debugging
            print("⚠️ LaMa inpainting failed, returning mask for debugging")
            return (finalMaskImage, outputMultiArray)
        }
        
        print("✅ Complete dust removal pipeline finished!")
        return (inpaintedImage, outputMultiArray)
    }
    
    private func updateThresholdedImage() {
        guard let rawPrediction = rawPrediction, let selectedImage = selectedImage, let lamaModel = lamaModel else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Create new mask with updated threshold
            guard let maskImage = self.applyThresholdToMultiArray(rawPrediction, threshold: self.threshold) else {
                return
            }
            
            let finalMaskImage = maskImage.resized(to: selectedImage.size)
            
            // Use LaMa to inpaint with the new mask
            Task {
                do {
                    if let inpaintedImage = try await self.performLaMaInpainting(originalImage: selectedImage, maskImage: finalMaskImage) {
                        await MainActor.run {
                            self.processedImage = inpaintedImage
                        }
                    }
                } catch {
                    print("❌ Real-time LaMa inpainting failed: \(error)")
                    // Fallback to showing the mask
                    await MainActor.run {
                        self.processedImage = finalMaskImage
                    }
                }
            }
        }
    }
    
    private func applyThresholdToMultiArray(_ multiArray: MLMultiArray, threshold: Float) -> NSImage? {
        let shape = multiArray.shape
        
        var width: Int
        var height: Int
        
        if shape.count == 4 {
            height = shape[2].intValue
            width = shape[3].intValue
        } else if shape.count == 3 {
            height = shape[1].intValue
            width = shape[2].intValue
        } else if shape.count == 2 {
            height = shape[0].intValue
            width = shape[1].intValue
        } else {
            print("❌ Unexpected MultiArray shape for thresholding: \(shape)")
            return nil
        }
        
        let dataPointer = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
        let count = multiArray.count
        
        var imageData = Data(count: width * height)
        var pixelsAboveThreshold = 0
        
        imageData.withUnsafeMutableBytes { ptr in
            let buffer = ptr.bindMemory(to: UInt8.self)
            
            for i in 0..<count {
                let floatValue = dataPointer[i]
                
                if floatValue > threshold {
                    buffer[i] = 255
                    pixelsAboveThreshold += 1
                } else {
                    buffer[i] = 0
                }
            }
        }
        
        let dustPercentage = Double(pixelsAboveThreshold) / Double(count) * 100.0
        print("🎯 Applied threshold \(threshold): \(String(format: "%.2f", dustPercentage))% pixels detected as dust")
        
        // Apply morphological dilation with 5x5 disc kernel
        let dilatedImageData = dilateImageData(imageData, width: width, height: height, kernelSize: 5)
        
        // Count dilated pixels for comparison
        var dilatedPixelsCount = 0
        dilatedImageData.withUnsafeBytes { ptr in
            let buffer = ptr.bindMemory(to: UInt8.self)
            for i in 0..<(width * height) {
                if buffer[i] > 0 {
                    dilatedPixelsCount += 1
                }
            }
        }
        
        let dilatedPercentage = Double(dilatedPixelsCount) / Double(width * height) * 100.0
        print("🔍 After dilation: \(String(format: "%.2f", dilatedPercentage))% pixels (expanded from \(String(format: "%.2f", dustPercentage))%)")
        
        guard let dataProvider = CGDataProvider(data: dilatedImageData as CFData),
              let cgImage = CGImage(width: width, height: height, 
                                  bitsPerComponent: 8, bitsPerPixel: 8,
                                  bytesPerRow: width, 
                                  space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                  provider: dataProvider, decode: nil, 
                                  shouldInterpolate: false, intent: .defaultIntent) else {
            print("❌ Failed to create dilated CGImage")
            return nil
        }
        
        return NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
    }
    
    private func debugRawMultiArrayOutput(_ multiArray: MLMultiArray) {
        let shape = multiArray.shape
        let count = multiArray.count
        
        print("🔍 RAW MULTIARRAY OUTPUT ANALYSIS:")
        print("  Shape: \(shape)")
        print("  Count: \(count)")
        
        let dataPointer = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
        
        var min: Float = Float.greatestFiniteMagnitude
        var max: Float = -Float.greatestFiniteMagnitude
        var sum: Double = 0.0
        var nonZeroCount = 0
        
        for i in 0..<count {
            let value = dataPointer[i]
            min = Swift.min(min, value)
            max = Swift.max(max, value)
            sum += Double(value)
            if value > 0 {
                nonZeroCount += 1
            }
        }
        
        let avg = sum / Double(count)
        let dustPercentage = Double(nonZeroCount) / Double(count) * 100.0
        
        print("  Float32 values - Min: \(String(format: "%.6f", min)), Max: \(String(format: "%.6f", max)), Avg: \(String(format: "%.6f", avg))")
        print("  Non-zero pixels: \(nonZeroCount)/\(count) (\(String(format: "%.2f", dustPercentage))%)")
        print("  ✅ MultiArray preserves continuous probability values!")
    }
    
    private func dilateImageData(_ imageData: Data, width: Int, height: Int, kernelSize: Int) -> Data {
        var dilatedData = Data(count: width * height)
        
        // Create 5x5 disc structuring element (same as Python's cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5,5)))
        let radius = kernelSize / 2  // radius = 2 for 5x5 kernel
        var kernel: [[Bool]] = Array(repeating: Array(repeating: false, count: kernelSize), count: kernelSize)
        
        // Create disc shape
        for y in 0..<kernelSize {
            for x in 0..<kernelSize {
                let dx = x - radius
                let dy = y - radius
                let distance = sqrt(Double(dx * dx + dy * dy))
                kernel[y][x] = distance <= Double(radius)
            }
        }
        
        print("🔍 Dilation kernel (5x5 disc):")
        for row in kernel {
            let rowString = row.map { $0 ? "●" : "○" }.joined(separator: " ")
            print("   \(rowString)")
        }
        
        imageData.withUnsafeBytes { srcPtr in
            let srcBuffer = srcPtr.bindMemory(to: UInt8.self)
            
            dilatedData.withUnsafeMutableBytes { dstPtr in
                let dstBuffer = dstPtr.bindMemory(to: UInt8.self)
                
                // Apply dilation: for each pixel, check if any pixel in the kernel neighborhood is white
        for y in 0..<height {
            for x in 0..<width {
                        let dstIndex = y * width + x
                        var maxValue: UInt8 = 0
                        
                        // Check all positions in the kernel
                        for ky in 0..<kernelSize {
                            for kx in 0..<kernelSize {
                                if kernel[ky][kx] {  // Only check positions that are part of the disc
                                    let srcY = y + ky - radius
                                    let srcX = x + kx - radius
                                    
                                    // Check bounds
                                    if srcY >= 0 && srcY < height && srcX >= 0 && srcX < width {
                                        let srcIndex = srcY * width + srcX
                                        maxValue = max(maxValue, srcBuffer[srcIndex])
                                    }
                                }
                            }
                        }
                        
                        dstBuffer[dstIndex] = maxValue
                    }
                }
            }
        }
        
        return dilatedData
    }
    
    private func performLaMaInpainting(originalImage: NSImage, maskImage: NSImage) async throws -> NSImage? {
        guard let lamaModel = lamaModel else {
            print("❌ LaMa model not loaded")
            return nil
        }
        
        print("🎨 Starting LaMa inpainting...")
        let originalSize = originalImage.size
        
        // LaMa expects 800x800 input size
        let lamaSize = CGSize(width: 800, height: 800)
        
        print("🔄 Resizing for LaMa: \(originalSize) → \(lamaSize)")
        
        // Resize both images to LaMa-compatible size
        let resizedOriginal = originalImage.resized(to: lamaSize)
        let resizedMask = maskImage.resized(to: lamaSize)
        
        // Convert images to CGImage
        guard let originalCGImage = resizedOriginal.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let maskCGImage = resizedMask.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("❌ Failed to convert images to CGImage for LaMa")
            return nil
        }
        
        print("🖼️ LaMa input - Original: \(originalCGImage.width)x\(originalCGImage.height), Mask: \(maskCGImage.width)x\(maskCGImage.height)")
        
        do {
            // Debug LaMa model requirements
            print("🔍 LaMa model input descriptions:")
            for (key, desc) in lamaModel.modelDescription.inputDescriptionsByName {
                print("  \(key): \(desc)")
            }
            
            // Create input for LaMa model
            // According to the article, LaMa expects imageWith and maskWith parameters
            let inputName = lamaModel.modelDescription.inputDescriptionsByName.keys.first ?? "image"
            let maskInputName = lamaModel.modelDescription.inputDescriptionsByName.keys.count > 1 ? 
                Array(lamaModel.modelDescription.inputDescriptionsByName.keys)[1] : "mask"
            
            print("🔍 LaMa input names: image='\(inputName)', mask='\(maskInputName)'")
            
            // Convert to pixel buffers (image=RGB, mask=grayscale for LaMa)
            guard let imagePixelBuffer = resizedOriginal.toCVPixelBufferRGB(),
                  let maskPixelBuffer = resizedMask.toCVPixelBuffer() else {
                print("❌ Failed to create pixel buffers for LaMa")
                return nil
            }
            
            // Create feature values
            let imageFeature = MLFeatureValue(pixelBuffer: imagePixelBuffer)
            let maskFeature = MLFeatureValue(pixelBuffer: maskPixelBuffer)
            
            // Create input dictionary
            let inputDict = [
                inputName: imageFeature,
                maskInputName: maskFeature
            ]
            
            let provider = try MLDictionaryFeatureProvider(dictionary: inputDict)
            
            print("🤖 Running LaMa inpainting...")
            let output = try await lamaModel.prediction(from: provider)
            
            // Get output
            let outputName = lamaModel.modelDescription.outputDescriptionsByName.keys.first ?? "output"
            
            if let outputPixelBuffer = output.featureValue(for: outputName)?.imageBufferValue {
                print("✅ LaMa inpainting complete - got PixelBuffer output")
                
                // Convert back to NSImage
                var cgImage: CGImage?
                VTCreateCGImageFromCVPixelBuffer(outputPixelBuffer, options: nil, imageOut: &cgImage)
                
                guard let resultCGImage = cgImage else {
                    print("❌ Failed to convert LaMa output to CGImage")
                    return nil
                }
                
                // Create image at LaMa output size first
                let lamaResultImage = NSImage(cgImage: resultCGImage, size: lamaSize)
                
                // Resize back to original dimensions
                let finalResultImage = lamaResultImage.resized(to: originalSize)
                
                print("🎨 LaMa inpainting successful! Resized back to: \(originalSize)")
                return finalResultImage
                
                } else {
                print("❌ LaMa output format not recognized")
                return nil
                }
            
        } catch {
            print("❌ LaMa inpainting failed: \(error)")
            throw error
        }
    }
    
    private func saveProcessedImage() {
        guard let processedImage = processedImage else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "dust_removed_\(Int(Date().timeIntervalSince1970)).png"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
                do {
                    print("Saving to: \(url.path)")
                    
                    if let tiffData = processedImage.tiffRepresentation,
                       let bitmapRep = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                        
                        try pngData.write(to: url)
                        
                        if FileManager.default.fileExists(atPath: url.path) {
                            let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
                            print("✅ Image saved successfully: \(url.lastPathComponent) (Size: \(fileSize) bytes)")
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                } catch {
                    print("❌ Failed to save image: \(error)")
                errorMessage = "Failed to save image: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}

// MARK: - Glassmorphic Card Component

struct GlassCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(20)
            .background(
                ZStack {
                    // Glass background
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.white.opacity(0.1))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    
                    // Border
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Supporting Types

enum ProcessingError: LocalizedError {
    case pixelBufferCreationFailed
    case outputProcessingFailed
    case maskConversionFailed
    case modelLoadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .pixelBufferCreationFailed:
            return "Failed to create pixel buffer"
        case .outputProcessingFailed:
            return "Failed to process model output"
        case .maskConversionFailed:
            return "Failed to convert mask"
        case .modelLoadFailed(let message):
            return "Model loading failed: \(message)"
        }
    }
}

// MARK: - Extensions

extension NSImage {
    func resized(to size: CGSize) -> NSImage {
        let resizedImage = NSImage(size: size)
        resizedImage.lockFocus()
        
        let sourceRect = NSRect(origin: .zero, size: self.size)
        let targetRect = NSRect(origin: .zero, size: size)
        
        self.draw(in: targetRect, from: sourceRect, operation: .copy, fraction: 1.0)
        
        resizedImage.unlockFocus()
        return resizedImage
    }
    
    func toGrayscale() -> NSImage {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), 
                               bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, 
                               bitmapInfo: CGImageAlphaInfo.none.rawValue)
        
        context?.draw(cgImage, in: CGRect(origin: .zero, size: size))
        
        guard let outputCGImage = context?.makeImage() else { return self }
        return NSImage(cgImage: outputCGImage, size: size)
    }
    
    func toCVPixelBuffer() -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue as Any,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue as Any,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                       Int(size.width),
                                       Int(size.height),
                                       kCVPixelFormatType_OneComponent8,
                                       attrs,
                                       &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        defer { CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0)) }
        
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                    width: Int(size.width),
                                    height: Int(size.height),
                                    bitsPerComponent: 8,
                                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                    space: CGColorSpaceCreateDeviceGray(),
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return buffer
    }
    
    func toCVPixelBufferRGB() -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue as Any,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue as Any,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                       Int(size.width),
                                       Int(size.height),
                                       kCVPixelFormatType_32BGRA, // Assuming RGBA for LaMa input
                                       attrs,
                                       &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        defer { CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0)) }
        
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                    width: Int(size.width),
                                    height: Int(size.height),
                                     bitsPerComponent: 8,
                                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                    space: CGColorSpaceCreateDeviceRGB(), // RGBA
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}

// MARK: - Image Picker (macOS)

struct ImagePicker: NSViewControllerRepresentable {
    @Binding var selectedImage: NSImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeNSViewController(context: Context) -> NSViewController {
        let controller = NSViewController()
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            
            if panel.runModal() == .OK, let url = panel.url {
                self.selectedImage = NSImage(contentsOf: url)
            }
            self.dismiss()
        }
        return controller
    }
    
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}

#Preview {
    ContentView()
}
