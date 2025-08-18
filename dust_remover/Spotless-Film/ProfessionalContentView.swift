//
//  ProfessionalContentView.swift
//  dust_remover
//
//  Professional UI redesign following UX research recommendations
//

import SwiftUI
import CoreML
import Accelerate

struct ProfessionalContentView: View {
    @StateObject private var state = DustRemovalState()
    @State private var showingImagePicker = false
    @State private var showingInspector = false
    @State private var compareMode: CompareMode = .single
    @State private var splitPosition: CGFloat = 0.5
    
    // Local monitor handle
    @State private var keyMonitor: Any?
    
    enum CompareMode: CaseIterable {
        case single, sideBySide, splitSlider
        
        var icon: String {
            switch self {
            case .single: return "photo"
            case .sideBySide: return "rectangle.split.2x1"
            case .splitSlider: return "rectangle.split.2x1.slash"
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
                    onExportImage: saveProcessedImage,
                    onThresholdChanged: updateDustMaskWithThreshold
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
                        onEraserClick: eraseDustAtPoint,
                        onEraserEnd: { state.endBrushStroke() },
                        onBrushClick: addDustAtPoint,
                        onBrushEnd: { state.endBrushStroke() }
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
            // Add key monitor for Space bar and Cmd+Z
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
                if event.keyCode == 49 { // Space bar keyCode
                    if event.type == .keyDown {
                        DispatchQueue.main.async {
                            state.spaceKeyPressed = true
                            // Update cursor when space is pressed (show open hand)
                            if state.eraserToolActive || state.brushToolActive {
                                NSCursor.openHand.set()
                            }
                        }
                    } else if event.type == .keyUp {
                        DispatchQueue.main.async {
                            state.spaceKeyPressed = false
                            // Update cursor when space is released (restore tool cursor)
                            if state.eraserToolActive || state.brushToolActive {
                                state.createCircularCursor(size: state.brushSize).set()
                            }
                        }
                    }
                    return nil // swallow space to prevent system beep
                } else if event.keyCode == 6 && event.modifierFlags.contains(.command) && event.type == .keyDown { // Z key with Cmd
                    if state.canUndo {
                        DispatchQueue.main.async {
                            state.undoLastMaskChange()
                        }
                    }
                    return nil // swallow the event
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
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
            state.spaceKeyPressed = true
            // Update cursor when space is pressed (show open hand)
            if state.eraserToolActive || state.brushToolActive {
                NSCursor.openHand.set()
            }
            return .handled
        }
        .onKeyPress(phases: .up) { keyPress in
            // Handle key release
            if keyPress.characters == " " {
                state.spaceKeyPressed = false
                // Update cursor when space is released (restore tool cursor)
                if state.eraserToolActive || state.brushToolActive {
                    state.createCircularCursor(size: state.brushSize).set()
                }
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
        let newMode = allCases[nextIndex]
        
        // Auto-disable overlay when switching to split view
        if newMode == .splitSlider {
            state.hideDetections = true
        }
        
        compareMode = newMode
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
                let output = try await ImageProcessingService.detectDust(
                    in: selectedImage,
                    using: model
                )
                
                await MainActor.run {
                    state.rawPredictionMask = output
                    updateDustMaskWithThreshold()
                    
                    // Store the original mask before any brush modifications
                    state.originalDustMask = state.dustMask
                    
                    state.isDetecting = false
                    
                    // Clear undo history and save initial detection state
                    state.clearMaskHistory()
                    if state.dustMask != nil {
                        state.saveMaskToHistory()
                    }
                    
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
                let dilatedMask = dilateMask(dustMask) ?? dustMask // fallback to original mask if dilation fails
                print("🔍 Dilated mask successfully")
                
                // Resize for LaMa (exactly 1600x1600)
                let lamaSize = CGSize(width: 1600, height: 1600)
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
                
                // Debug logging
                print("🔍 Original image size: \(selectedImage.size)")
                print("🔍 LaMa result size: \(resultImage.size)")
                print("🔍 Dust mask size: \(dustMask.size)")
                
                // Blend inpainted result with original image using mask
                let upscaledInpainted = resultImage.resized(to: selectedImage.size)
                print("🔍 Upscaled inpainted size: \(upscaledInpainted.size)")
                
                // Use the original full-resolution mask for blending, dilated at original size
                let originalSizeDilatedMask = dilateMask(dustMask) ?? dustMask
                print("🔍 Final mask size: \(originalSizeDilatedMask.size)")
                
                guard let finalImage = blendImages(original: selectedImage, inpainted: upscaledInpainted, mask: originalSizeDilatedMask) else {
                    throw ProcessingError.outputProcessingFailed
                }
                
                print("🔍 Final image size: \(finalImage.size)")
                
                let endTime = CFAbsoluteTimeGetCurrent()
                
                await MainActor.run {
                    state.processedImage = finalImage
                    state.processingTime = endTime - startTime
                    state.isRemoving = false
                    state.hideDetections = true // Auto-disable overlay when switching to split view
                    compareMode = .splitSlider // Automatically switch to split view mode
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
        
        // Store current brush modifications (if any)
        let currentMask = state.dustMask
        
        // Generate new mask from raw prediction with new threshold
        let newBaseMask = createBinaryMask(from: rawPredictionMask, threshold: state.threshold, originalSize: originalImage.size)
        
        // If we have previous brush modifications, apply them to the new mask
        if let existingMask = currentMask, let baseMask = newBaseMask {
            // We need the original mask that was generated before any brush modifications
            // For now, we'll store the original in the state when detection completes
            state.dustMask = applyBrushModifications(to: baseMask, from: existingMask)
        } else {
            state.dustMask = newBaseMask
        }
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
        guard let cgImage = mask.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        // Calculate kernel size proportional to image size
        let imageWidth = cgImage.width
        let imageHeight = cgImage.height
        let minDimension = min(imageWidth, imageHeight)
        
        // Scale kernel size: 0.3% of minimum dimension, minimum 5, maximum 15
        let kernelSize = max(5, min(15, Int(Double(minDimension) * 0.003)))
        
        // Ensure kernel size is odd
        let finalKernelSize = kernelSize % 2 == 0 ? kernelSize + 1 : kernelSize
        
        print("🔍 Dilating mask: image \(imageWidth)x\(imageHeight), kernel size \(finalKernelSize)x\(finalKernelSize)")

        // Create source vImage buffer
        var format = vImage_CGImageFormat(bitsPerComponent: 8,
                                          bitsPerPixel: 8,
                                          colorSpace: nil,
                                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                          version: 0,
                                          decode: nil,
                                          renderingIntent: .defaultIntent)
        var srcBuffer = vImage_Buffer()
        var error = vImageBuffer_InitWithCGImage(&srcBuffer, &format, nil, cgImage, vImage_Flags(kvImageNoFlags))
        guard error == kvImageNoError else { return nil }

        // Create destination buffer
        var dstBuffer = vImage_Buffer()
        error = vImageBuffer_Init(&dstBuffer, srcBuffer.height, srcBuffer.width, 8, vImage_Flags(kvImageNoFlags))
        guard error == kvImageNoError else { return nil }

        // Create circular kernel proportional to image size
        var kernel = Array(repeating: UInt8(1), count: finalKernelSize * finalKernelSize)
        let center = finalKernelSize / 2
        let radius = Double(center)
        
        // Make kernel circular by setting edge pixels to 0
        for y in 0..<finalKernelSize {
            for x in 0..<finalKernelSize {
                let dx = Double(x - center)
                let dy = Double(y - center)
                let distance = sqrt(dx * dx + dy * dy)
                if distance > radius {
                    kernel[y * finalKernelSize + x] = 0
                }
            }
        }

        _ = kernel.withUnsafeBufferPointer { ptr in
            vImageDilate_Planar8(&srcBuffer, &dstBuffer, 0, 0, ptr.baseAddress!, UInt(finalKernelSize), UInt(finalKernelSize), vImage_Flags(kvImageEdgeExtend))
        }

        // Create CGImage from dstBuffer
        guard let outCG = vImageCreateCGImageFromBuffer(&dstBuffer, &format, nil, nil, vImage_Flags(kvImageNoAllocate), &error)?.takeRetainedValue(),
              error == kvImageNoError else {
            free(dstBuffer.data)
            return nil
        }

        // Clean up src (dst already handed off / not allocated)
        free(srcBuffer.data)

        return NSImage(cgImage: outCG, size: mask.size)
    }
    
    private func blendImages(original: NSImage, inpainted: NSImage, mask: NSImage) -> NSImage? {
        let size = original.size
        
        // Get the actual pixel dimensions from the original image
        guard let originalCG = original.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let pixelWidth = originalCG.width
        let pixelHeight = originalCG.height
        
        print("🔍 Blend context: size=\(size), pixels=\(pixelWidth)x\(pixelHeight)")
        
        // Create output image context using actual pixel dimensions
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil,
                                    width: pixelWidth,
                                    height: pixelHeight,
                                    bitsPerComponent: 8,
                                    bytesPerRow: 0,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        
        // Get CGImages
        guard let inpaintedCG = inpainted.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let maskCG = mask.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        // Use pixel dimensions for drawing rectangles
        let pixelRect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        
        // Draw original image as base
        context.draw(originalCG, in: pixelRect)
        
        // Create mask for inpainted areas
        context.saveGState()
        context.clip(to: pixelRect, mask: maskCG)
        
        // Draw inpainted image only in masked areas
        context.draw(inpaintedCG, in: pixelRect)
        context.restoreGState()
        
        guard let outputCGImage = context.makeImage() else {
            return nil
        }
        
        return NSImage(cgImage: outputCGImage, size: size)
    }
    
    private func applyBrushModifications(to newBaseMask: NSImage, from modifiedMask: NSImage) -> NSImage? {
        guard let originalMask = state.originalDustMask else {
            // If no original mask, return the new base mask
            return newBaseMask
        }
        
        // Get CGImages for all three masks
        guard let newBaseCG = newBaseMask.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let modifiedCG = modifiedMask.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let originalCG = originalMask.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return newBaseMask
        }
        
        let width = newBaseCG.width
        let height = newBaseCG.height
        
        // Create contexts for all images
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width
        
        guard let newContext = CGContext(data: nil, width: width, height: height,
                                       bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                       space: colorSpace,
                                       bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let modifiedContext = CGContext(data: nil, width: width, height: height,
                                            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                            space: colorSpace,
                                            bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let originalContext = CGContext(data: nil, width: width, height: height,
                                            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                            space: colorSpace,
                                            bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return newBaseMask
        }
        
        // Draw images to contexts
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        newContext.draw(newBaseCG, in: rect)
        modifiedContext.draw(modifiedCG, in: rect)
        originalContext.draw(originalCG, in: rect)
        
        // Get data pointers
        guard let newData = newContext.data,
              let modifiedData = modifiedContext.data,
              let originalData = originalContext.data else {
            return newBaseMask
        }
        
        let newBuffer = newData.bindMemory(to: UInt8.self, capacity: width * height)
        let modifiedBuffer = modifiedData.bindMemory(to: UInt8.self, capacity: width * height)
        let originalBuffer = originalData.bindMemory(to: UInt8.self, capacity: width * height)
        
        // Apply brush modifications: wherever the modified mask differs from original,
        // apply that difference to the new base mask
        for i in 0..<(width * height) {
            let originalPixel = originalBuffer[i]
            let modifiedPixel = modifiedBuffer[i]
            
            // If the pixel was erased (modified is black but original was white)
            if originalPixel > 127 && modifiedPixel < 128 {
                newBuffer[i] = 0 // Erase from new mask too
            }
            // Keep the new base mask value otherwise
        }
        
        // Create new CGImage from modified buffer
        guard let resultCGImage = newContext.makeImage() else {
            return newBaseMask
        }
        
        return NSImage(cgImage: resultCGImage, size: newBaseMask.size)
    }
    
    private func eraseDustAtPoint(_ point: CGPoint, in canvasSize: CGSize) {
        print("🖱️ Eraser tool activated at point: \(point)")
        
        guard let lowResMask = state.getLowResMask(),
              let selectedImage = state.selectedImage else {
            print("❌ Missing dust mask or selected image")
            return
        }
        
        // Start brush stroke (saves mask state only once per drag)
        state.startBrushStroke()
        
        // Get actual image and LOW-RES mask dimensions for performance
        let imageSize = selectedImage.size
        guard let cgImage = lowResMask.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("❌ Failed to get CGImage from low-res mask")
            return
        }
        
        let maskPixelWidth = cgImage.width
        let maskPixelHeight = cgImage.height
        
        guard maskPixelWidth > 0 && maskPixelHeight > 0 else {
            print("❌ Invalid low-res mask pixel dimensions: \(maskPixelWidth)x\(maskPixelHeight)")
            return
        }
        
        print("🔍 Image size: \(imageSize), Low-res mask pixels: \(maskPixelWidth)x\(maskPixelHeight), Canvas: \(canvasSize)")
        
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
        
        // Convert to LOW-RES mask pixel coordinates
        let maskX = zoomedX * CGFloat(maskPixelWidth)
        let maskY = zoomedY * CGFloat(maskPixelHeight)
        
        let maskPoint = CGPoint(x: maskX, y: maskY)
        
        print("📍 Canvas: \(point) → Image relative: (\(relativeX), \(relativeY)) → Zoomed: (\(zoomedX), \(zoomedY)) → Low-res mask: \(maskPoint)")
        
        // Bounds check using low-res pixel dimensions
        guard maskX >= 0 && maskX < CGFloat(maskPixelWidth) &&
              maskY >= 0 && maskY < CGFloat(maskPixelHeight) else {
            print("❌ Point out of low-res mask bounds: \(maskPoint) for pixel size \(maskPixelWidth)x\(maskPixelHeight)")
            return
        }
        
        // Compute scale to convert screen radius to LOW-RES mask pixel radius
        let scaleFactor = CGFloat(maskPixelWidth) / displayedImageRect.width
        let pixelRadius = max(1, Int(CGFloat(state.brushSize) * scaleFactor))

        // Use interpolated stroke for smooth drawing on LOW-RES mask
        if let updatedLowResMask = applyInterpolatedStroke(mask: lowResMask, at: maskPoint, pixelRadius: pixelRadius, isErasing: true) {
            // Update the low-res mask and provide immediate visual feedback
            state.updateLowResMask(updatedLowResMask)
        }
    }
    
    private func addDustAtPoint(_ point: CGPoint, in canvasSize: CGSize) {
        print("🖱️ Brush tool activated at point: \(point)")
        
        guard let lowResMask = state.getLowResMask(),
              let selectedImage = state.selectedImage else {
            print("❌ Missing dust mask or selected image")
            return
        }
        
        // Start brush stroke (saves mask state only once per drag)
        state.startBrushStroke()
        
        // Get actual image and LOW-RES mask dimensions for performance
        let imageSize = selectedImage.size
        guard let cgImage = lowResMask.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("❌ Failed to get CGImage from low-res mask")
            return
        }
        
        let maskPixelWidth = cgImage.width
        let maskPixelHeight = cgImage.height
        
        guard maskPixelWidth > 0 && maskPixelHeight > 0 else {
            print("❌ Invalid low-res mask pixel dimensions: \(maskPixelWidth)x\(maskPixelHeight)")
            return
        }
        
        print("🔍 Image size: \(imageSize), Low-res mask pixels: \(maskPixelWidth)x\(maskPixelHeight), Canvas: \(canvasSize)")
        
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
        
        // Convert to LOW-RES mask pixel coordinates
        let maskX = zoomedX * CGFloat(maskPixelWidth)
        let maskY = zoomedY * CGFloat(maskPixelHeight)
        
        let maskPoint = CGPoint(x: maskX, y: maskY)
        
        print("📍 Canvas: \(point) → Image relative: (\(relativeX), \(relativeY)) → Zoomed: (\(zoomedX), \(zoomedY)) → Low-res mask: \(maskPoint)")
        
        // Bounds check using low-res pixel dimensions
        guard maskX >= 0 && maskX < CGFloat(maskPixelWidth) &&
              maskY >= 0 && maskY < CGFloat(maskPixelHeight) else {
            print("❌ Point out of low-res mask bounds: \(maskPoint) for pixel size \(maskPixelWidth)x\(maskPixelHeight)")
            return
        }
        
        // Compute scale to convert screen radius to LOW-RES mask pixel radius
        let scaleFactor = CGFloat(maskPixelWidth) / displayedImageRect.width
        let pixelRadius = max(1, Int(CGFloat(state.brushSize) * scaleFactor))

        // Use interpolated stroke for smooth drawing on LOW-RES mask
        if let updatedLowResMask = applyInterpolatedStroke(mask: lowResMask, at: maskPoint, pixelRadius: pixelRadius, isErasing: false) {
            // Update the low-res mask and provide immediate visual feedback
            state.updateLowResMask(updatedLowResMask)
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
    
    private func circularBrushErase(mask: NSImage, at point: CGPoint, pixelRadius: Int) -> NSImage? {
        let brushRadius = pixelRadius
        print("🖌️ Brush erase at \(point) with radius \(brushRadius)")
        
        guard let cgImage = mask.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("❌ Failed to get CGImage")
            return nil
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Safety check for valid dimensions
        guard width > 0 && height > 0 else {
            return mask
        }
        
        // Check if point is within bounds
        let centerX = Int(point.x.rounded())
        let centerY = Int(point.y.rounded())
        
        guard centerX >= 0 && centerX < width && centerY >= 0 && centerY < height else {
            return mask
        }
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width
        let dataSize = width * height
        
        guard let context = CGContext(data: nil, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else { 
            return nil 
        }
        
        let buffer = data.bindMemory(to: UInt8.self, capacity: dataSize)
        
        // Create a copy of the buffer data for modification
        guard let mutableData = NSMutableData(length: dataSize) else {
            return nil
        }
        
        mutableData.replaceBytes(in: NSRange(location: 0, length: dataSize), withBytes: buffer)
        let mutableBuffer = mutableData.mutableBytes.bindMemory(to: UInt8.self, capacity: dataSize)
        
        var pixelsChanged = 0
        let radiusSquared = brushRadius * brushRadius
        
        // Apply circular brush - erase all pixels within the brush radius
        for y in max(0, centerY - brushRadius)...min(height - 1, centerY + brushRadius) {
            for x in max(0, centerX - brushRadius)...min(width - 1, centerX + brushRadius) {
                // Calculate distance from center
                let dx = x - centerX
                let dy = y - centerY
                let distanceSquared = dx * dx + dy * dy
                
                // Only erase if within circular brush
                if distanceSquared <= radiusSquared {
                    let index = y * width + x
                    if index >= 0 && index < dataSize && mutableBuffer[index] > 0 {
                        mutableBuffer[index] = 0 // Set pixel to background (no dust)
                        pixelsChanged += 1
                    }
                }
            }
        }
        
        // Only create new image if we actually changed something
        guard pixelsChanged > 0 else {
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
            return nil
        }
        
        return NSImage(cgImage: newCGImage, size: mask.size)
    }
    
    private func circularBrushAdd(mask: NSImage, at point: CGPoint, pixelRadius: Int) -> NSImage? {
        let brushRadius = pixelRadius
        print("🖌️ Brush add at \(point) with radius \(brushRadius)")
        
        guard let cgImage = mask.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("❌ Failed to get CGImage")
            return nil
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Safety check for valid dimensions
        guard width > 0 && height > 0 else {
            return mask
        }
        
        // Check if point is within bounds
        let centerX = Int(point.x.rounded())
        let centerY = Int(point.y.rounded())
        
        guard centerX >= 0 && centerX < width && centerY >= 0 && centerY < height else {
            return mask
        }
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width
        let dataSize = width * height
        
        guard let context = CGContext(data: nil, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else { 
            return nil 
        }
        
        let buffer = data.bindMemory(to: UInt8.self, capacity: dataSize)
        
        // Create a copy of the buffer data for modification
        guard let mutableData = NSMutableData(length: dataSize) else {
            return nil
        }
        
        mutableData.replaceBytes(in: NSRange(location: 0, length: dataSize), withBytes: buffer)
        let mutableBuffer = mutableData.mutableBytes.bindMemory(to: UInt8.self, capacity: dataSize)
        
        var pixelsChanged = 0
        let radiusSquared = brushRadius * brushRadius
        
        // Apply circular brush - add dust to all pixels within the brush radius
        for y in max(0, centerY - brushRadius)...min(height - 1, centerY + brushRadius) {
            for x in max(0, centerX - brushRadius)...min(width - 1, centerX + brushRadius) {
                // Calculate distance from center
                let dx = x - centerX
                let dy = y - centerY
                let distanceSquared = dx * dx + dy * dy
                
                // Only add dust if within circular brush
                if distanceSquared <= radiusSquared {
                    let index = y * width + x
                    if index >= 0 && index < dataSize && mutableBuffer[index] < 255 {
                        mutableBuffer[index] = 255 // Set pixel to dust (white)
                        pixelsChanged += 1
                    }
                }
            }
        }
        
        // Only create new image if we actually changed something
        guard pixelsChanged > 0 else {
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
            return nil
        }
        
        return NSImage(cgImage: newCGImage, size: mask.size)
    }
    
    private func applyInterpolatedStroke(mask: NSImage, at currentPoint: CGPoint, pixelRadius: Int, isErasing: Bool) -> NSImage? {
        let lastPoint: CGPoint?
        
        // Get the appropriate last point based on tool type
        if isErasing {
            lastPoint = state.lastEraserPoint
            state.lastEraserPoint = currentPoint
        } else {
            lastPoint = state.lastBrushPoint  
            state.lastBrushPoint = currentPoint
        }
        
        // If this is the first point of the stroke, just draw a single circle
        guard let previousPoint = lastPoint else {
            if isErasing {
                return circularBrushErase(mask: mask, at: currentPoint, pixelRadius: pixelRadius)
            } else {
                return circularBrushAdd(mask: mask, at: currentPoint, pixelRadius: pixelRadius)
            }
        }
        
        // Calculate distance between points
        let dx = currentPoint.x - previousPoint.x
        let dy = currentPoint.y - previousPoint.y
        let distance = sqrt(dx * dx + dy * dy)
        
        // If points are very close, just draw at current point
        if distance < 1.0 {
            if isErasing {
                return circularBrushErase(mask: mask, at: currentPoint, pixelRadius: pixelRadius)
            } else {
                return circularBrushAdd(mask: mask, at: currentPoint, pixelRadius: pixelRadius)
            }
        }
        
        // Interpolate points along the line
        let spacing = max(1.0, CGFloat(pixelRadius) * 0.25) // Spacing based on brush size
        let steps = Int(ceil(distance / spacing))
        
        var workingMask = mask
        
        // Draw circles along the interpolated line
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let interpolatedPoint = CGPoint(
                x: previousPoint.x + t * dx,
                y: previousPoint.y + t * dy
            )
            
            if isErasing {
                if let updatedMask = circularBrushErase(mask: workingMask, at: interpolatedPoint, pixelRadius: pixelRadius) {
                    workingMask = updatedMask
                }
            } else {
                if let updatedMask = circularBrushAdd(mask: workingMask, at: interpolatedPoint, pixelRadius: pixelRadius) {
                    workingMask = updatedMask
                }
            }
        }
        
        return workingMask
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
                
                let cfg = MLModelConfiguration()
                cfg.computeUnits = .all
                let model = try MLModel(contentsOf: dustURL, configuration: cfg)
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
                
                let lamaModel = try MLModel(contentsOf: lamaURL, configuration: cfg)
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
