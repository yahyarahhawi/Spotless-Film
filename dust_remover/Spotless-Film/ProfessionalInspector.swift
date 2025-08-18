//
//  ProfessionalInspector.swift
//  dust_remover
//
//  Right-hand inspector panel with advanced controls and metadata
//

import SwiftUI

struct ProfessionalInspector: View {
    @ObservedObject var state: DustRemovalState
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Inspector")
                        .font(.headline.weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial)
                .overlay(alignment: .bottom) {
                    Divider()
                }
                
                VStack(spacing: 0) {
                    // Image Information
                    if let selectedImage = state.selectedImage {
                        imageInfoSection(selectedImage)
                    }
                    
                    // Detection Analysis
                    if state.rawPredictionMask != nil {
                        detectionAnalysisSection
                    }
                    
                    // Processing History
                    processingHistorySection
                    
                    // Advanced Settings
                    advancedSettingsSection
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(.windowBackground)
    }
    
    // MARK: - Sections
    
    private func imageInfoSection(_ image: NSImage) -> some View {
        DisclosureGroup("Image Information", isExpanded: .constant(true)) {
            VStack(spacing: 12) {
                infoGrid([
                    ("Dimensions", "\(Int(image.size.width)) × \(Int(image.size.height))"),
                    ("Aspect Ratio", String(format: "%.2f:1", image.size.width / image.size.height)),
                    ("Color Space", image.representations.first?.colorSpaceName.rawValue ?? "Unknown"),
                    ("Megapixels", String(format: "%.1f MP", (image.size.width * image.size.height) / 1_000_000))
                ])
                
                if let rep = image.representations.first as? NSBitmapImageRep {
                    infoGrid([
                        ("Bit Depth", "\(rep.bitsPerPixel) bit"),
                        ("Channels", "\(rep.samplesPerPixel)"),
                        ("Alpha", rep.hasAlpha ? "Yes" : "No")
                    ])
                }
            }
            .padding(.vertical, 16)
        }
        .disclosureGroupStyle(ProfessionalDisclosureStyle())
    }
    
    private var detectionAnalysisSection: some View {
        DisclosureGroup("Detection Analysis", isExpanded: .constant(true)) {
            VStack(spacing: 16) {
                // Dust Statistics
                if let stats = calculateDustStats() {
                    VStack(spacing: 8) {
                        Text("Dust Coverage")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack {
                            Text("Pixels:")
                            Spacer()
                            Text("\(stats.dustPixels)")
                                .font(.monospacedDigit(.caption)())
                        }
                        
                        HStack {
                            Text("Coverage:")
                            Spacer()
                            Text(String(format: "%.2f%%", stats.coverage * 100))
                                .font(.monospacedDigit(.caption)())
                        }
                        
                        HStack {
                            Text("Confidence:")
                            Spacer()
                            Text(String(format: "%.1f%%", stats.avgConfidence * 100))
                                .font(.monospacedDigit(.caption)())
                        }
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                }
                
                // Threshold Visualization
                thresholdVisualization
            }
            .padding(.vertical, 16)
        }
        .disclosureGroupStyle(ProfessionalDisclosureStyle())
    }
    
    private var processingHistorySection: some View {
        DisclosureGroup("Processing History", isExpanded: .constant(false)) {
            VStack(spacing: 12) {
                if state.rawPredictionMask != nil {
                    historyItem("Dust Detection", "Completed", systemImage: "magnifyingglass", color: .green)
                }
                
                if state.dustMask != nil {
                    historyItem("Threshold Applied", String(format: "%.3f", state.threshold), systemImage: "slider.horizontal.3", color: .orange)
                }
                
                if state.processedImage != nil {
                    historyItem("Dust Removal", String(format: "%.2fs", state.processingTime), systemImage: "wand.and.stars", color: .blue)
                }
                
                if state.rawPredictionMask == nil && state.dustMask == nil && state.processedImage == nil {
                    Text("No processing history")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            }
            .padding(.vertical, 16)
        }
        .disclosureGroupStyle(ProfessionalDisclosureStyle())
    }
    
    private var advancedSettingsSection: some View {
        DisclosureGroup("Advanced Settings", isExpanded: .constant(true)) {
            VStack(spacing: 16) {
                // Dilation Kernel Size
                VStack(spacing: 8) {
                    HStack {
                        Text("Dilation Kernel")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("3×3")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    
                    Picker("Kernel Size", selection: .constant(3)) {
                        Text("3×3").tag(3)
                        Text("5×5").tag(5)
                        Text("7×7").tag(7)
                    }
                    .pickerStyle(.segmented)
                    .disabled(true) // TODO: Implement kernel size selection
                }
                
                // Model Information
                VStack(spacing: 8) {
                    HStack {
                        Text("AI Models")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                    
                    VStack(spacing: 4) {
                        infoRow("UNet", "1024×1024 detection")
                        infoRow("LaMa", "800×800 inpainting")
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                }
                
                
                // Performance Settings
                VStack(spacing: 8) {
                    HStack {
                        Text("Performance")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                    
                    VStack(spacing: 8) {
                        HStack {
                            Text("GPU Acceleration")
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        
                        HStack {
                            Text("Memory Usage")
                            Spacer()
                            Text("Optimized")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    .padding(8)
                    .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.vertical, 16)
        }
        .disclosureGroupStyle(ProfessionalDisclosureStyle())
    }
    
    // MARK: - Helper Views
    
    private func infoGrid(_ items: [(String, String)]) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                infoRow(item.0, item.1)
            }
        }
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
    
    private func historyItem(_ title: String, _ detail: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private var thresholdVisualization: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Threshold Range")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            
            VStack(spacing: 4) {
                // Visual representation of threshold
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(.green.opacity(0.3))
                        .frame(height: 20)
                        .overlay(alignment: .center) {
                            Text("Clean")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                    
                    Rectangle()
                        .fill(.orange.opacity(0.5))
                        .frame(width: 2, height: 20)
                    
                    Rectangle()
                        .fill(.red.opacity(0.3))
                        .frame(height: 20)
                        .overlay(alignment: .center) {
                            Text("Dust")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                
                HStack {
                    Text("0.000")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    // Current threshold indicator
                    VStack(spacing: 2) {
                        Text(String(format: "%.3f", state.threshold))
                            .font(.caption2.monospacedDigit().weight(.medium))
                        Rectangle()
                            .fill(.orange)
                            .frame(width: 1, height: 8)
                    }
                    
                    Spacer()
                    
                    Text("0.100")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Helper Functions
    
    private func calculateDustStats() -> (dustPixels: Int, coverage: Double, avgConfidence: Double)? {
        guard let rawMask = state.rawPredictionMask else { return nil }
        
        let dataPointer = rawMask.dataPointer.assumingMemoryBound(to: Float.self)
        let totalPixels = rawMask.count
        
        var dustPixels = 0
        var totalConfidence: Double = 0
        
        for i in 0..<totalPixels {
            let value = dataPointer[i]
            if value > state.threshold {
                dustPixels += 1
                totalConfidence += Double(value)
            }
        }
        
        let coverage = Double(dustPixels) / Double(totalPixels)
        let avgConfidence = dustPixels > 0 ? totalConfidence / Double(dustPixels) : 0
        
        return (dustPixels, coverage, avgConfidence)
    }
}

#Preview {
    ProfessionalInspector(state: DustRemovalState())
        .frame(width: 280)
}