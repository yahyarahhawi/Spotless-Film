//
//  ProfessionalToolbar.swift
//  dust_remover
//
//  Unified toolbar following macOS design patterns
//

import SwiftUI

struct ProfessionalToolbar: View {
    @ObservedObject var state: DustRemovalState
    @Binding var compareMode: ProfessionalContentView.CompareMode
    @Binding var showingInspector: Bool
    let onImportImage: () -> Void
    let onDetectDust: () -> Void
    let onRemoveDust: () -> Void
    let onExportImage: () -> Void
    let onThresholdChanged: () -> Void
    
    private func toggleCompareMode() {
        guard state.processedImage != nil || state.dustMask != nil else { return }
        
        let allCases = ProfessionalContentView.CompareMode.allCases
        let currentIndex = allCases.firstIndex(of: compareMode) ?? 0
        let nextIndex = (currentIndex + 1) % allCases.count
        compareMode = allCases[nextIndex]
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Tools Section
            HStack(spacing: 12) {
                // Eraser Tool
                Button(action: { state.eraserToolActive.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "eraser.fill")
                            .foregroundStyle(state.eraserToolActive ? .orange : .primary)
                        Text("Eraser")
                    }
                }
                .buttonStyle(.bordered)
                .background(state.eraserToolActive ? .orange.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .disabled(state.dustMask == nil)
                .help("Click and erase dust with circular brush")

                // Brush Size Slider (visible only when eraser tool is active)
                if state.eraserToolActive {
                    HStack(spacing: 6) {
                        Image(systemName: "circlebadge")
                            .foregroundStyle(.secondary)
                        Slider(value: Binding(
                            get: { Double(state.brushSize) },
                            set: { state.brushSize = Int($0) }
                        ), in: 5...100, step: 1)
                            .frame(width: 120)
                            .help("Brush radius")
                        Text("\(state.brushSize)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 28)
                    }
                    .transition(.opacity.combined(with: .slide))
                }
            }
            
            Divider()
                .frame(height: 20)
            
            // View Controls Section
            HStack(spacing: 8) {
                // Compare Mode Toggle - Simple icon only
                Button(action: { toggleCompareMode() }) {
                    Image(systemName: compareMode.icon)
                }
                .buttonStyle(.bordered)
                .disabled(state.selectedImage == nil)
                .help(compareMode.label)
            }
            
            Divider()
                .frame(height: 20)
            
            // Overlay Controls Section
            HStack(spacing: 8) {
                // Overlay Toggle
                Button(action: { state.hideDetections.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: state.hideDetections ? "eye.slash" : "eye")
                            .foregroundStyle(state.hideDetections ? Color.secondary : Color.orange)
                        Text("Overlay")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(state.dustMask == nil)
                .help("Toggle Dust Overlay (M)")
                
                // Overlay Opacity Slider (when mask exists and overlay is visible)
                if state.dustMask != nil && !state.hideDetections {
                    HStack(spacing: 8) {
                        Text("Opacity")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                        
                        Slider(value: $state.overlayOpacity, in: 0.1...1.0, step: 0.1)
                            .frame(width: 100)
                            .tint(Color.red.opacity(0.7))
                        
                        Text(String(format: "%.0f%%", state.overlayOpacity * 100))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.secondary)
                            .frame(minWidth: 30)
                    }
                }
            }
            
            Spacer()
            
            // Processing time indicator
            if state.processingTime > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .foregroundStyle(Color.secondary)
                    Text("\(String(format: "%.2f", state.processingTime))s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.secondary)
                }
            }
            
            Divider()
                .frame(height: 20)
            
            // Actions Section
            HStack(spacing: 8) {
                // Export
                Button(action: onExportImage) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(state.processedImage == nil)
                .help("Export Image")
                
                // Inspector Toggle
                Button(action: { showingInspector.toggle() }) {
                    Image(systemName: "sidebar.right")
                        .foregroundStyle(showingInspector ? Color.blue : Color.primary)
                }
                .buttonStyle(.bordered)
                .help("Toggle Inspector")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Rectangle())
        .overlay(alignment: .bottom) {
            Divider()
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true) // Prevent compression
    }
}

#Preview {
    @Previewable @State var compareMode = ProfessionalContentView.CompareMode.single
    @Previewable @State var showingInspector = false
    
    return ProfessionalToolbar(
        state: DustRemovalState(),
        compareMode: $compareMode,
        showingInspector: $showingInspector,
        onImportImage: {},
        onDetectDust: {},
        onRemoveDust: {},
        onExportImage: {},
        onThresholdChanged: {}
    )
}