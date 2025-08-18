//
//  ProfessionalSidebar.swift
//  dust_remover
//
//  Professional sidebar with Library & Actions sections
//

import SwiftUI

struct ProfessionalSidebar: View {
    @ObservedObject var state: DustRemovalState
    let onImportImage: () -> Void
    let onDetectDust: () -> Void
    let onRemoveDust: () -> Void
    let onThresholdChanged: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)
                
                VStack(spacing: 4) {
                    Text("Dust Remover")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    
                    Text("AI-powered film restoration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: Rectangle())
            .overlay(alignment: .bottom) {
                Divider()
            }
            
            // Main Content
            ScrollView {
                VStack(spacing: 0) {
                    // Import Section
                    DisclosureGroup("Import", isExpanded: .constant(true)) {
                        VStack(spacing: 16) {
                            // Drop Zone or File Info
                            if let selectedImage = state.selectedImage {
                                imageInfoSection(selectedImage)
                            } else {
                                dropZoneSection
                            }
                            
                            // Import Button
                            Button(action: onImportImage) {
                                Label("Choose File", systemImage: "folder.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                        .padding(.vertical, 16)
                    }
                    .disclosureGroupStyle(ProfessionalDisclosureStyle())
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // Detection Section
                    DisclosureGroup("Detection", isExpanded: .constant(true)) {
                        VStack(spacing: 16) {
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
                            
                            // Threshold Controls (when available)
                            if state.rawPredictionMask != nil {
                                thresholdSection
                            }
                            
                        }
                        .padding(.vertical, 16)
                    }
                    .disclosureGroupStyle(ProfessionalDisclosureStyle())
                    
                    // Removal Section (when dust is detected)
                    if state.dustMask != nil {
                        Divider()
                            .padding(.vertical, 8)
                        
                        DisclosureGroup("Dust Removal", isExpanded: .constant(true)) {
                            VStack(spacing: 16) {
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
                                
                                if state.processingTime > 0 {
                                    HStack {
                                        Text("Processing Time:")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(String(format: "%.2f", state.processingTime))s")
                                            .font(.monospacedDigit(.caption)())
                                            .foregroundStyle(.primary)
                                    }
                                    .font(.caption)
                                }
                            }
                            .padding(.vertical, 16)
                        }
                        .disclosureGroupStyle(ProfessionalDisclosureStyle())
                    }
                    
                    Spacer()
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(.windowBackground)
    }
    
    // MARK: - Subviews
    
    private var dropZoneSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.quaternary)
            
            VStack(spacing: 4) {
                Text("Drop image here")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                
                Text("or use Choose File")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("PNG, JPEG, TIFF")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }
    
    private func imageInfoSection(_ image: NSImage) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Image Loaded")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            
            VStack(spacing: 4) {
                infoRow("Size", "\(Int(image.size.width)) × \(Int(image.size.height))")
                if let colorSpace = image.representations.first?.colorSpaceName {
                    infoRow("Color Space", colorSpace.rawValue)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label + ":")
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.monospacedDigit(.caption)())
                .foregroundStyle(.primary)
        }
        .font(.caption)
    }
    
    private var thresholdSection: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Sensitivity", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            
            VStack(spacing: 8) {
                HStack {
                    Text("Less Sensitive")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("More Sensitive")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Slider(value: Binding(
                    get: { 0.101 - state.threshold }, // Invert the value: high threshold = left side, low threshold = right side
                    set: { state.threshold = 0.101 - $0 }
                ), in: 0.001...0.1, step: 0.001)
                    .tint(.orange)
                    .onChange(of: state.threshold) { _, _ in
                        onThresholdChanged()
                    }
                
                Text("Adjust to fine-tune dust detection")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }
    
    
}

// MARK: - Custom Disclosure Style

struct ProfessionalDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack {
                    configuration.label
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            if configuration.isExpanded {
                configuration.content
                    .padding(.horizontal, 16)
            }
        }
    }
}

#Preview {
    NavigationSplitView {
        ProfessionalSidebar(
            state: DustRemovalState(),
            onImportImage: {},
            onDetectDust: {},
            onRemoveDust: {},
            onThresholdChanged: {}
        )
    } detail: {
        Text("Canvas")
    }
}