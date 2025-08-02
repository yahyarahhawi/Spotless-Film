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
    @Published var spaceKeyPressed = false
    @Published var overlayOpacity: Double = 0.6
    @Published var brushSize: Int = 15
    @Published var isErasing = false
    
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
    
    // MARK: - Actions
    func resetProcessing() {
        processedImage = nil
        dustMask = nil
        rawPredictionMask = nil
        hideDetections = false
        resetZoom()
    }
    
    func resetZoom() {
        withAnimation(.easeInOut(duration: 0.3)) {
            zoomScale = 1.0
            dragOffset = .zero
            zoomAnchor = .center
        }
    }
    
    func zoomIn() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = min(zoomScale * 1.5, 5.0)
        }
    }
    
    func zoomOut() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = max(zoomScale / 1.5, 1.0)
            if zoomScale == 1.0 {
                dragOffset = .zero
            }
        }
    }
    
    func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
    
    func createCircularCursor(size: Int) -> NSCursor {
        let diameter = max(16, size * 2)
        let cursorSize = diameter
        let image = NSImage(size: NSSize(width: cursorSize, height: cursorSize))
        
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: cursorSize, height: cursorSize).fill()
        
        // Draw circle outline
        let circleRect = NSRect(x: 2, y: 2, width: cursorSize - 4, height: cursorSize - 4)
        let path = NSBezierPath(ovalIn: circleRect)
        path.lineWidth = 1.0
        NSColor.black.setStroke()
        path.stroke()
        
        // Draw inner white circle for contrast
        let innerPath = NSBezierPath(ovalIn: circleRect.insetBy(dx: 1, dy: 1))
        innerPath.lineWidth = 1.0
        NSColor.white.setStroke()
        innerPath.stroke()
        
        image.unlockFocus()
        
        let hotSpot = NSPoint(x: cursorSize / 2, y: cursorSize / 2)
        return NSCursor(image: image, hotSpot: hotSpot)
    }
}