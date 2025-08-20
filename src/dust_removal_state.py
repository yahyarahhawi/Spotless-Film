#!/usr/bin/env python3
"""
Dust Removal State Management

Centralized state management for the dust removal application,
matching the SwiftUI ObservableObject pattern from Spotless-Film.
"""

import tkinter as tk
from tkinter import messagebox
import numpy as np
from PIL import Image, ImageTk
import torch
import torch.nn as nn
from typing import Optional, List, Tuple, Callable
import threading
from dataclasses import dataclass
from enum import Enum
import cv2


class ProcessingMode(Enum):
    SINGLE = "single"
    SIDE_BY_SIDE = "side_by_side"
    SPLIT_SLIDER = "split_slider"


class ToolMode(Enum):
    NONE = "none"
    ERASER = "eraser"
    BRUSH = "brush"
    PAN = "pan"


@dataclass
class ViewState:
    """View-related state"""
    zoom_scale: float = 1.0
    drag_offset: Tuple[float, float] = (0.0, 0.0)
    showing_original: bool = False
    hide_detections: bool = False
    processing_mode: ProcessingMode = ProcessingMode.SINGLE
    split_position: float = 0.5
    overlay_opacity: float = 0.6
    tool_mode: ToolMode = ToolMode.NONE
    brush_size: int = 15
    space_key_pressed: bool = False


@dataclass
class ProcessingState:
    """Processing-related state"""
    is_detecting: bool = False
    is_removing: bool = False
    threshold: float = 0.05
    processing_time: float = 0.0
    patch_size: int = 1024
    stride: int = 512


