//
//  ImageDisplayView.swift
//  dust_remover
//
//  Main image display area with zoom controls and dust overlay
//

import SwiftUI

struct ImageDisplayView: View {
    @ObservedObject var state: DustRemovalState
    let onDrop: ([NSItemProvider]) -> Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                headerLabel
                Spacer()
                
                // Zoom controls and instruction text
                if state.selectedImage != nil || state.processedImage != nil {
                    HStack(spacing: 12) {
                        zoomControls
                        instructionText
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
                    
                    if state.selectedImage == nil && state.processedImage == nil {
                        dropZone
                    } else {
                        imageWithOverlay(geometry: geometry)
                    }
                }
            }
            .onDrop(of: [.image], isTargeted: nil) { providers in
                onDrop(providers)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Header Label
    
    @ViewBuilder
    private var headerLabel: some View {
        if state.hideDetections && state.dustMask != nil {
            Label("Original Image (Hold to Hide Detections)", systemImage: "photo")
                .foregroundStyle(.blue)
                .font(.title3)
                .fontWeight(.medium)
        } else if state.showingOriginal && state.processedImage != nil {
            Label("Original Image (Hold to Compare)", systemImage: "photo")
                .foregroundStyle(.blue)
                .font(.title3)
                .fontWeight(.medium)
        } else if state.processedImage != nil {
            Label("Dust-Free Result", systemImage: "sparkles.tv.fill")
                .foregroundStyle(.orange)
                .font(.title3)
                .fontWeight(.medium)
        } else if state.dustMask != nil {
            Label("Dust Detection Preview", systemImage: "magnifyingglass.circle.fill")
                .foregroundStyle(.red)
                .font(.title3)
                .fontWeight(.medium)
        } else if state.selectedImage != nil {
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
    }
    
    // MARK: - Zoom Controls
    
    private var zoomControls: some View {
        HStack(spacing: 8) {
            Button(action: { state.zoomOut() }) {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(state.zoomScale <= 1.0)
            
            Text("\(String(format: "%.0f", state.zoomScale * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 32)
            
            Button(action: { state.zoomIn() }) {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(state.zoomScale >= 5.0)
            
            Button(action: { state.resetZoom() }) {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(state.zoomScale == 1.0 && state.dragOffset == .zero)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
    
    // MARK: - Instruction Text
    
    @ViewBuilder
    private var instructionText: some View {
        if state.processedImage != nil && !state.showingOriginal {
            VStack(alignment: .trailing, spacing: 2) {
                Text("Hold to see original")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if state.dustMask != nil && !state.hideDetections && state.processedImage == nil {
            VStack(alignment: .trailing, spacing: 2) {
                Text("Hold to hide detections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Drop Zone
    
    private var dropZone: some View {
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
    }
    
    // MARK: - Image with Overlay
    
    private func imageWithOverlay(geometry: GeometryProxy) -> some View {
        let imageToShow: NSImage? = {
            if state.hideDetections && state.dustMask != nil {
                return state.selectedImage
            } else if state.showingOriginal && state.selectedImage != nil {
                return state.selectedImage
            } else if state.processedImage != nil {
                return state.processedImage
            } else {
                return state.selectedImage
            }
        }()
        
        return Group {
            if let image = imageToShow {
                ZStack {
                    // Base image
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                    
                    // Red dust overlay (only when dust is detected and not hiding detections)
                    if let dustMask = state.dustMask, !state.hideDetections, state.processedImage == nil, !state.showingOriginal {
                        Image(nsImage: dustMask)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                            .blendMode(.multiply)
                            .colorMultiply(.red)
                            .opacity(0.6)
                    }
                }
                .scaleEffect(state.zoomScale, anchor: state.zoomAnchor)
                .offset(state.dragOffset)
                .clipped()
                .onTapGesture(count: 2) {
                    // Double-tap to reset zoom
                    state.resetZoom()
                }
                .onLongPressGesture(minimumDuration: 0.1, maximumDistance: 50) {
                    // Long press ended
                    if state.processedImage != nil {
                        state.showingOriginal = false
                    } else if state.dustMask != nil {
                        state.hideDetections = false
                    }
                } onPressingChanged: { pressing in
                    // Handle press state changes
                    if pressing && state.processedImage != nil && state.selectedImage != nil {
                        // Show original while pressing (existing behavior)
                        state.showingOriginal = true
                        state.hideDetections = false
                    } else if pressing && state.dustMask != nil && state.processedImage == nil {
                        // Hide detections while pressing (new behavior)
                        state.hideDetections = true
                        state.showingOriginal = false
                    } else {
                        // Release: restore normal state
                        state.showingOriginal = false
                        state.hideDetections = false
                    }
                }
                .simultaneousGesture(
                    // Magnification gesture for pinch-to-zoom
                    MagnificationGesture()
                        .onChanged { value in
                            let newScale = max(1.0, min(value, 5.0))
                            state.zoomScale = newScale
                        }
                        .onEnded { value in
                            let finalScale = max(1.0, min(value, 5.0))
                            withAnimation(.easeOut(duration: 0.2)) {
                                state.zoomScale = finalScale
                                if finalScale == 1.0 {
                                    state.dragOffset = .zero
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    // Drag gesture for panning when zoomed
                    DragGesture()
                        .onChanged { value in
                            if state.zoomScale > 1.0 {
                                state.dragOffset = value.translation
                            }
                        }
                        .onEnded { value in
                            if state.zoomScale > 1.0 {
                                withAnimation(.easeOut(duration: 0.1)) {
                                    state.dragOffset = value.translation
                                }
                            }
                        }
                )
                .animation(.easeInOut(duration: 0.2), value: state.showingOriginal)
                .animation(.easeInOut(duration: 0.2), value: state.hideDetections)
            }
        }
    }
}