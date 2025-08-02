//
//  SidebarView.swift
//  dust_remover
//
//  Sidebar containing all controls and settings
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var state: DustRemovalState
    let onImportImage: () -> Void
    let onDetectDust: () -> Void
    let onRemoveDust: () -> Void
    let onExportImage: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            
            Form {
                Section {
                    importSection
                }
                
                if state.selectedImage != nil {
                    Section("Processing") {
                        processSection
                    }
                }
                
                if state.rawPredictionMask != nil {
                    Section("Detection Threshold") {
                        sensitivitySection
                    }
                }
                
                if state.processedImage != nil {
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
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles.tv.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.orange)
            
            Text("Dust Remover")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            
            Text("AI-powered film restoration")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: Rectangle())
    }
    
    // MARK: - Import Section
    
    private var importSection: some View {
        VStack(spacing: 12) {
            Button(action: onImportImage) {
                Label("Choose File", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            
            Text("Select a scanned film photo to restore")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Process Section
    
    private var processSection: some View {
        VStack(spacing: 12) {
            if let selectedImage = state.selectedImage {
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
                Button(action: onDetectDust) {
                    HStack {
                        if state.isDetecting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text(state.isDetecting ? "Detecting..." : "Detect Dust")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!state.canDetectDust)
                
                // Remove Dust Button
                Button(action: onRemoveDust) {
                    HStack {
                        if state.isRemoving {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                        Text(state.isRemoving ? "Removing..." : "Remove Dust")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!state.canRemoveDust)
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Sensitivity Section
    
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
                    Text(String(format: "%.3f", state.threshold))
                        .font(.monospaced(.callout)())
                        .foregroundStyle(.primary)
                        .fontWeight(.medium)
                    Spacer()
                    Text("Less Sensitive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Slider(value: $state.threshold, in: 0.001...0.1, step: 0.001)
                
                if state.rawPredictionMask != nil {
                    Text("Adjust the slider to fine-tune dust detection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Export Section
    
    private var exportSection: some View {
        VStack(spacing: 12) {
            if state.processingTime > 0 {
                HStack {
                    Text("Processing Time:")
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2f", state.processingTime) + "s")
                        .font(.monospaced(.caption)())
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
            
            Button(action: onExportImage) {
                Label("Export Result", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.vertical, 8)
    }
}