class DustRemovalState:
    """Main state management class matching SwiftUI's DustRemovalState"""
    
    def __init__(self, root: tk.Tk):
        self.root = root
        
        # Images
        self.selected_image: Optional[Image.Image] = None
        self.processed_image: Optional[Image.Image] = None
        self.dust_mask: Optional[Image.Image] = None
        self.original_dust_mask: Optional[Image.Image] = None
        self.raw_prediction_mask: Optional[np.ndarray] = None
        
        # Low-resolution drawing for performance
        self.low_res_mask: Optional[Image.Image] = None
        self.low_res_scale: float = 0.25
        self.max_drawing_resolution: float = 1024
        
        # Models
        self.unet_model: Optional[nn.Module] = None
        self.lama_inpainter = None
        
        # Device
        self.device = torch.device(
            "mps" if torch.backends.mps.is_available() else
            "cuda" if torch.cuda.is_available() else "cpu"
        )
        
        # State objects
        self.view_state = ViewState()
        self.processing_state = ProcessingState()
        
        # Undo system
        self.mask_history: List[Image.Image] = []
        self.max_history_size = 20
        self.is_dragging = False
        
        # Stroke tracking for smooth drawing
        self.last_brush_point: Optional[Tuple[float, float]] = None
        self.last_eraser_point: Optional[Tuple[float, float]] = None
        
        # Error handling
        self.error_message: Optional[str] = None
        self.showing_error = False
        
        # Observer callbacks
        self.observers: List[Callable] = []
        
        # Threading locks
        self._lock = threading.Lock()
    
    def add_observer(self, callback: Callable) -> None:
        """Add an observer for state changes"""
        self.observers.append(callback)
    
    def notify_observers(self) -> None:
        """Notify all observers of state changes"""
        print(f"🔔 notify_observers called with {len(self.observers)} observers")
        for i, callback in enumerate(self.observers):
            try:
                print(f"🔔 Scheduling observer {i}: {callback.__name__ if hasattr(callback, '__name__') else str(callback)}")
                self.root.after_idle(callback)
            except Exception as e:
                print(f"🔔 Error scheduling observer {i}: {e}")
                pass  # Handle stale callbacks gracefully
    
    # MARK: - Computed Properties
    
    @property
    def can_detect_dust(self) -> bool:
        return (self.selected_image is not None and 
                self.unet_model is not None and 
                not self.processing_state.is_detecting and 
                not self.processing_state.is_removing)
    
    @property
    def can_remove_dust(self) -> bool:
        return (self.dust_mask is not None and 
                not self.processing_state.is_detecting and 
                not self.processing_state.is_removing)
    
    @property
    def is_in_detection_mode(self) -> bool:
        return self.dust_mask is not None and self.processed_image is None
    
    @property
    def can_undo(self) -> bool:
        return len(self.mask_history) > 0
    
    # MARK: - Actions
    
    def reset_processing(self) -> None:
        """Reset processing state for new image"""
        with self._lock:
            self.processed_image = None
            self.dust_mask = None
            self.original_dust_mask = None
            self.raw_prediction_mask = None
            self.view_state.hide_detections = False
            self.reset_zoom()
            self.clear_mask_history()
            self.low_res_mask = None
            self.notify_observers()
    
    def reset_zoom(self) -> None:
        """Reset zoom and pan to default"""
        self.view_state.zoom_scale = 1.0
        self.view_state.drag_offset = (0.0, 0.0)
        self.notify_observers()
    
    def zoom_in(self) -> None:
        """Zoom in by 1.5x up to 5x max"""
        self.view_state.zoom_scale = min(self.view_state.zoom_scale * 1.5, 5.0)
        self.notify_observers()
    
    def zoom_out(self) -> None:
        """Zoom out by 1.5x down to 1x min"""
        self.view_state.zoom_scale = max(self.view_state.zoom_scale / 1.5, 1.0)
        if self.view_state.zoom_scale == 1.0:
            self.view_state.drag_offset = (0.0, 0.0)
        self.notify_observers()
    
    def set_tool_mode(self, mode: ToolMode) -> None:
        """Set the current tool mode"""
        self.view_state.tool_mode = mode
        self.notify_observers()
    
    def toggle_overlay(self) -> None:
        """Toggle dust overlay visibility"""
        self.view_state.hide_detections = not self.view_state.hide_detections
        self.notify_observers()
    
    def set_processing_mode(self, mode: ProcessingMode) -> None:
        """Set the processing/compare mode"""
        self.view_state.processing_mode = mode
        # Do not force-hide detections; let the user control overlay visibility
        self.notify_observers()
    
    def show_error(self, message: str) -> None:
        """Show error message"""
        self.error_message = message
        self.showing_error = True
        messagebox.showerror("Error", message)
        self.notify_observers()
    
    # MARK: - Undo System
    
    def save_mask_to_history(self) -> None:
        """Save current mask to undo history"""
        if self.dust_mask is None:
            return
        
        # Convert PIL to copy for history
        mask_copy = self.dust_mask.copy()
        self.mask_history.append(mask_copy)
        
        # Limit history size
        if len(self.mask_history) > self.max_history_size:
            self.mask_history.pop(0)
    
    def start_brush_stroke(self) -> None:
        """Start a new brush stroke"""
        if not self.is_dragging:
            self.save_mask_to_history()
            self.is_dragging = True
    
    def end_brush_stroke(self) -> None:
        """End the current brush stroke"""
        self.is_dragging = False
        self.last_brush_point = None
        self.last_eraser_point = None
        
        # Sync low-res changes back to full resolution
        self.sync_low_res_to_full_res()
        self.notify_observers()
    
    def undo_last_mask_change(self) -> None:
        """Undo the last mask change"""
        if not self.mask_history:
            return
        
        # Restore previous mask
        self.dust_mask = self.mask_history.pop()
        
        # Recreate low-res mask from restored full-res mask
        self.create_low_res_mask()
        self.notify_observers()
    
    def clear_mask_history(self) -> None:
        """Clear undo history"""
        self.mask_history.clear()
        self.is_dragging = False
    
    # MARK: - Low-Resolution Drawing Methods
    
    def create_low_res_mask(self) -> None:
        """Create low-resolution mask for performance"""
        if self.dust_mask is None:
            self.low_res_mask = None
            return
        
        original_size = self.dust_mask.size
        
        # Calculate optimal low-res size
        max_dimension = max(original_size)
        target_scale = min(self.low_res_scale, self.max_drawing_resolution / max_dimension)
        
        low_res_size = (
            int(original_size[0] * target_scale),
            int(original_size[1] * target_scale)
        )
        
        self.low_res_mask = self.dust_mask.resize(low_res_size, Image.NEAREST)
        print(f"🎨 Created low-res mask: {low_res_size} (scale: {target_scale})")
    
    def get_low_res_mask(self) -> Optional[Image.Image]:
        """Get low-resolution mask, creating if needed"""
        if self.low_res_mask is None:
            self.create_low_res_mask()
        return self.low_res_mask
    
    def update_low_res_mask(self, new_low_res_mask: Image.Image) -> None:
        """Update low-res mask and provide visual feedback"""
        self.low_res_mask = new_low_res_mask
        
        # Update the display mask immediately with upscaled version for visual feedback
        if self.dust_mask is not None:
            upscaled_mask = new_low_res_mask.resize(self.dust_mask.size, Image.NEAREST)
            self.dust_mask = upscaled_mask
        
        self.notify_observers()
    
    def sync_low_res_to_full_res(self) -> None:
        """Sync low-res drawing to full resolution"""
        if self.low_res_mask is None or self.dust_mask is None:
            return
        
        # Upscale the low-res mask to full resolution
        final_mask = self.low_res_mask.resize(self.dust_mask.size, Image.NEAREST)
        self.dust_mask = final_mask
        
        print("🔄 Synced low-res drawing to full resolution")

    # MARK: - Image Processing Helpers
    
    def dilate_mask(self, mask: Image.Image, kernel_size: int = 5) -> Image.Image:
        """Dilate mask using OpenCV"""
        # Convert PIL to numpy
        mask_np = np.array(mask.convert('L'))
        
        # Create elliptical kernel
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel_size, kernel_size))
        
        # Apply dilation
        dilated = cv2.dilate(mask_np, kernel, iterations=1)
        
        # Convert back to PIL
        return Image.fromarray(dilated, mode='L')
    
    def create_binary_mask_from_prediction(self, prediction: np.ndarray, threshold: float, 
                                         original_size: Tuple[int, int]) -> Optional[Image.Image]:
        """Create binary mask from ML prediction"""
        try:
            # Handle different prediction formats
            if len(prediction.shape) == 4:
                # Batch dimension
                prediction = prediction[0]
            if len(prediction.shape) == 3:
                # Channel dimension
                prediction = prediction[0]
            
            # Apply threshold
            binary_mask = (prediction > threshold).astype(np.uint8) * 255
            
            # Convert to PIL and resize
            mask_image = Image.fromarray(binary_mask, mode='L')
            return mask_image.resize(original_size, Image.NEAREST)
            
        except Exception as e:
            print(f"❌ Error creating binary mask: {e}")
            return None
