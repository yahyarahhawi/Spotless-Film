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
    @State private var showingOriginal = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var zoomAnchor: UnitPoint = .center
    @State private var dragOffset: CGSize = .zero
    
    // Dust detection state
    @State private var dustMask: NSImage?
    @State private var rawPredictionMask: MLMultiArray?
    @State private var isDetecting = false
    @State private var isRemoving = false
    @State private var hideDetections = false
    
    var body: some View {
        NavigationSplitView {
            // Sidebar - Controls
            VStack(spacing: 0) {
                headerSection
                
                Form {
                    Section {
                        importSection
                    }
                    
                    if selectedImage != nil {
                        Section("Processing") {
                            processSection
                        }
                    }
                    
                    if rawPredictionMask != nil {
                        Section("Detection Threshold") {
                            sensitivitySection
                        }
                    }
                    
                    if processedImage != nil {
                        Section("Export") {
                            exportSection
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                
                Spacer()
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 320, max: 400)
        } detail: {
            // Main content area - Image Display
            imageDisplayArea
                .navigationTitle("")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        if processedImage != nil {
                            Button("Save", action: saveProcessedImage)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .background(.windowBackground)
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
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            
            VStack(spacing: 4) {
                Text("Film Dust Removal")
                    .font(.title3)
                    .fontWeight(.medium)
                
                Text("AI-powered restoration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }
    
    private var importSection: some View {
        VStack(spacing: 12) {
            Label("Import Image", systemImage: "photo.badge.plus")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Button(action: {
                showingImagePicker = true
            }) {
                HStack {
                    Image(systemName: "folder.badge.plus")
                    Text("Choose File")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isLoading)
        }
        .padding(.vertical, 8)
    }
                    
    private var processSection: some View {
        VStack(spacing: 12) {
            if let selectedImage = selectedImage {
                HStack {
                    Label("Image Loaded", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                }
                
                HStack {
                    Text("Size:")
                        .foregroundStyle(.secondary)
                    Text("\(Int(selectedImage.size.width)) × \(Int(selectedImage.size.height))")
                        .font(.monospaced(.caption)())
                        .foregroundStyle(.primary)
                    Spacer()
                }
                
                // Detect Dust Button
                Button(action: detectDust) {
                    HStack {
                        if isDetecting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text(isDetecting ? "Detecting..." : "Detect Dust")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isDetecting || isRemoving)
                
                // Remove Dust Button
                Button(action: removeDust) {
                    HStack {
                        if isRemoving {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                        Text(isRemoving ? "Removing..." : "Remove Dust")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(dustMask == nil || isDetecting || isRemoving)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var sensitivitySection: some View {
        VStack(spacing: 12) {
            Label("Detection Threshold", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.primary)
            
            VStack(spacing: 8) {
                HStack {
                    Text("More Sensitive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.3f", threshold))
                        .font(.monospaced(.callout)())
                        .foregroundStyle(.primary)
                        .fontWeight(.medium)
                    Spacer()
                    Text("Less Sensitive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Slider(value: $threshold, in: 0.001...0.1, step: 0.001)
                    .onChange(of: threshold) {
                        updateDustMaskWithThreshold()
                    }
                
                if rawPredictionMask != nil {
                    Text("Adjust the slider to fine-tune dust detection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private var exportSection: some View {
        VStack(spacing: 12) {
            if processingTime > 0 {
                HStack {
                    Label("Processed in", systemImage: "clock")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(String(format: "%.2f", processingTime))s")
                        .font(.monospaced(.caption)())
                        .foregroundStyle(.green)
                }
            }
            
            Button(action: saveProcessedImage) {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save Image")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.vertical, 8)
    }
    
    private var imageDisplayArea: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if hideDetections && dustMask != nil {
                    Label("Original Image (Hold to Hide Detections)", systemImage: "photo")
                        .foregroundStyle(.blue)
                        .font(.title3)
                        .fontWeight(.medium)
                } else if showingOriginal && processedImage != nil {
                    Label("Original Image (Hold to Compare)", systemImage: "photo")
                        .foregroundStyle(.blue)
                        .font(.title3)
                        .fontWeight(.medium)
                } else if let _ = processedImage {
                    Label("Dust-Free Result", systemImage: "sparkles.tv.fill")
                        .foregroundStyle(.orange)
                        .font(.title3)
                        .fontWeight(.medium)
                } else if dustMask != nil {
                    Label("Dust Detection Preview", systemImage: "magnifyingglass.circle.fill")
                        .foregroundStyle(.red)
                        .font(.title3)
                        .fontWeight(.medium)
                } else if let _ = selectedImage {
                    Label("Original Image", systemImage: "photo")
                        .foregroundStyle(.blue)
                        .font(.title3)
                        .fontWeight(.medium)
                } else {
                    Label("No Image Selected", systemImage: "photo.artframe")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                        .fontWeight(.medium)
                }
                Spacer()
                
                // Zoom controls and instruction text
                if selectedImage != nil || processedImage != nil {
                    HStack(spacing: 12) {
                        // Zoom controls
                        HStack(spacing: 8) {
                            Button(action: { zoomOut() }) {
                                Image(systemName: "minus.magnifyingglass")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .disabled(zoomScale <= 1.0)
                            
                            Text("\(String(format: "%.0f", zoomScale * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 32)
                            
                            Button(action: { zoomIn() }) {
                                Image(systemName: "plus.magnifyingglass")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .disabled(zoomScale >= 5.0)
                            
                            Button(action: { resetZoom() }) {
                                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .disabled(zoomScale == 1.0 && dragOffset == .zero)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        
                        if processedImage != nil && !showingOriginal {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Hold to see original")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if dustMask != nil && !hideDetections && processedImage == nil {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Hold to hide detections")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.regularMaterial, in: Rectangle())
            
            // Image Display Area
            GeometryReader { geometry in
                ZStack {
                    // Background
                    Rectangle()
                        .fill(.quinary)
                    
                    if selectedImage == nil && processedImage == nil {
                        // Drop zone when no image
                        VStack(spacing: 24) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 64, weight: .ultraLight))
                                .foregroundStyle(.tertiary)
                            
                            VStack(spacing: 8) {
                                Text("Drag and drop an image here")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                
                                Text("or click \"Choose File\" to browse")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                
                                Text("Supported: PNG, JPEG, TIFF")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Display current image with optional dust overlay
                        let imageToShow: NSImage? = {
                            if hideDetections && dustMask != nil {
                                return selectedImage
                            } else if showingOriginal && selectedImage != nil {
                                return selectedImage
                            } else if processedImage != nil {
                                return processedImage
                            } else {
                                return selectedImage
                            }
                        }()
                        
                        if let image = imageToShow {
                            ZStack {
                                // Base image
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                                
                                // Red dust overlay (only when dust is detected and not hiding detections)
                                if let dustMask = dustMask, !hideDetections, processedImage == nil, !showingOriginal {
                                    Image(nsImage: dustMask)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                                        .blendMode(.multiply)
                                        .colorMultiply(.red)
                                        .opacity(0.6)
                                }
                            }
                            .scaleEffect(zoomScale, anchor: zoomAnchor)
                            .offset(dragOffset)
                            .clipped()
                                .onTapGesture(count: 2) {
                                    // Double-tap to reset zoom
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        zoomScale = 1.0
                                        dragOffset = .zero
                                        zoomAnchor = .center
                                    }
                                }
                                .onLongPressGesture(minimumDuration: 0.1, maximumDistance: 50) {
                                    // Long press ended
                                    if processedImage != nil {
                                        showingOriginal = false
                                    } else if dustMask != nil {
                                        hideDetections = false
                                    }
                                } onPressingChanged: { pressing in
                                    // Handle press state changes
                                    if pressing && processedImage != nil && selectedImage != nil {
                                        // Show original while pressing (existing behavior)
                                        showingOriginal = true
                                        hideDetections = false
                                    } else if pressing && dustMask != nil && processedImage == nil {
                                        // Hide detections while pressing (new behavior)
                                        hideDetections = true
                                        showingOriginal = false
                                    } else {
                                        // Release: restore normal state
                                        showingOriginal = false
                                        hideDetections = false
                                    }
                                }
                                .simultaneousGesture(
                                    // Magnification gesture for pinch-to-zoom
                                    MagnificationGesture()
                                        .onChanged { value in
                                            let newScale = max(1.0, min(value, 5.0))
                                            zoomScale = newScale
                                        }
                                        .onEnded { value in
                                            let finalScale = max(1.0, min(value, 5.0))
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                zoomScale = finalScale
                                                if finalScale == 1.0 {
                                                    dragOffset = .zero
                                                }
                                            }
                                        }
                                )
                                .simultaneousGesture(
                                    // Drag gesture for panning when zoomed
                                    DragGesture()
                                        .onChanged { value in
                                            if zoomScale > 1.0 {
                                                dragOffset = value.translation
                                            }
                                        }
                                        .onEnded { value in
                                            if zoomScale > 1.0 {
                                                withAnimation(.easeOut(duration: 0.1)) {
                                                    dragOffset = value.translation
                                                }
                                            }
                                        }
                                )
                                .animation(.easeInOut(duration: 0.2), value: showingOriginal)
                                .animation(.easeInOut(duration: 0.2), value: hideDetections)
                        }
                    }
                }
            }
            .onDrop(of: [.image], isTargeted: nil) { providers in
                handleDrop(providers: providers)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helper Functions
    
    private func resetProcessing() {
        processedImage = nil
        rawPrediction = nil
        dustMask = nil
        rawPredictionMask = nil
        hideDetections = false
        resetZoom()
    }
    
    // MARK: - Action Functions
    
    private func detectDust() {
        guard let selectedImage = selectedImage, let model = model else { return }
        
        isDetecting = true
        
        Task {
            do {
                // Run UNet dust detection
                let unetSize = CGSize(width: 1024, height: 1024)
                let resizedImage = selectedImage.resized(to: unetSize)
                
                guard let pixelBuffer = resizedImage.toCVPixelBuffer() else {
                    throw NSError(domain: "ImageProcessing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to convert to pixel buffer"])
                }
                
                let input = UNetDustInput(input: pixelBuffer)
                let unetModel = UNetDust(model: model)
                
                let prediction = try await unetModel.prediction(input: input)
                let output = prediction.output
                
                await MainActor.run {
                    // Store raw prediction for threshold tuning
                    rawPredictionMask = output
                    
                    // Create initial dust mask with current threshold
                    updateDustMaskWithThreshold()
                    
                    isDetecting = false
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = "Dust detection failed: \(error.localizedDescription)"
                    showingError = true
                    isDetecting = false
                }
            }
        }
    }
    
    private func removeDust() {
        guard let selectedImage = selectedImage, 
              let lamaModel = lamaModel,
              let dustMask = dustMask else { return }
        
        isRemoving = true
        
        Task {
            do {
                let startTime = CFAbsoluteTimeGetCurrent()
                
                // Dilate the mask for better inpainting coverage
                guard let dilatedMask = dilateMask(dustMask) else {
                    throw NSError(domain: "ImageProcessing", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to dilate mask"])
                }
                
                // Resize for LaMa (exactly 800x800)
                let lamaSize = CGSize(width: 800, height: 800)
                let resizedForLama = selectedImage.resized(to: lamaSize)
                let resizedMaskForLama = dilatedMask.resized(to: lamaSize)
                
                guard let rgbPixelBuffer = resizedForLama.toCVPixelBufferRGB(),
                      let maskPixelBuffer = resizedMaskForLama.toCVPixelBuffer() else {
                    throw NSError(domain: "ImageProcessing", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to convert to LaMa pixel buffers"])
                }
                
                let lamaInput = LaMaInput(image: rgbPixelBuffer, mask: maskPixelBuffer)
                let lama = LaMa(model: lamaModel)
                
                print("🚀 Running LaMa inpainting...")
                let lamaOutput = try await lama.prediction(input: lamaInput)
                
                guard let resultImage = NSImage(cvPixelBuffer: lamaOutput.output) else {
                    throw NSError(domain: "ImageProcessing", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to convert LaMa output to NSImage"])
                }
                
                let finalImage = resultImage.resized(to: selectedImage.size)
                
                let endTime = CFAbsoluteTimeGetCurrent()
                
                await MainActor.run {
                    processedImage = finalImage
                    processingTime = endTime - startTime
                    isRemoving = false
                    print("⏱️ Dust removal completed in \(String(format: "%.2f", processingTime))s")
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = "Dust removal failed: \(error.localizedDescription)"
                    showingError = true
                    isRemoving = false
                }
            }
        }
    }
    
    private func updateDustMaskWithThreshold() {
        guard let rawPredictionMask = rawPredictionMask else { return }
        
        dustMask = createBinaryMask(from: rawPredictionMask, threshold: threshold)
    }
    
    // MARK: - Image Processing Helper Functions
    
    private func createBinaryMask(from multiArray: MLMultiArray, threshold: Float) -> NSImage? {
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
    
    private func dilateMask(_ mask: NSImage) -> NSImage? {
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
    
    // MARK: - Zoom Functions
    
    private func zoomIn() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = min(zoomScale * 1.5, 5.0)
        }
    }
    
    private func zoomOut() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = max(zoomScale / 1.5, 1.0)
            if zoomScale == 1.0 {
                dragOffset = .zero
            }
        }
    }
    
    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.3)) {
            zoomScale = 1.0
            dragOffset = .zero
            zoomAnchor = .center
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        if provider.hasItemConformingToTypeIdentifier("public.image") {
            provider.loadItem(forTypeIdentifier: "public.image", options: nil) { item, error in
                if let url = item as? URL {
                    DispatchQueue.main.async {
                        self.selectedImage = NSImage(contentsOf: url)
                    }
                } else if let data = item as? Data {
                    DispatchQueue.main.async {
                        self.selectedImage = NSImage(data: data)
                    }
                }
            }
            return true
        }
        return false
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
        let resizedMask = maskImage.resized(to: lamaSize).toGrayscale() // Keep mask as grayscale (OneComponent8)
        
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
                print("  \(key): \(desc.type)")
                if case .image = desc.type {
                    print("    Type: Image input")
                }
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
    
    func toRGB() -> NSImage {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, 
                               width: Int(size.width), 
                               height: Int(size.height), 
                               bitsPerComponent: 8, 
                               bytesPerRow: 0, 
                               space: colorSpace, 
                               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        
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
                                       kCVPixelFormatType_32ARGB, // Use ARGB for LaMa input
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
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue), // ARGB
              let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return buffer
    }
    
    convenience init?(cvPixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: cvPixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        self.init(cgImage: cgImage, size: ciImage.extent.size)
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
