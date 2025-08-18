//
//  DustRemovalState.swift
//  dust_remover
//
//  Shared state management for dust removal workflow
//

import SwiftUI
import CoreML

@MainActor
class DustRemovalState: ObservableObject {
    // MARK: - Images
    @Published var selectedImage: NSImage?
    @Published var processedImage: NSImage?
    @Published var dustMask: NSImage?
    @Published var originalDustMask: NSImage? // Stores the original AI-detected mask before brush modifications
    
    // MARK: - ML Models
    @Published var unetModel: MLModel?
    @Published var lamaModel: MLModel?
    
    // MARK: - Processing State
    @Published var rawPredictionMask: MLMultiArray?
    @Published var isDetecting = false
    @Published var isRemoving = false
    @Published var threshold: Float = 0.05
    @Published var processingTime: Double = 0
    
    // MARK: - UI State
    @Published var showingOriginal = false
    @Published var hideDetections = false
    @Published var zoomScale: CGFloat = 1.0
    @Published var zoomAnchor: UnitPoint = .center
    @Published var dragOffset: CGSize = .zero
    @Published var eraserToolActive = false
    @Published var brushToolActive = false
    @Published var spaceKeyPressed = false
    @Published var overlayOpacity: Double = 0.6
    @Published var brushSize: Int = 15
    @Published var isErasing = false
    @Published var isBrushing = false
    
    // MARK: - Stroke Tracking for Smooth Drawing
    var lastBrushPoint: CGPoint?
    var lastEraserPoint: CGPoint?
    
    // MARK: - Low-Resolution Drawing for Performance
    private var lowResMask: NSImage?
    private var lowResScale: CGFloat = 0.25 // 25% of original resolution
    private let maxDrawingResolution: CGFloat = 1024 // Cap drawing resolution for performance
    
    // MARK: - Undo System
    private var maskHistory: [NSImage] = []
    private let maxHistorySize = 20
    private var isDragging = false
    
    // MARK: - Error Handling
    @Published var errorMessage: String?
    @Published var showingError = false
    
    // MARK: - Computed Properties
    var canDetectDust: Bool {
        selectedImage != nil && unetModel != nil && !isDetecting && !isRemoving
    }
    
    var canRemoveDust: Bool {
        dustMask != nil && lamaModel != nil && !isDetecting && !isRemoving
    }
    
    var isInDetectionMode: Bool {
        dustMask != nil && processedImage == nil
    }
    
    var canUndo: Bool {
        !maskHistory.isEmpty
    }
    
    // MARK: - Actions
    func resetProcessing() {
        processedImage = nil
        dustMask = nil
        originalDustMask = nil
        rawPredictionMask = nil
        hideDetections = false
        resetZoom()
        clearMaskHistory()
    }
    
    func resetZoom() {
        withAnimation(.easeInOut(duration: 0.3)) {
            zoomScale = 1.0
            dragOffset = .zero
            zoomAnchor = .center
        }
        updateCursorForZoom()
    }
    
    func zoomIn() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = min(zoomScale * 1.5, 5.0)
        }
        updateCursorForZoom()
    }
    
    func zoomOut() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = max(zoomScale / 1.5, 1.0)
            if zoomScale == 1.0 {
                dragOffset = .zero
            }
        }
        updateCursorForZoom()
    }
    
    func updateCursorForZoom() {
        // Update cursor when zoom changes
        if eraserToolActive || brushToolActive {
            DispatchQueue.main.async {
                self.createCircularCursor(size: self.brushSize).set()
            }
        }
    }
    
    func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
    
    func createCircularCursor(size: Int) -> NSCursor {
        // Scale cursor size with zoom level so it appears consistent
        let scaledSize = max(16, Int(CGFloat(size * 2) * zoomScale))
        let cursorSize = min(scaledSize, 200) // Cap at reasonable size
        let image = NSImage(size: NSSize(width: cursorSize, height: cursorSize))
        
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: cursorSize, height: cursorSize).fill()
        
        // Draw circle outline
        let circleRect = NSRect(x: 2, y: 2, width: cursorSize - 4, height: cursorSize - 4)
        let path = NSBezierPath(ovalIn: circleRect)
        path.lineWidth = max(1.0, zoomScale * 0.5) // Scale line width slightly
        NSColor.black.setStroke()
        path.stroke()
        
        // Draw inner white circle for contrast
        let innerPath = NSBezierPath(ovalIn: circleRect.insetBy(dx: 1, dy: 1))
        innerPath.lineWidth = max(1.0, zoomScale * 0.5)
        NSColor.white.setStroke()
        innerPath.stroke()
        
        image.unlockFocus()
        
        let hotSpot = NSPoint(x: cursorSize / 2, y: cursorSize / 2)
        return NSCursor(image: image, hotSpot: hotSpot)
    }
    
    // MARK: - Undo System
    func saveMaskToHistory() {
        guard let dustMask = dustMask else { return }
        
        // Add current mask to history
        maskHistory.append(dustMask)
        
        // Limit history size
        if maskHistory.count > maxHistorySize {
            maskHistory.removeFirst()
        }
    }
    
    func startBrushStroke() {
        if !isDragging {
            // Save mask state only at the beginning of a drag gesture
            saveMaskToHistory()
            isDragging = true
        }
    }
    
    func endBrushStroke() {
        isDragging = false
        isErasing = false
        isBrushing = false
        lastBrushPoint = nil
        lastEraserPoint = nil
        
        // Sync low-res changes back to full resolution when stroke ends
        syncLowResToFullRes()
    }
    
    func undoLastMaskChange() {
        guard !maskHistory.isEmpty else { return }
        
        // Restore previous mask
        dustMask = maskHistory.removeLast()
        
        // Recreate low-res mask from restored full-res mask
        createLowResMask()
    }
    
    func clearMaskHistory() {
        maskHistory.removeAll()
        isDragging = false
    }
    
    // MARK: - Low-Resolution Drawing Methods
    
    func createLowResMask() {
        guard let fullResMask = dustMask else {
            lowResMask = nil
            return
        }
        
        let originalSize = fullResMask.size
        
        // Calculate optimal low-res size
        let maxDimension = max(originalSize.width, originalSize.height)
        let targetScale = min(lowResScale, maxDrawingResolution / maxDimension)
        
        let lowResSize = CGSize(
            width: originalSize.width * targetScale,
            height: originalSize.height * targetScale
        )
        
        lowResMask = fullResMask.resized(to: lowResSize)
        print("🎨 Created low-res mask: \(lowResSize) (scale: \(targetScale))")
    }
    
    func getLowResMask() -> NSImage? {
        if lowResMask == nil {
            createLowResMask()
        }
        return lowResMask
    }
    
    func updateLowResMask(_ newLowResMask: NSImage) {
        lowResMask = newLowResMask
        
        // Update the display mask immediately with upscaled version for visual feedback
        if let fullResMask = dustMask {
            let upscaledMask = newLowResMask.resized(to: fullResMask.size)
            dustMask = upscaledMask
        }
    }
    
    private func syncLowResToFullRes() {
        guard let lowRes = lowResMask,
              let fullRes = dustMask else { return }
        
        // Upscale the low-res mask to full resolution
        let finalMask = lowRes.resized(to: fullRes.size)
        dustMask = finalMask
        
        print("🔄 Synced low-res drawing to full resolution")
    }
}