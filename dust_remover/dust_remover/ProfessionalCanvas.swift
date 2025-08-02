//
//  ProfessionalCanvas.swift
//  dust_remover
//
//  Professional canvas with multiple compare modes and advanced zoom controls
//

import SwiftUI

struct ProfessionalCanvas: View {
    @ObservedObject var state: DustRemovalState
    let compareMode: ProfessionalContentView.CompareMode
    @Binding var splitPosition: CGFloat
    let onDrop: ([NSItemProvider]) -> Bool
    let onEraserClick: (CGPoint, CGSize) -> Void
    
    @State private var dragGesture: CGSize = .zero
    @State private var isShowingNavigator = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Rectangle()
                    .fill(.windowBackground)
                
                if state.selectedImage == nil && state.processedImage == nil {
                    dropZoneView
                } else {
                    canvasContent(geometry: geometry)
                }
                
                // Navigator (when zoomed in)
                if state.zoomScale > 1.5 && (state.selectedImage != nil || state.processedImage != nil) {
                    NavigatorView(state: state, canvasSize: geometry.size) { newOffset in
                        dragGesture = newOffset
                    }
                        .frame(width: 120, height: 80)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.quaternary, lineWidth: 1)
                        }
                        .position(x: geometry.size.width - 80, y: 60)
                }
                
                // Processing Overlay
                if state.isDetecting || state.isRemoving {
                    processingOverlay
                }
            }
        }
        .onDrop(of: [.image], isTargeted: nil) { providers in
            onDrop(providers)
        }
        .background(.windowBackground)
    }
    
    // MARK: - Subviews
    
    private var dropZoneView: some View {
        VStack(spacing: 32) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 80, weight: .ultraLight))
                .foregroundStyle(.quaternary)
            
            VStack(spacing: 12) {
                Text("Drag and drop an image here")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
                
                Text("or use the Import button to browse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text("Supported formats: PNG, JPEG, TIFF")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func canvasContent(geometry: GeometryProxy) -> some View {
        Group {
            switch compareMode {
            case .single:
                singleImageView(geometry: geometry)
            case .sideBySide:
                sideBySideView(geometry: geometry)
            case .splitSlider:
                splitSliderView(geometry: geometry)
            }
        }
    }
    
    private func singleImageView(geometry: GeometryProxy) -> some View {
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
                    
                    // Dust overlay (only when appropriate)
                    if let dustMask = state.dustMask,
                       !state.hideDetections,
                       state.processedImage == nil,
                       !state.showingOriginal {
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
                .coordinateSpace(name: "canvas")
                .gesture(getCombinedGestures())
                .onTapGesture(coordinateSpace: .named("canvas")) { location in
                    if state.eraserToolActive && !state.spaceKeyPressed {
                        onEraserClick(location, geometry.size)
                    }
                }
                .onHover { hovering in
                    if hovering {
                        if state.eraserToolActive && state.spaceKeyPressed {
                            NSCursor.openHand.set() // Pan cursor when space is held
                        } else if state.eraserToolActive {
                            NSCursor.crosshair.set() // Eraser cursor
                        } else {
                            NSCursor.arrow.set() // Normal cursor
                        }
                    } else {
                        NSCursor.arrow.set()
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: state.showingOriginal)
                .animation(.easeInOut(duration: 0.2), value: state.hideDetections)
            }
        }
    }
    
    private func sideBySideView(geometry: GeometryProxy) -> some View {
        HStack(spacing: 2) {
            // Original
            if let originalImage = state.selectedImage {
                VStack(spacing: 0) {
                    headerLabel("Original", icon: "photo", color: .blue)
                    
                    ZStack {
                        Image(nsImage: originalImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: geometry.size.width / 2 - 1, maxHeight: geometry.size.height - 40)
                            .scaleEffect(state.zoomScale, anchor: .center)
                            .offset(state.dragOffset)
                            .clipped()
                        
                        // Dust overlay on original
                        if let dustMask = state.dustMask, !state.hideDetections {
                            Image(nsImage: dustMask)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: geometry.size.width / 2 - 1, maxHeight: geometry.size.height - 40)
                                .scaleEffect(state.zoomScale, anchor: .center)
                                .offset(state.dragOffset)
                                .clipped()
                                .blendMode(.multiply)
                                .colorMultiply(.red)
                                .opacity(0.6)
                        }
                    }
                    .coordinateSpace(name: "originalCanvas")
                    .onTapGesture(coordinateSpace: .named("originalCanvas")) { location in
                        if state.eraserToolActive && !state.spaceKeyPressed {
                            // Adjust location for side-by-side layout
                            let adjustedSize = CGSize(width: geometry.size.width / 2 - 1, height: geometry.size.height - 40)
                            onEraserClick(location, adjustedSize)
                        }
                    }
                    .onHover { hovering in
                        if hovering {
                            if state.eraserToolActive && state.spaceKeyPressed {
                                NSCursor.openHand.set() // Pan cursor when space is held
                            } else if state.eraserToolActive {
                                NSCursor.crosshair.set() // Eraser cursor
                            } else {
                                NSCursor.arrow.set() // Normal cursor
                            }
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                }
            }
            
            // Processed
            if let processedImage = state.processedImage {
                VStack(spacing: 0) {
                    headerLabel("Dust-Free", icon: "sparkles.tv.fill", color: .green)
                    
                    Image(nsImage: processedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width / 2 - 1, maxHeight: geometry.size.height - 40)
                        .scaleEffect(state.zoomScale, anchor: .center)
                        .offset(state.dragOffset)
                        .clipped()
                }
            } else if state.selectedImage != nil {
                VStack(spacing: 0) {
                    headerLabel("Dust-Free", icon: "sparkles.tv", color: .secondary)
                    
                    Rectangle()
                        .fill(.quinary)
                        .frame(maxWidth: geometry.size.width / 2 - 1, maxHeight: geometry.size.height - 40)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "wand.and.stars")
                                    .font(.largeTitle)
                                    .foregroundStyle(.quaternary)
                                Text("Run dust removal")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            }
        }
        .gesture(getCombinedGestures())
    }
    
    private func splitSliderView(geometry: GeometryProxy) -> some View {
        ZStack {
            // Base layers
            if let originalImage = state.selectedImage {
                ZStack {
                    Image(nsImage: originalImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                        .scaleEffect(state.zoomScale, anchor: .center)
                        .offset(state.dragOffset)
                        .clipped()
                    
                    // Dust overlay on original side
                    if let dustMask = state.dustMask, !state.hideDetections {
                        Image(nsImage: dustMask)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                            .scaleEffect(state.zoomScale, anchor: .center)
                            .offset(state.dragOffset)
                            .clipped()
                            .blendMode(.multiply)
                            .colorMultiply(.red)
                            .opacity(0.6)
                    }
                }
            }
            
            // Processed overlay (clipped)
            if let processedImage = state.processedImage {
                Image(nsImage: processedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                    .scaleEffect(state.zoomScale, anchor: .center)
                    .offset(state.dragOffset)
                    .clipped()
                    .mask {
                        Rectangle()
                            .frame(width: geometry.size.width * splitPosition)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
            }
            
            // Split line
            Rectangle()
                .fill(.primary)
                .frame(width: 2)
                .overlay {
                    // Drag handle
                    Circle()
                        .fill(.primary)
                        .frame(width: 20, height: 20)
                        .overlay {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.background)
                        }
                }
                .position(x: geometry.size.width * splitPosition, y: geometry.size.height / 2)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newPosition = value.location.x / geometry.size.width
                            splitPosition = max(0, min(1, newPosition))
                        }
                )
            
            // Labels
            VStack {
                HStack {
                    headerLabel("Original", icon: "photo", color: .blue)
                        .opacity(splitPosition > 0.1 ? 1 : 0)
                    
                    Spacer()
                    
                    headerLabel("Dust-Free", icon: "sparkles.tv.fill", color: .green)
                        .opacity(splitPosition < 0.9 ? 1 : 0)
                }
                .padding()
                
                Spacer()
            }
        }
        .gesture(getCombinedGestures())
    }
    
    private func headerLabel(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
    
    private func getCombinedGestures() -> AnyGesture<Void> {
        // Always allow zoom, but restrict pan to space key when eraser is active
        if state.eraserToolActive {
            return AnyGesture(eraserModeGestures.map { _ in () })
        } else {
            return AnyGesture(panZoomGestures.map { _ in () })
        }
    }
    
    private var eraserModeGestures: some Gesture {
        SimultaneousGesture(
            // Always allow magnification in eraser mode
            MagnificationGesture()
                .onChanged { value in
                    let dampedValue = value > 1 ? 1 + (value - 1) * 0.5 : 1 - (1 - value) * 0.5
                    let newScale = max(0.5, min(dampedValue * state.zoomScale, 5.0))
                    state.zoomScale = newScale
                }
                .onEnded { value in
                    let dampedValue = value > 1 ? 1 + (value - 1) * 0.5 : 1 - (1 - value) * 0.5
                    let finalScale = max(0.5, min(dampedValue * state.zoomScale, 5.0))
                    withAnimation(.easeOut(duration: 0.2)) {
                        state.zoomScale = finalScale
                        if finalScale <= 1.0 {
                            state.zoomScale = 1.0
                            state.dragOffset = .zero
                        }
                    }
                },
            
            // Only allow pan when space is pressed in eraser mode
            DragGesture()
                .onChanged { value in
                    if state.spaceKeyPressed && state.zoomScale > 1.0 {
                        let newOffset = CGSize(
                            width: dragGesture.width + value.translation.width,
                            height: dragGesture.height + value.translation.height
                        )
                        state.dragOffset = newOffset
                    }
                }
                .onEnded { value in
                    if state.spaceKeyPressed && state.zoomScale > 1.0 {
                        let finalOffset = CGSize(
                            width: dragGesture.width + value.translation.width,
                            height: dragGesture.height + value.translation.height
                        )
                        dragGesture = finalOffset
                        state.dragOffset = finalOffset
                    } else if !state.spaceKeyPressed {
                        dragGesture = .zero
                        state.dragOffset = .zero
                    }
                }
        )
        .simultaneously(with:
            // Double tap to reset zoom in eraser mode
            TapGesture(count: 2)
                .onEnded {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        state.resetZoom()
                        dragGesture = .zero
                    }
                }
        )
    }
    
    private var panZoomGestures: some Gesture {
        SimultaneousGesture(
            // Long press for original/mask toggle
            LongPressGesture(minimumDuration: 0.1, maximumDistance: 50)
                .onEnded { _ in
                    if state.processedImage != nil {
                        state.showingOriginal = false
                    } else if state.dustMask != nil {
                        state.hideDetections = false
                    }
                }
                .sequenced(before:
                    DragGesture()
                        .onChanged { _ in
                            if state.processedImage != nil && state.selectedImage != nil {
                                state.showingOriginal = true
                                state.hideDetections = false
                            } else if state.dustMask != nil && state.processedImage == nil {
                                state.hideDetections = true
                                state.showingOriginal = false
                            }
                        }
                        .onEnded { _ in
                            state.showingOriginal = false
                            state.hideDetections = false
                        }
                ),
            
            SimultaneousGesture(
                // Magnification gesture with better sensitivity
                MagnificationGesture()
                    .onChanged { value in
                        // Reduce sensitivity by using square root for smoother zooming
                        let dampedValue = value > 1 ? 1 + (value - 1) * 0.5 : 1 - (1 - value) * 0.5
                        let newScale = max(0.5, min(dampedValue * state.zoomScale, 5.0))
                        state.zoomScale = newScale
                    }
                    .onEnded { value in
                        let dampedValue = value > 1 ? 1 + (value - 1) * 0.5 : 1 - (1 - value) * 0.5
                        let finalScale = max(0.5, min(dampedValue * state.zoomScale, 5.0))
                        withAnimation(.easeOut(duration: 0.2)) {
                            state.zoomScale = finalScale
                            if finalScale <= 1.0 {
                                state.zoomScale = 1.0
                                state.dragOffset = .zero
                            }
                        }
                    },
                
                // Drag gesture for panning
                DragGesture()
                    .onChanged { value in
                        if state.zoomScale > 1.0 {
                            let newOffset = CGSize(
                                width: dragGesture.width + value.translation.width,
                                height: dragGesture.height + value.translation.height
                            )
                            state.dragOffset = newOffset
                        }
                    }
                    .onEnded { value in
                        if state.zoomScale > 1.0 {
                            let finalOffset = CGSize(
                                width: dragGesture.width + value.translation.width,
                                height: dragGesture.height + value.translation.height
                            )
                            dragGesture = finalOffset
                            state.dragOffset = finalOffset
                        } else {
                            dragGesture = .zero
                            state.dragOffset = .zero
                        }
                    }
            )
        )
        .simultaneously(with:
            // Double tap to reset zoom
            TapGesture(count: 2)
                .onEnded {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        state.resetZoom()
                        dragGesture = .zero
                    }
                }
        )
    }
    
    private var processingOverlay: some View {
        Rectangle()
            .fill(.background.opacity(0.8))
            .overlay {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    
                    VStack(spacing: 4) {
                        Text(state.isDetecting ? "Detecting dust..." : "Removing dust...")
                            .font(.headline)
                        
                        Text(state.isDetecting ? "Analyzing image for dust particles" : "Applying AI inpainting")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
    }
}

// MARK: - Navigator View

struct NavigatorView: View {
    @ObservedObject var state: DustRemovalState
    let canvasSize: CGSize
    let onPanUpdate: (CGSize) -> Void
    
    private let navigatorSize = CGSize(width: 100, height: 60)
    
    var body: some View {
        VStack(spacing: 4) {
            Text("Navigator")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            
            GeometryReader { navGeometry in
                ZStack {
                    // Thumbnail
                    if let image = state.selectedImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .opacity(0.7)
                    }
                    
                    // Viewport indicator
                    Rectangle()
                        .stroke(.blue, lineWidth: 1)
                        .background(.blue.opacity(0.1))
                        .frame(
                            width: min(navigatorSize.width, navigatorSize.width / state.zoomScale),
                            height: min(navigatorSize.height, navigatorSize.height / state.zoomScale)
                        )
                        .position(viewportPosition(in: navGeometry.size))
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    // Convert tap location to pan offset
                    let normalizedX = (location.x - navGeometry.size.width / 2) / navGeometry.size.width
                    let normalizedY = (location.y - navGeometry.size.height / 2) / navGeometry.size.height
                    
                    // Scale by zoom factor and canvas size
                    let newOffsetX = -normalizedX * canvasSize.width * (state.zoomScale - 1)
                    let newOffsetY = -normalizedY * canvasSize.height * (state.zoomScale - 1)
                    let newOffset = CGSize(width: newOffsetX, height: newOffsetY)
                    
                    withAnimation(.easeInOut(duration: 0.3)) {
                        state.dragOffset = newOffset
                        onPanUpdate(newOffset)
                    }
                }
            }
            .frame(height: 60)
        }
        .padding(8)
    }
    
    private func viewportPosition(in size: CGSize) -> CGPoint {
        // Calculate position based on current drag offset
        let normalizedX = -state.dragOffset.width / (canvasSize.width * (state.zoomScale - 1))
        let normalizedY = -state.dragOffset.height / (canvasSize.height * (state.zoomScale - 1))
        
        let x = size.width / 2 + normalizedX * size.width
        let y = size.height / 2 + normalizedY * size.height
        
        return CGPoint(
            x: min(max(x, 0), size.width),
            y: min(max(y, 0), size.height)
        )
    }
}

#Preview {
    ProfessionalCanvas(
        state: DustRemovalState(),
        compareMode: .single,
        splitPosition: .constant(0.5),
        onDrop: { _ in false },
        onEraserClick: { _, _ in }
    )
}