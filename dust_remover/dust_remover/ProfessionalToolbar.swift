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
    
    var body: some View {
        HStack(spacing: 16) {
            // Import Section
            Button(action: onImportImage) {
                Label("Import", systemImage: "folder.badge.plus")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.isDetecting || state.isRemoving)
            
            Divider()
                .frame(height: 20)
            
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
                .help("Click dust particles to remove them from the mask")
            }
            
            Divider()
                .frame(height: 20)
            
            // View Controls Section
            HStack(spacing: 8) {
                // Zoom to Fit
                Button(action: { state.resetZoom() }) {
                    Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(state.selectedImage == nil)
                .help("Zoom to Fit")
                
                // Zoom to 100%
                Button(action: { 
                    state.zoomScale = 1.0
                    state.dragOffset = .zero
                }) {
                    Text("1:1")
                        .font(.caption.weight(.medium))
                        .frame(minWidth: 24)
                }
                .buttonStyle(.bordered)
                .disabled(state.selectedImage == nil)
                .help("Actual Size")
                
                // Compare Mode Toggle
                Menu {
                    ForEach(ProfessionalContentView.CompareMode.allCases, id: \.self) { mode in
                        Button(action: { compareMode = mode }) {
                            Label(mode.label, systemImage: mode.icon)
                        }
                    }
                } label: {
                    Image(systemName: compareMode.icon)
                }
                .buttonStyle(.bordered)
                .disabled(state.selectedImage == nil)
                .help("Compare Mode")
            }
            
            Spacer()
            
            // Status Section
            HStack(spacing: 12) {
                // Processing time indicator
                if state.processingTime > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text("\(String(format: "%.2f", state.processingTime))s")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Dust detection status
                if let _ = state.dustMask {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                        Text("Dust Detected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Clean status
                if let _ = state.processedImage {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text("Clean")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                        .foregroundStyle(showingInspector ? .blue : .primary)
                }
                .buttonStyle(.bordered)
                .help("Toggle Inspector")
                
                // More Menu
                Menu {
                    Button("Preferences") {
                        // TODO: Implement preferences
                    }
                    Button("About") {
                        // TODO: Implement about
                    }
                    Divider()
                    Button("Help") {
                        // TODO: Implement help
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.bordered)
                .help("More Options")
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
        onExportImage: {}
    )
}