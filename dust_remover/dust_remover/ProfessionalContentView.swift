//
//  ProfessionalContentView.swift
//  dust_remover
//
//  Professional UI redesign following UX research recommendations
//

import SwiftUI
import CoreML

struct ProfessionalContentView: View {
    @StateObject private var state = DustRemovalState()
    @State private var showingImagePicker = false
    @State private var showingInspector = false
    @State private var compareMode: CompareMode = .single
    @State private var splitPosition: CGFloat = 0.5
    
    enum CompareMode: CaseIterable {
        case single, sideBySide, splitSlider
        
        var icon: String {
            switch self {
            case .single: return "photo"
            case .sideBySide: return "rectangle.split.2x1"
            case .splitSlider: return "slider.horizontal.2.rectangle"
            }
        }
        
        var label: String {
            switch self {
            case .single: return "Single"
            case .sideBySide: return "Side by Side"
            case .splitSlider: return "Split View"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Left Sidebar - Library & Actions
            ProfessionalSidebar(
                state: state,
                onImportImage: { showingImagePicker = true },
                onDetectDust: detectDust,
                onRemoveDust: removeDust,
                onThresholdChanged: updateDustMaskWithThreshold
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 320)
        } detail: {
            // Main Content Area
            VStack(spacing: 0) {
                // Unified Toolbar - Fixed position, not affected by zoom
                ProfessionalToolbar(
                    state: state,
                    compareMode: $compareMode,
                    showingInspector: $showingInspector,
                    onImportImage: { showingImagePicker = true },
                    onDetectDust: detectDust,
                    onRemoveDust: removeDust,
                    onExportImage: saveProcessedImage
                )
                .zIndex(1000) // Ensure toolbar stays on top
                .allowsHitTesting(true) // Ensure toolbar can receive touches
                .clipped() // Prevent any overflow issues
                
                // Canvas + Optional Inspector
                HStack(spacing: 0) {
                    // Main Canvas - Isolated gesture handling
                    ProfessionalCanvas(
                        state: state,
                        compareMode: compareMode,
                        splitPosition: $splitPosition,
                        onDrop: handleDrop,
                        onEraserClick: eraseDustAtPoint
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped() // Contain all canvas gestures within this area
                    
                    // Right Inspector (collapsible)
                    if showingInspector {
                        Divider()
                        ProfessionalInspector(state: state)
                            .frame(width: 280)
                            .allowsHitTesting(true) // Ensure inspector is also touchable
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("")
        }
        .navigationSplitViewStyle(.balanced)
        .background(.windowBackground)
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $state.selectedImage)
        }
        .onChange(of: state.selectedImage) { _, _ in
            resetProcessing()
        }
        .onAppear {
            loadModels()
        }
        .alert("Error", isPresented: $state.showingError) {
            Button("OK") { }
        } message: {
            Text(state.errorMessage ?? "Unknown error occurred")
        }
        .onKeyPress(.init("m")) {
            // Toggle mask overlay
            if state.dustMask != nil {
                state.hideDetections.toggle()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.init("c")) {
            // Toggle compare mode
            toggleCompareMode()
            return .handled
        }
        .onKeyPress(.init(" ")) { // Space key
            // Space key for pan mode when eraser is active
            if state.eraserToolActive {
                state.spaceKeyPressed = true
                return .handled
            }
            return .ignored
        }
        .onKeyPress(phases: .up) { keyPress in
            // Handle key release
            if keyPress.characters == " " && state.eraserToolActive {
                state.spaceKeyPressed = false
                return .handled
            }
            return .ignored
        }
    }
    
    // MARK: - Helper Functions
    
    private func toggleCompareMode() {
        guard state.processedImage != nil || state.dustMask != nil else { return }
        
        let allCases = CompareMode.allCases
        let currentIndex = allCases.firstIndex(of: compareMode) ?? 0
        let nextIndex = (currentIndex + 1) % allCases.count
        compareMode = allCases[nextIndex]
    }
    
    private func resetProcessing() {
        state.processedImage = nil
        state.dustMask = nil
        state.rawPredictionMask = nil
        state.hideDetections = false
        state.resetZoom()
        compareMode = .single
    }
    
    private func detectDust() {
        guard let selectedImage = state.selectedImage, let model = state.unetModel else { return }
        
        state.isDetecting = true
        
        Task {
            do {
                let unetSize = CGSize(width: 1024, height: 1024)
                let resizedImage = selectedImage.resized(to: unetSize)
                
                guard let pixelBuffer = resizedImage.toCVPixelBuffer() else {
                    throw ProcessingError.pixelBufferCreationFailed
                }
                
                let input = UNetDustInput(input: pixelBuffer)
                let unetModel = UNetDust(model: model)
                
                // Configure for performance
                let configuration = MLPredictionOptions()
                configuration.usesCPUOnly = false // Ensure GPU/Neural Engine is used
                
                let prediction = try await unetModel.prediction(input: input, options: configuration)
                let output = prediction.output
                
                await MainActor.run {
                    state.rawPredictionMask = output
                    updateDustMaskWithThreshold()
                    state.isDetecting = false
                    
                    // Pulse effect when detection completes
                    withAnimation(.easeInOut(duration: 0.2)) {
                        // This could trigger a visual pulse effect
                    }
                }
                
            } catch {
                await MainActor.run {
                    state.errorMessage = "Dust detection failed: \(error.localizedDescription)"
                    state.showingError = true
                    state.isDetecting = false
                }
            }
        }
    }
    
    private func removeDust() {
        guard let selectedImage = state.selectedImage,
              let lamaModel = state.lamaModel,
              let dustMask = state.dustMask else { return }
        
        state.isRemoving = true
        
        Task {
            do {
                let startTime = CFAbsoluteTimeGetCurrent()
                
                // Dilate the mask for better inpainting coverage
                guard let dilatedMask = dilateMask(dustMask) else {
                    throw ProcessingError.maskProcessingFailed
                }
                
                // Resize for LaMa (exactly 800x800)
                let lamaSize = CGSize(width: 800, height: 800)
                let resizedForLama = selectedImage.resized(to: lamaSize)
                let resizedMaskForLama = dilatedMask.resized(to: lamaSize)
                
                guard let rgbPixelBuffer = resizedForLama.toCVPixelBufferRGB(),
                      let maskPixelBuffer = resizedMaskForLama.toCVPixelBuffer() else {
                    throw ProcessingError.pixelBufferCreationFailed
                }
                
                let lamaInput = LaMaInput(image: rgbPixelBuffer, mask: maskPixelBuffer)
                let lama = LaMa(model: lamaModel)
                
                let lamaOutput = try await lama.prediction(input: lamaInput)
                
                guard let resultImage = NSImage(cvPixelBuffer: lamaOutput.output) else {
                    throw ProcessingError.outputProcessingFailed
                }
                
                // Blend inpainted result with original image using mask
                let upscaledInpainted = resultImage.resized(to: selectedImage.size)
                guard let finalImage = blendImages(original: selectedImage, inpainted: upscaledInpainted, mask: dilatedMask) else {
                    throw ProcessingError.outputProcessingFailed
                }
                
                let endTime = CFAbsoluteTimeGetCurrent()
                
                await MainActor.run {
                    state.processedImage = finalImage
                    state.processingTime = endTime - startTime
                    state.isRemoving = false
                    compareMode = .sideBySide // Automatically switch to compare mode
                }
                
            } catch {
                await MainActor.run {
                    state.errorMessage = "Dust removal failed: \(error.localizedDescription)"
                    state.showingError = true
                    state.isRemoving = false
                }
            }
        }
    }
    
    private func updateDustMaskWithThreshold() {
        guard let rawPredictionMask = state.rawPredictionMask,
              let originalImage = state.selectedImage else { return }
        
        state.dustMask = createBinaryMask(from: rawPredictionMask, threshold: state.threshold, originalSize: originalImage.size)
    }
    
    private func createBinaryMask(from multiArray: MLMultiArray, threshold: Float, originalSize: CGSize) -> NSImage? {
        let shape = multiArray.shape
        guard shape.count == 4,
              let width = shape[3] as? Int,
              let height = shape[2] as? Int else {
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
            return nil
        }
        
        let maskImage = NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
        return maskImage.resized(to: originalSize)
    }
    
    private func dilateMask(_ mask: NSImage) -> NSImage? {
        guard let cgImage = mask.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(data: nil, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height)
        
        var dilatedData = Data(count: width * height)
        dilatedData.withUnsafeMutableBytes { ptr in
            let dilatedBuffer = ptr.bindMemory(to: UInt8.self)
            
            // Optimized dilation using concurrent dispatch
            DispatchQueue.concurrentPerform(iterations: height) { y in
                for x in 0..<width {
                    let index = y * width + x
                    var maxValue: UInt8 = 0
                    
                    // Optimized neighborhood check
                    let minY = max(0, y - 1)
                    let maxY = min(height - 1, y + 1)
                    let minX = max(0, x - 1)
                    let maxX = min(width - 1, x + 1)
                    
                    for ny in minY...maxY {
                        for nx in minX...maxX {
                            let neighborIndex = ny * width + nx
                            let value = buffer[neighborIndex]
                            if value > maxValue {
                                maxValue = value
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
    
    private func blendImages(original: NSImage, inpainted: NSImage, mask: NSImage) -> NSImage? {
        let size = original.size
        
        // Create output image context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil,
                                    width: Int(size.width),
                                    height: Int(size.height),
                                    bitsPerComponent: 8,
                                    bytesPerRow: 0,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        
        // Get CGImages
        guard let originalCG = original.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let inpaintedCG = inpainted.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let maskCG = mask.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        // Draw original image as base
        context.draw(originalCG, in: CGRect(origin: .zero, size: size))
        
        // Create mask for inpainted areas
        context.saveGState()
        context.clip(to: CGRect(origin: .zero, size: size), mask: maskCG)
        
        // Draw inpainted image only in masked areas
        context.draw(inpaintedCG, in: CGRect(origin: .zero, size: size))
        context.restoreGState()
        
        guard let outputCGImage = context.makeImage() else {
            return nil
        }
        
        return NSImage(cgImage: outputCGImage, size: size)
    }
    
    private func eraseDustAtPoint(_ point: CGPoint, in canvasSize: CGSize) {
        print("🖱️ Eraser tool activated at point: \(point)")
        
        do {
            guard let dustMask = state.dustMask,
                  let selectedImage = state.selectedImage else {
                print("❌ Missing dust mask or selected image")
                return
            }
            
            // Get actual image and mask dimensions
            let imageSize = selectedImage.size
            guard let cgImage = dustMask.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                print("❌ Failed to get CGImage from mask")
                return
            }
            
            let maskPixelWidth = cgImage.width
            let maskPixelHeight = cgImage.height
            
            guard maskPixelWidth > 0 && maskPixelHeight > 0 else {
                print("❌ Invalid mask pixel dimensions: \(maskPixelWidth)x\(maskPixelHeight)")
                return
            }
            
            print("🔍 Image size: \(imageSize), Mask pixels: \(maskPixelWidth)x\(maskPixelHeight), Canvas: \(canvasSize)")
            
            // Calculate actual displayed image bounds (accounting for aspect ratio fit)
            let imageAspect = imageSize.width / imageSize.height
            let canvasAspect = canvasSize.width / canvasSize.height
            
            var displayedImageRect: CGRect
            
            if imageAspect > canvasAspect {
                // Image is wider - letterboxed top/bottom
                let displayedHeight = canvasSize.width / imageAspect
                let offsetY = (canvasSize.height - displayedHeight) / 2
                displayedImageRect = CGRect(x: 0, y: offsetY, width: canvasSize.width, height: displayedHeight)
            } else {
                // Image is taller - letterboxed left/right  
                let displayedWidth = canvasSize.height * imageAspect
                let offsetX = (canvasSize.width - displayedWidth) / 2
                displayedImageRect = CGRect(x: offsetX, y: 0, width: displayedWidth, height: canvasSize.height)
            }
            
            print("📐 Displayed image rect: \(displayedImageRect)")
            
            // Check if click is within the actual displayed image area
            guard displayedImageRect.contains(point) else {
                print("❌ Click outside displayed image area")
                return
            }
            
            // Convert click to image coordinates (0-1 normalized within the image)
            let relativeX = (point.x - displayedImageRect.minX) / displayedImageRect.width
            let relativeY = (point.y - displayedImageRect.minY) / displayedImageRect.height
            
            // Apply zoom/pan transformations
            let zoomedX = (relativeX - 0.5) / state.zoomScale + 0.5 - (state.dragOffset.width / (displayedImageRect.width * state.zoomScale))
            let zoomedY = (relativeY - 0.5) / state.zoomScale + 0.5 - (state.dragOffset.height / (displayedImageRect.height * state.zoomScale))
            
            // Convert to mask pixel coordinates
            let maskX = zoomedX * CGFloat(maskPixelWidth)
            let maskY = zoomedY * CGFloat(maskPixelHeight)
            
            let maskPoint = CGPoint(x: maskX, y: maskY)
            
            print("📍 Canvas: \(point) → Image relative: (\(relativeX), \(relativeY)) → Zoomed: (\(zoomedX), \(zoomedY)) → Mask: \(maskPoint)")
            
            // Bounds check using actual pixel dimensions
            guard maskX >= 0 && maskX < CGFloat(maskPixelWidth) &&
                  maskY >= 0 && maskY < CGFloat(maskPixelHeight) else {
                print("❌ Point out of mask bounds: \(maskPoint) for pixel size \(maskPixelWidth)x\(maskPixelHeight)")
                return
            }
            
            // Use flood fill to remove connected dust particles
            if let updatedMask = floodFillRemove(mask: dustMask, at: maskPoint) {
                print("🔄 Updating state with new mask...")
                DispatchQueue.main.async {
                    self.state.dustMask = updatedMask
                    print("📝 State updated successfully")
                }
                print("✅ Mask updated with flood fill")
            } else {
                print("❌ Flood fill failed")
            }
            
        } catch {
            print("💥 Eraser error: \(error)")
        }
    }
    
    private func simpleErase(mask: NSImage, at point: CGPoint) -> NSImage? {
        guard let cgImage = mask.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("❌ Failed to get CGImage from mask")
            return nil
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        guard width > 0 && height > 0 else {
            print("❌ Invalid CGImage dimensions: \(width)x\(height)")
            return nil
        }
        
        let x = Int(point.x.rounded())
        let y = Int(point.y.rounded())
        
        guard x >= 0 && x < width && y >= 0 && y < height else {
            print("❌ Point out of bounds: (\(x), \(y)) for image \(width)x\(height)")
            return mask
        }
        
        // Create a simple 5x5 erase area
        let eraseRadius = 2
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width
        
        guard let context = CGContext(data: nil, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            print("❌ Failed to create CGContext")
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else {
            print("❌ Failed to get context data")
            return nil
        }
        
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height)
        
        // Erase a small area around the click point
        for dy in -eraseRadius...eraseRadius {
            for dx in -eraseRadius...eraseRadius {
                let pixelX = x + dx
                let pixelY = y + dy
                
                if pixelX >= 0 && pixelX < width && pixelY >= 0 && pixelY < height {
                    let index = pixelY * width + pixelX
                    if index >= 0 && index < width * height {
                        buffer[index] = 0 // Set to black (no dust)
                    }
                }
            }
        }
        
        guard let newCGImage = context.makeImage() else {
            print("❌ Failed to create new CGImage")
            return nil
        }
        
        return NSImage(cgImage: newCGImage, size: mask.size)
    }
    
    private func floodFillRemove(mask: NSImage, at point: CGPoint) -> NSImage? {
        print("🌊 Starting flood fill at point: \(point)")
        
        guard let cgImage = mask.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("❌ Failed to get CGImage from mask")
            return nil
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Safety check for valid dimensions
        guard width > 0 && height > 0 else {
            print("❌ Invalid image dimensions: \(width)x\(height)")
            return mask
        }
        
        // Check if point is within bounds
        let x = Int(point.x.rounded())
        let y = Int(point.y.rounded())
        
        guard x >= 0 && x < width && y >= 0 && y < height else {
            print("❌ Point out of bounds: (\(x), \(y)) for image \(width)x\(height)")
            return mask
        }
        
        print("📐 Image size: \(width)x\(height), Click point: (\(x), \(y))")
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width
        let dataSize = width * height
        
        guard let context = CGContext(data: nil, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            print("❌ Failed to create CGContext")
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else { 
            print("❌ Failed to get context data")
            return nil 
        }
        
        let buffer = data.bindMemory(to: UInt8.self, capacity: dataSize)
        
        // Get the value at the clicked point
        let clickedIndex = y * width + x
        guard clickedIndex >= 0 && clickedIndex < dataSize else {
            print("❌ Clicked index out of bounds: \(clickedIndex) for size \(dataSize)")
            return mask
        }
        
        // Find all dust pixels in a larger area around the click point
        let searchRadius = 3 // Larger search area (7x7)
        var dustPixels: [(Int, Int)] = []
        
        print("🔍 Searching for dust in 7x7 area around (\(x), \(y))")
        
        // Collect all dust pixels in the search area
        for dy in -searchRadius...searchRadius {
            for dx in -searchRadius...searchRadius {
                let checkX = x + dx
                let checkY = y + dy
                
                if checkX >= 0 && checkX < width && checkY >= 0 && checkY < height {
                    let checkIndex = checkY * width + checkX
                    let pixelValue = buffer[checkIndex]
                    
                    // Show what we find at center and dust pixels
                    if dx == 0 && dy == 0 {
                        print("🎯 Center pixel (\(checkX), \(checkY)): \(pixelValue)")
                    }
                    
                    if pixelValue > 128 {
                        dustPixels.append((checkX, checkY))
                        print("✅ Found dust pixel at (\(checkX), \(checkY)) with value: \(pixelValue)")
                    }
                }
            }
        }
        
        guard !dustPixels.isEmpty else {
            print("❌ No dust pixels found in search area")
            return mask
        }
        
        print("🎯 Found \(dustPixels.count) dust pixels to flood fill from")
        
        // Create a copy of the buffer data for modification
        guard let mutableData = NSMutableData(length: dataSize) else {
            print("❌ Failed to create mutable data")
            return nil
        }
        
        mutableData.replaceBytes(in: NSRange(location: 0, length: dataSize), withBytes: buffer)
        let mutableBuffer = mutableData.mutableBytes.bindMemory(to: UInt8.self, capacity: dataSize)
        
        // Debug: Mark the clicked area with a small cross pattern for visual verification
        let debugRadius = 1
        for dy in -debugRadius...debugRadius {
            for dx in -debugRadius...debugRadius {
                let debugX = x + dx
                let debugY = y + dy
                if debugX >= 0 && debugX < width && debugY >= 0 && debugY < height {
                    let debugIndex = debugY * width + debugX
                    if (dx == 0 || dy == 0) { // Cross pattern
                        mutableBuffer[debugIndex] = 128 // Gray to show click location
                    }
                }
            }
        }
        
        // Flood fill to remove connected dust pixels starting from all found dust pixels
        var pixelsToCheck = dustPixels
        var visited = Set<Int>()
        var pixelsChanged = 0
        
        print("🌊 Starting area-based flood fill from \(dustPixels.count) seed pixels...")
        
        while !pixelsToCheck.isEmpty {
            let (currentX, currentY) = pixelsToCheck.removeFirst()
            
            guard currentX >= 0 && currentX < width,
                  currentY >= 0 && currentY < height else {
                continue
            }
            
            let currentIndex = currentY * width + currentX
            guard currentIndex >= 0 && currentIndex < dataSize,
                  !visited.contains(currentIndex) else {
                continue
            }
            
            visited.insert(currentIndex)
            
            // If this pixel is dust (similar to target), remove it
            if mutableBuffer[currentIndex] > 128 {
                mutableBuffer[currentIndex] = 0 // Set to black (no dust)
                pixelsChanged += 1
                
                // Add neighbors to check
                pixelsToCheck.append((currentX + 1, currentY))
                pixelsToCheck.append((currentX - 1, currentY))
                pixelsToCheck.append((currentX, currentY + 1))
                pixelsToCheck.append((currentX, currentY - 1))
            }
        }
        
        print("🔢 Pixels changed: \(pixelsChanged)")
        
        // Only create new image if we actually changed something
        guard pixelsChanged > 0 else {
            print("⚠️ No pixels were changed")
            return mask
        }
        
        // Create new image from modified buffer
        guard let dataProvider = CGDataProvider(data: mutableData),
              let newCGImage = CGImage(width: width, height: height,
                                     bitsPerComponent: 8, bitsPerPixel: 8,
                                     bytesPerRow: bytesPerRow,
                                     space: colorSpace,
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                     provider: dataProvider, decode: nil,
                                     shouldInterpolate: false, intent: .defaultIntent) else {
            print("❌ Failed to create new CGImage")
            return nil
        }
        
        let newImage = NSImage(cgImage: newCGImage, size: mask.size)
        print("✅ Successfully created new mask image")
        return newImage
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        if provider.hasItemConformingToTypeIdentifier("public.image") {
            provider.loadItem(forTypeIdentifier: "public.image", options: nil) { item, error in
                if let url = item as? URL {
                    DispatchQueue.main.async {
                        self.state.selectedImage = NSImage(contentsOf: url)
                    }
                } else if let data = item as? Data {
                    DispatchQueue.main.async {
                        self.state.selectedImage = NSImage(data: data)
                    }
                }
            }
            return true
        }
        return false
    }
    
    private func loadModels() {
        Task {
            do {
                // Load UNet model
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
                
                let model = try MLModel(contentsOf: dustURL)
                await MainActor.run {
                    state.unetModel = model
                }
                
                // Load LaMa model
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
                
                let lamaModel = try MLModel(contentsOf: lamaURL)
                await MainActor.run {
                    state.lamaModel = lamaModel
                }
                
            } catch {
                await MainActor.run {
                    state.errorMessage = "Failed to load AI models: \(error.localizedDescription)"
                    state.showingError = true
                }
            }
        }
    }
    
    private func saveProcessedImage() {
        guard let processedImage = state.processedImage else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "dust_removed_\(Int(Date().timeIntervalSince1970)).png"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                if let tiffData = processedImage.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                    
                    try pngData.write(to: url)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } catch {
                state.errorMessage = "Failed to save image: \(error.localizedDescription)"
                state.showingError = true
            }
        }
    }
}

#Preview {
    ProfessionalContentView()
}