#!/usr/bin/env python3
"""
Dust Removal GUI Application

A simple drag-and-drop interface for film dust removal using trained U-Net models.
Supports both traditional CV2 inpainting and LaMa deep learning inpainting.

Usage: python dust_removal_app.py
"""

import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from tkinterdnd2 import DND_FILES, TkinterDnD
import numpy as np
import torch
import torch.nn as nn
from PIL import Image, ImageTk
import cv2
import os
from pathlib import Path
from tqdm import tqdm
import threading
import io
import sys

# Import model architecture (copy from notebook)
class UNet(nn.Module):
    def __init__(self):
        super().__init__()

        def conv_block(in_c, out_c):
            return nn.Sequential(
                nn.Conv2d(in_c, out_c, 3, padding=1), nn.ReLU(),
                nn.Conv2d(out_c, out_c, 3, padding=1), nn.ReLU()
            )

        # 1 channel for greyscale
        self.enc1 = conv_block(1, 64)
        self.enc2 = conv_block(64, 128)
        self.enc3 = conv_block(128, 256)
        self.enc4 = conv_block(256, 512)

        self.pool = nn.MaxPool2d(2)

        self.middle = conv_block(512, 1024)

        self.up4 = nn.ConvTranspose2d(1024, 512, 2, stride=2)
        self.dec4 = conv_block(1024, 512)
        self.up3 = nn.ConvTranspose2d(512, 256, 2, stride=2)
        self.dec3 = conv_block(512, 256)
        self.up2 = nn.ConvTranspose2d(256, 128, 2, stride=2)
        self.dec2 = conv_block(256, 128)
        self.up1 = nn.ConvTranspose2d(128, 64, 2, stride=2)
        self.dec1 = conv_block(128, 64)

        self.final = nn.Conv2d(64, 1, 1)

    def forward(self, x):
        e1 = self.enc1(x)
        e2 = self.enc2(self.pool(e1))
        e3 = self.enc3(self.pool(e2))
        e4 = self.enc4(self.pool(e3))

        m = self.middle(self.pool(e4))

        d4 = self.dec4(torch.cat([self.up4(m), e4], dim=1))
        d3 = self.dec3(torch.cat([self.up3(d4), e3], dim=1))
        d2 = self.dec2(torch.cat([self.up2(d3), e2], dim=1))
        d1 = self.dec1(torch.cat([self.up1(d2), e1], dim=1))

        return torch.sigmoid(self.final(d1))

# Try to import LaMa for deep learning inpainting
try:
    from lama_cleaner.model_manager import ModelManager
    from lama_cleaner.schema import Config
    LAMA_AVAILABLE = True
except ImportError:
    LAMA_AVAILABLE = False

class LamaInpainter:
    """LaMa deep learning inpainting wrapper"""
    def __init__(self):
        self.device = torch.device("mps" if torch.backends.mps.is_available() else 
                                 "cuda" if torch.cuda.is_available() else "cpu")
        self.available = False
        
        if LAMA_AVAILABLE:
            try:
                self.model = ModelManager(
                    name="lama",
                    device=self.device,
                    no_half=False,
                    low_mem=True,
                    cpu_offload=False,
                    disable_nsfw=True
                )
                self.config = Config(
                    ldm_steps=20,
                    ldm_sampler='plms',
                    hd_strategy='Resize',
                    hd_strategy_crop_margin=32,
                    hd_strategy_crop_trigger_size=1024,
                    hd_strategy_resize_limit=2048,
                )
                self.available = True
            except Exception as e:
                print(f"Failed to load LaMa: {e}")
                self.available = False
    
    def inpaint(self, image, mask):
        """Inpaint using LaMa or fallback to CV2"""
        if not self.available:
            return self._fallback_inpaint(image, mask)
        
        try:
            # Convert to numpy
            if isinstance(image, Image.Image):
                image_np = np.array(image)
            else:
                image_np = image
                
            if isinstance(mask, Image.Image):
                mask_np = np.array(mask)
            else:
                mask_np = mask
                
            # Ensure RGB
            if len(image_np.shape) == 2:
                image_np = cv2.cvtColor(image_np, cv2.COLOR_GRAY2RGB)
            if len(mask_np.shape) == 3:
                mask_np = cv2.cvtColor(mask_np, cv2.COLOR_RGB2GRAY)
                
            result = self.model(image_np, mask_np, self.config)
            return Image.fromarray(result)
            
        except Exception as e:
            print(f"LaMa failed: {e}, falling back to CV2")
            return self._fallback_inpaint(image, mask)
    
    def _fallback_inpaint(self, image, mask):
        """Fallback to advanced CV2 inpainting"""
        if isinstance(image, Image.Image):
            image = np.array(image)
        if isinstance(mask, Image.Image):
            mask = np.array(mask)
            
        if len(image.shape) == 2:
            image = cv2.cvtColor(image, cv2.COLOR_GRAY2RGB)
        if len(mask.shape) == 3:
            mask = cv2.cvtColor(mask, cv2.COLOR_RGB2GRAY)
            
        # Multi-pass inpainting
        result = image.copy()
        for radius in [3, 7, 11]:
            result = cv2.inpaint(result, mask, inpaintRadius=radius, flags=cv2.INPAINT_TELEA)
            
        return Image.fromarray(result)

class DustRemovalApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Film Dust Removal - Drag & Drop Interface")
        self.root.geometry("800x600")
        
        # Initialize variables
        self.image_path = None
        self.weights_path = None
        self.model = None
        self.device = torch.device("mps" if torch.backends.mps.is_available() else 
                                 "cuda" if torch.cuda.is_available() else "cpu")
        self.lama_inpainter = None
        
        # Configuration
        self.patch_size = 1024
        self.stride = 512
        
        self.setup_ui()
        self.setup_drag_drop()
        
    def setup_ui(self):
        """Setup the user interface"""
        
        # Main frame
        main_frame = ttk.Frame(self.root, padding="10")
        main_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        
        # Configure grid weights
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)
        main_frame.columnconfigure(1, weight=1)
        
        # Title
        title_label = ttk.Label(main_frame, text="Film Dust Removal", 
                               font=("Helvetica", 16, "bold"))
        title_label.grid(row=0, column=0, columnspan=3, pady=(0, 20))
        
        # Image drag area
        ttk.Label(main_frame, text="1. Drag Image Here:", font=("Helvetica", 12, "bold")).grid(
            row=1, column=0, sticky=tk.W, pady=(0, 5))
        
        self.image_frame = tk.Frame(main_frame, width=400, height=200, 
                                   bg="lightgray", relief="ridge", bd=2)
        self.image_frame.grid(row=2, column=0, columnspan=3, pady=(0, 10), sticky=(tk.W, tk.E))
        self.image_frame.grid_propagate(False)
        
        self.image_label = ttk.Label(self.image_frame, text="Drop image file here\\n(.jpg, .jpeg, .png)")
        self.image_label.place(relx=0.5, rely=0.5, anchor="center")
        
        # Browse button for image
        ttk.Button(main_frame, text="Browse Image", 
                  command=self.browse_image).grid(row=3, column=0, pady=5, sticky=tk.W)
        
        # Weights drag area
        ttk.Label(main_frame, text="2. Drag Model Weights Here:", 
                 font=("Helvetica", 12, "bold")).grid(row=4, column=0, sticky=tk.W, pady=(20, 5))
        
        self.weights_frame = tk.Frame(main_frame, width=400, height=100, 
                                     bg="lightblue", relief="ridge", bd=2)
        self.weights_frame.grid(row=5, column=0, columnspan=3, pady=(0, 10), sticky=(tk.W, tk.E))
        self.weights_frame.grid_propagate(False)
        
        self.weights_label = ttk.Label(self.weights_frame, text="Drop .pth weights file here")
        self.weights_label.place(relx=0.5, rely=0.5, anchor="center")
        
        # Browse button for weights
        ttk.Button(main_frame, text="Browse Weights", 
                  command=self.browse_weights).grid(row=6, column=0, pady=5, sticky=tk.W)
        
        # Settings frame
        settings_frame = ttk.LabelFrame(main_frame, text="Settings", padding="10")
        settings_frame.grid(row=7, column=0, columnspan=3, pady=(20, 10), sticky=(tk.W, tk.E))
        
        # Threshold slider
        ttk.Label(settings_frame, text="Detection Threshold:").grid(row=0, column=0, sticky=tk.W)
        self.threshold_var = tk.DoubleVar(value=0.005)  # Default 5e-3
        self.threshold_scale = ttk.Scale(settings_frame, from_=0.001, to=0.05, 
                                        variable=self.threshold_var, orient="horizontal")
        self.threshold_scale.grid(row=0, column=1, sticky=(tk.W, tk.E), padx=(10, 0))
        
        self.threshold_label = ttk.Label(settings_frame, text=f"{self.threshold_var.get():.3f}")
        self.threshold_label.grid(row=0, column=2, padx=(10, 0))
        self.threshold_var.trace("w", self.update_threshold_label)
        
        # Inpainting method
        ttk.Label(settings_frame, text="Inpainting Method:").grid(row=1, column=0, sticky=tk.W, pady=(10, 0))
        self.inpaint_method = tk.StringVar(value="LaMa" if LAMA_AVAILABLE else "CV2 Advanced")
        methods = ["LaMa (Deep Learning)", "CV2 Advanced", "CV2 TELEA", "CV2 Navier-Stokes"] if LAMA_AVAILABLE else ["CV2 Advanced", "CV2 TELEA", "CV2 Navier-Stokes"]
        self.method_combo = ttk.Combobox(settings_frame, textvariable=self.inpaint_method, 
                                        values=methods, state="readonly")
        self.method_combo.grid(row=1, column=1, sticky=(tk.W, tk.E), padx=(10, 0), pady=(10, 0))
        
        # Configure column weights
        settings_frame.columnconfigure(1, weight=1)
        
        # Progress bar
        self.progress_var = tk.DoubleVar()
        self.progress_bar = ttk.Progressbar(main_frame, variable=self.progress_var, 
                                           maximum=100, length=400)
        self.progress_bar.grid(row=8, column=0, columnspan=3, pady=(0, 10), sticky=(tk.W, tk.E))
        
        # Status label
        self.status_var = tk.StringVar(value="Ready - Drag image and weights files")
        self.status_label = ttk.Label(main_frame, textvariable=self.status_var)
        self.status_label.grid(row=9, column=0, columnspan=3, pady=(0, 10))
        
        # Process button
        self.process_button = ttk.Button(main_frame, text="🎯 Remove Dust & Save", 
                                        command=self.process_image, state="disabled")
        self.process_button.grid(row=10, column=0, columnspan=3, pady=10)
        
        # Device info
        device_info = f"Device: {self.device} | LaMa: {'✅' if LAMA_AVAILABLE else '❌'}"
        ttk.Label(main_frame, text=device_info, font=("Helvetica", 9)).grid(
            row=11, column=0, columnspan=3, pady=(10, 0))
    
    def setup_drag_drop(self):
        """Setup drag and drop functionality"""
        
        # Image drag and drop
        self.image_frame.drop_target_register(DND_FILES)
        self.image_frame.dnd_bind('<<Drop>>', self.on_image_drop)
        
        # Weights drag and drop
        self.weights_frame.drop_target_register(DND_FILES)
        self.weights_frame.dnd_bind('<<Drop>>', self.on_weights_drop)
    
    def on_image_drop(self, event):
        """Handle image file drop"""
        files = self.root.tk.splitlist(event.data)
        if files:
            file_path = files[0]
            if file_path.lower().endswith(('.jpg', '.jpeg', '.png', '.tiff', '.bmp')):
                self.set_image_path(file_path)
            else:
                messagebox.showerror("Error", "Please drop a valid image file (.jpg, .jpeg, .png)")
    
    def on_weights_drop(self, event):
        """Handle weights file drop"""
        files = self.root.tk.splitlist(event.data)
        if files:
            file_path = files[0]
            if file_path.lower().endswith('.pth'):
                self.set_weights_path(file_path)
            else:
                messagebox.showerror("Error", "Please drop a valid weights file (.pth)")
    
    def browse_image(self):
        """Browse for image file"""
        file_path = filedialog.askopenfilename(
            title="Select Image",
            filetypes=[("Image files", "*.jpg *.jpeg *.png *.tiff *.bmp")]
        )
        if file_path:
            self.set_image_path(file_path)
    
    def browse_weights(self):
        """Browse for weights file"""
        file_path = filedialog.askopenfilename(
            title="Select Model Weights",
            filetypes=[("PyTorch weights", "*.pth")]
        )
        if file_path:
            self.set_weights_path(file_path)
    
    def set_image_path(self, path):
        """Set image path and update UI"""
        self.image_path = path
        filename = os.path.basename(path)
        self.image_label.config(text=f"✅ {filename}")
        self.image_frame.config(bg="lightgreen")
        self.update_process_button()
        self.status_var.set(f"Image loaded: {filename}")
    
    def set_weights_path(self, path):
        """Set weights path and update UI"""
        self.weights_path = path
        filename = os.path.basename(path)
        self.weights_label.config(text=f"✅ {filename}")
        self.weights_frame.config(bg="lightgreen")
        self.update_process_button()
        self.status_var.set(f"Weights loaded: {filename}")
        
        # Try to load model
        try:
            self.load_model()
        except Exception as e:
            messagebox.showerror("Error", f"Failed to load model: {str(e)}")
            self.weights_path = None
            self.weights_label.config(text="Drop .pth weights file here")
            self.weights_frame.config(bg="lightblue")
            self.update_process_button()
    
    def load_model(self):
        """Load the U-Net model"""
        if not self.weights_path:
            return
            
        self.model = UNet()
        self.model.load_state_dict(torch.load(self.weights_path, map_location="cpu"))
        self.model = self.model.to(self.device)
        self.model.eval()
        
        # Initialize LaMa if available
        if LAMA_AVAILABLE and "LaMa" in self.inpaint_method.get():
            if self.lama_inpainter is None:
                self.lama_inpainter = LamaInpainter()
    
    def update_process_button(self):
        """Update process button state"""
        if self.image_path and self.weights_path:
            self.process_button.config(state="normal")
        else:
            self.process_button.config(state="disabled")
    
    def update_threshold_label(self, *args):
        """Update threshold label"""
        self.threshold_label.config(text=f"{self.threshold_var.get():.3f}")
    
    def process_image(self):
        """Process image in separate thread"""
        if not self.image_path or not self.weights_path:
            return
            
        # Disable button during processing
        self.process_button.config(state="disabled")
        
        # Start processing in separate thread
        thread = threading.Thread(target=self._process_image_thread)
        thread.daemon = True
        thread.start()
    
    def _process_image_thread(self):
        """Process image in background thread"""
        try:
            self.status_var.set("🔍 Loading image...")
            self.progress_var.set(10)
            
            # Load image
            image = Image.open(self.image_path).convert('L')
            image_np = np.array(image)
            H, W = image_np.shape
            
            self.status_var.set("🧠 Running dust detection...")
            self.progress_var.set(20)
            
            # Dust detection
            final_mask, binary_mask = self.detect_dust(image_np)
            
            self.status_var.set("🎨 Running inpainting...")
            self.progress_var.set(60)
            
            # Inpainting
            result_image = self.inpaint_image(image_np, binary_mask)
            
            self.status_var.set("💾 Saving result...")
            self.progress_var.set(90)
            
            # Save result
            self.save_result(result_image)
            
            self.progress_var.set(100)
            self.status_var.set("✅ Complete! Image saved with _dust_removal suffix")
            
        except Exception as e:
            self.status_var.set(f"❌ Error: {str(e)}")
            messagebox.showerror("Processing Error", str(e))
        finally:
            # Re-enable button
            self.process_button.config(state="normal")
            self.progress_var.set(0)
    
    def detect_dust(self, image_np):
        """Detect dust using patch-based inference"""
        H, W = image_np.shape
        
        # Pad image
        pad_h = (self.patch_size - H % self.stride) % self.stride if H % self.stride != 0 else 0
        pad_w = (self.patch_size - W % self.stride) % self.stride if W % self.stride != 0 else 0
        padded = np.pad(image_np, ((0, pad_h), (0, pad_w)), mode='reflect')
        pH, pW = padded.shape
        
        # Initialize maps
        prediction_map = np.zeros((pH, pW), dtype=np.float32)
        count_map = np.zeros((pH, pW), dtype=np.float32)
        
        # Patch-wise inference
        with torch.no_grad():
            total_patches = len(range(0, pH - self.patch_size + 1, self.stride)) * len(range(0, pW - self.patch_size + 1, self.stride))
            patch_count = 0
            
            for y in range(0, pH - self.patch_size + 1, self.stride):
                for x in range(0, pW - self.patch_size + 1, self.stride):
                    patch = padded[y:y+self.patch_size, x:x+self.patch_size]
                    patch_tensor = torch.from_numpy(patch).float().unsqueeze(0).unsqueeze(0) / 255.0
                    patch_tensor = patch_tensor.to(self.device)
                    pred = self.model(patch_tensor)
                    pred = pred.squeeze().cpu().numpy()
                    prediction_map[y:y+self.patch_size, x:x+self.patch_size] += pred
                    count_map[y:y+self.patch_size, x:x+self.patch_size] += 1.0
                    
                    patch_count += 1
                    progress = 20 + (patch_count / total_patches) * 40  # 20-60%
                    self.progress_var.set(progress)
        
        # Finalize prediction
        final_mask = prediction_map / np.maximum(count_map, 1e-8)
        final_mask = final_mask[:H, :W]
        
        # Apply threshold
        threshold = self.threshold_var.get()
        binary_mask = (final_mask > threshold).astype(np.uint8)
        
        return final_mask, binary_mask
    
    def inpaint_image(self, image_np, binary_mask):
        """Inpaint image using selected method"""
        # Convert to RGB
        image_rgb = cv2.cvtColor(image_np, cv2.COLOR_GRAY2RGB)
        
        # Ensure mask matches image dimensions exactly
        H, W = image_np.shape
        if binary_mask.shape != (H, W):
            binary_mask = cv2.resize(binary_mask, (W, H), interpolation=cv2.INTER_NEAREST)
        
        # Dilate mask
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
        mask_dilated = cv2.dilate(binary_mask * 255, kernel, iterations=1)
        
        method = self.inpaint_method.get()
        
        if "LaMa" in method and self.lama_inpainter:
            result = self.lama_inpainter.inpaint(image_rgb, mask_dilated)
            return np.array(result)
        elif "Advanced" in method:
            # Multi-pass CV2
            result = image_rgb.copy()
            for radius in [3, 7, 11]:
                result = cv2.inpaint(result, mask_dilated, inpaintRadius=radius, flags=cv2.INPAINT_TELEA)
            return result
        elif "TELEA" in method:
            return cv2.inpaint(image_rgb, mask_dilated, inpaintRadius=3, flags=cv2.INPAINT_TELEA)
        elif "Navier" in method:
            return cv2.inpaint(image_rgb, mask_dilated, inpaintRadius=5, flags=cv2.INPAINT_NS)
        else:
            # Default to CV2 TELEA
            return cv2.inpaint(image_rgb, mask_dilated, inpaintRadius=3, flags=cv2.INPAINT_TELEA)
    
    def save_result(self, result_image):
        """Save the result image with _dust_removal suffix"""
        # Get original file path components
        path = Path(self.image_path)
        
        # Create new filename with suffix
        new_name = f"{path.stem}_dust_removal{path.suffix}"
        output_path = path.parent / new_name
        
        # Save image
        Image.fromarray(result_image).save(output_path, quality=95)
        
        return output_path

def main():
    """Main application entry point"""
    # Create root window with drag-and-drop support
    root = TkinterDnD.Tk()
    
    # Set up the application
    app = DustRemovalApp(root)
    
    # Start the GUI event loop
    root.mainloop()

if __name__ == "__main__":
    main()