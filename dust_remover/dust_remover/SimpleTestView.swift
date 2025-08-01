//
//  SimpleTestView.swift
//  dust_remover
//
//  Simple test version without Core ML dependencies
//

import SwiftUI
import PhotosUI

struct SimpleTestView: View {
    @State private var selectedImage: NSImage?
    @State private var processedImage: NSImage?
    @State private var isLoading = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var threshold: Float = 0.005
    @State private var processingTime: Double = 0
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // Header
                    VStack {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                        
                        Text("Film Dust Removal")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Remove dust from scanned film photos using AI")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    
                    // Threshold Control
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Detection Threshold")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.3f", threshold))
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(value: $threshold, in: 0.001...0.05, step: 0.001)
                            .accentColor(.blue)
                        
                        HStack {
                            Text("More Sensitive")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Less Sensitive")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Image Selection Button
                    PhotosPicker(selection: $selectedPhotoItem,
                               matching: .images,
                               photoLibrary: .shared()) {
                        Label("Select from Photo Library", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // Images Display
                    if let selectedImage = selectedImage {
                        VStack(spacing: 16) {
                            // Original Image
                            VStack {
                                Text("Original Image")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Image(nsImage: selectedImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 300)
                                    .cornerRadius(12)
                                    .shadow(radius: 4)
                            }
                            
                            // Process Button (Mock processing)
                            Button(action: mockProcessImage) {
                                HStack {
                                    if isLoading {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "wand.and.rays")
                                    }
                                    Text(isLoading ? "Processing..." : "Remove Dust (Mock)")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(isLoading ? Color.gray : Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .disabled(isLoading)
                            
                            // Processed Image
                            if let processedImage = processedImage {
                                VStack {
                                    HStack {
                                        Text("Dust Removed (Mock)")
                                            .font(.headline)
                                        
                                        Spacer()
                                        
                                        if processingTime > 0 {
                                            Text(String(format: "%.2f", processingTime) + "s")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Image(nsImage: processedImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxHeight: 300)
                                        .cornerRadius(12)
                                        .shadow(radius: 4)
                                }
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        // Placeholder
                        VStack {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            
                            Text("Select an image to get started")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 20)
                }
            }
            .navigationTitle("Dust Remover Test")
            // navigationBarTitleDisplayMode not available on macOS
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = NSImage(data: data) {
                    selectedImage = image
                    processedImage = nil
                }
            }
        }
    }
    
    // Mock processing function for testing UI
    private func mockProcessImage() {
        guard let selectedImage = selectedImage else { return }
        
        isLoading = true
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Simulate processing time
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // Just return a slightly modified version for testing
            self.processedImage = selectedImage.applySimpleFilter()
            self.processingTime = CFAbsoluteTimeGetCurrent() - startTime
            self.isLoading = false
        }
    }
}

extension NSImage {
    func applySimpleFilter() -> NSImage {
        // Simple mock filter - just adjust brightness slightly
        let context = CIContext()
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }
        let ciImage = CIImage(cgImage: cgImage)
        
        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(1.1, forKey: kCIInputBrightnessKey) // Slightly brighter
        
        if let outputImage = filter?.outputImage,
           let newCGImage = context.createCGImage(outputImage, from: outputImage.extent) {
            return NSImage(cgImage: newCGImage, size: self.size)
        }
        
        return self
    }
}

#Preview {
    SimpleTestView()
}