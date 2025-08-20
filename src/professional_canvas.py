#!/usr/bin/env python3
"""
Professional Canvas for Dust Removal App

Advanced canvas component matching Spotless-Film's ProfessionalCanvas with
multiple view modes, zoom/pan, and brush tools.
"""

import tkinter as tk
from tkinter import ttk
from tkinterdnd2 import DND_FILES
from PIL import Image, ImageTk, ImageDraw
import numpy as np
from typing import Optional, Callable, Tuple
import math
from dust_removal_state import DustRemovalState, ProcessingMode, ToolMode
from simple_modern_theme import SimpleModernColors


class SpotlessCanvas(tk.Frame):
    """Spotless Film canvas with multiple view modes and advanced controls"""
    
    def __init__(self, parent, state: DustRemovalState, callbacks: dict, **kwargs):
        super().__init__(parent, **kwargs)
        self.state = state
        self.callbacks = callbacks
        
        # Canvas state
        self.canvas_images = {}
        self.display_scale = 1.0
        self.image_bounds = (0, 0, 0, 0)  # x, y, width, height on canvas
        
        # Interaction state
        self.is_panning = False
        self.last_mouse_pos = None
        self.pan_start_offset = None
        
        # Split view state
        self.split_position = 0.5
        self.split_dragging = False
        
        self.setup_ui()
        self.state.add_observer(self.update_canvas)
        
    def setup_ui(self):
        """Setup canvas UI"""
        self.config(bg=SimpleModernColors.BG_DARK, relief='flat', borderwidth=0)
        
        # Main canvas with modern styling
        self.canvas = tk.Canvas(self, 
                               bg=SimpleModernColors.BG_DARK, 
                               highlightthickness=0,
                               relief='flat',
                               borderwidth=0)
        self.canvas.pack(fill='both', expand=True)
        
        # Setup drag and drop
        self.canvas.drop_target_register(DND_FILES)
        self.canvas.dnd_bind('<<Drop>>', self.on_image_drop)
        
        # Bind events
        self.canvas.bind('<Button-1>', self.on_mouse_down)
        self.canvas.bind('<B1-Motion>', self.on_mouse_drag)
        self.canvas.bind('<ButtonRelease-1>', self.on_mouse_up)
        self.canvas.bind('<Double-Button-1>', self.on_double_click)
        self.canvas.bind('<MouseWheel>', self.on_mouse_wheel)
        self.canvas.bind('<Configure>', self.on_canvas_resize)
        
        # Keyboard bindings
        self.canvas.bind('<KeyPress-space>', self.on_space_press)
        self.canvas.bind('<KeyRelease-space>', self.on_space_release)
        self.canvas.bind('<Motion>', self.on_mouse_motion)
        self.canvas.focus_set()
        
        # Brush cursor state
        self.brush_cursor_id = None
        self.cursor_visible = False
        
        # Initial display
        self.show_drop_zone()
    
    def show_drop_zone(self):
        """Show drop zone when no image is loaded"""
        self.canvas.delete('all')
        
        # Center text
        canvas_width = self.canvas.winfo_width() or 800
        canvas_height = self.canvas.winfo_height() or 600
        
        center_x = canvas_width // 2
        center_y = canvas_height // 2
        
        # Background gradient effect (using rectangles)
        gradient_steps = 20
        for i in range(gradient_steps):
            alpha = 1 - (i / gradient_steps) * 0.3
            color_value = int(28 + i * 2)  # Subtle gradient from BG_CANVAS
            color = f"#{color_value:02x}{color_value:02x}{color_value:02x}"
            y_start = center_y - 100 + i * 10
            self.canvas.create_rectangle(0, y_start, canvas_width, y_start + 10, 
                                       fill=color, outline="")
        
        # Modern icon with glow effect
        self.canvas.create_text(center_x, center_y - 60, text="🖼️",
                               font=("Helvetica", 56), fill=SimpleModernColors.TEXT_MEDIUM)
        
        # Main text with modern typography
        self.canvas.create_text(center_x, center_y - 5, 
                               text="Drag and drop an image here",
                               font=("Helvetica", 20, "bold"), 
                               fill=SimpleModernColors.TEXT_WHITE)
        
        # Subtitle
        self.canvas.create_text(center_x, center_y + 25,
                               text="or use the Import button to browse",
                               font=("Helvetica", 14, "normal"), 
                               fill=SimpleModernColors.TEXT_LIGHT)
        
        # Supported formats
        self.canvas.create_text(center_x, center_y + 50,
                               text="Supported formats: PNG, JPEG, TIFF",
                               font=("Helvetica", 12, "normal"), 
                               fill=SimpleModernColors.TEXT_MEDIUM)
    
    def update_canvas(self):
        """Update canvas based on current state"""
        print(f"🖼️ Canvas update_canvas called")
        print(f"🖼️ Selected image: {self.state.selected_image is not None}")
        print(f"🖼️ Processed image: {self.state.processed_image is not None}")
        print(f"🖼️ Processing mode: {self.state.view_state.processing_mode}")
        
        # Update cursor based on tool mode
        self.update_cursor_for_tool_change()
        
        if not self.state.selected_image and not self.state.processed_image:
            print("🖼️ No images, showing drop zone")
            self.show_drop_zone()
            return
        
        # Choose rendering mode
        if self.state.view_state.processing_mode == ProcessingMode.SINGLE:
            print("🖼️ Rendering single view")
            self.render_single_view()
        elif self.state.view_state.processing_mode == ProcessingMode.SIDE_BY_SIDE:
            print("🖼️ Rendering side by side view")
            self.render_side_by_side_view()
        elif self.state.view_state.processing_mode == ProcessingMode.SPLIT_SLIDER:
            print("🖼️ Rendering split slider view")
            self.render_split_slider_view()
    
    def render_single_view(self):
        """Render single image view"""
        self.canvas.delete('all')
        
        # Determine which image to show
        image_to_show = self.get_image_to_display()
        if not image_to_show:
            return
        
        # Calculate display parameters
        canvas_width = self.canvas.winfo_width() or 800
        canvas_height = self.canvas.winfo_height() or 600
        
        display_image, image_bounds = self.prepare_image_for_display(
            image_to_show, canvas_width, canvas_height
        )
        
        if not display_image:
            return
        
        # Convert to PhotoImage and display
        photo = ImageTk.PhotoImage(display_image)
        self.canvas_images['main'] = photo  # Keep reference
        
        image_id = self.canvas.create_image(
            image_bounds[0] + image_bounds[2] // 2,
            image_bounds[1] + image_bounds[3] // 2,
            image=photo
        )
        
        # Store image bounds for interaction
        self.image_bounds = image_bounds
        
        # Add dust overlay if appropriate
        if self.should_show_dust_overlay():
            self.render_dust_overlay(image_bounds)
        
        # Add header label
        self.add_view_header()
    
    def render_side_by_side_view(self):
        """Render side-by-side comparison view"""
        self.canvas.delete('all')
        
        canvas_width = self.canvas.winfo_width() or 800
        canvas_height = self.canvas.winfo_height() or 600
        
        # Calculate split dimensions
        half_width = canvas_width // 2 - 1
        
        # Left side - Original with overlay
        if self.state.selected_image:
            left_image, left_bounds = self.prepare_image_for_display(
                self.state.selected_image, half_width, canvas_height
            )
            
            if left_image:
                photo_left = ImageTk.PhotoImage(left_image)
                self.canvas_images['left'] = photo_left
                
                self.canvas.create_image(
                    left_bounds[0] + left_bounds[2] // 2,
                    left_bounds[1] + left_bounds[3] // 2,
                    image=photo_left
                )
                
                # Add dust overlay on left side
                if self.should_show_dust_overlay():
                    self.render_dust_overlay(left_bounds, alpha=0.6)
        
        # Right side - Processed or placeholder
        right_x_offset = half_width + 2
        
        if self.state.processed_image:
            right_image, right_bounds = self.prepare_image_for_display(
                self.state.processed_image, half_width, canvas_height
            )
            
            if right_image:
                # Adjust bounds for right side
                right_bounds = (
                    right_bounds[0] + right_x_offset,
                    right_bounds[1],
                    right_bounds[2],
                    right_bounds[3]
                )
                
                photo_right = ImageTk.PhotoImage(right_image)
                self.canvas_images['right'] = photo_right
                
                self.canvas.create_image(
                    right_bounds[0] + right_bounds[2] // 2,
                    right_bounds[1] + right_bounds[3] // 2,
                    image=photo_right
                )
        else:
            # Placeholder for processed image
            placeholder_bounds = (right_x_offset, 40, half_width, canvas_height - 40)
            self.canvas.create_rectangle(
                placeholder_bounds[0], placeholder_bounds[1],
                placeholder_bounds[0] + placeholder_bounds[2],
                placeholder_bounds[1] + placeholder_bounds[3],
                fill='#e8e8e8', outline='#cccccc'
            )
            
            # Placeholder text
            center_x = placeholder_bounds[0] + placeholder_bounds[2] // 2
            center_y = placeholder_bounds[1] + placeholder_bounds[3] // 2
            
            self.canvas.create_text(center_x, center_y - 20, text="✨",
                                   font=("SF Pro Display", 32), fill='#cccccc')
            self.canvas.create_text(center_x, center_y + 20,
                                   text="Run dust removal",
                                   font=("SF Pro Display", 14), fill='#888888')
        
        # Add separator line
        separator_x = half_width + 1
        self.canvas.create_line(separator_x, 0, separator_x, canvas_height,
                               fill='#cccccc', width=2)
        
        # Add labels
        self.add_side_by_side_labels()
    
    def render_split_slider_view(self):
        """Render split slider comparison view"""
        self.canvas.delete('all')
        
        if not self.state.selected_image or not self.state.processed_image:
            self.render_single_view()
            return
        
        canvas_width = self.canvas.winfo_width() or 800
        canvas_height = self.canvas.winfo_height() or 600
        
        # Prepare both images
        original_image, image_bounds = self.prepare_image_for_display(
            self.state.selected_image, canvas_width, canvas_height
        )
        processed_image, _ = self.prepare_image_for_display(
            self.state.processed_image, canvas_width, canvas_height
        )
        
        if not original_image or not processed_image:
            return
        
        # Create split position line
        split_x = int(canvas_width * self.split_position)
        
        # Create composite image
        composite = Image.new('RGB', (canvas_width, canvas_height), '#f5f5f5')
        
        # Paste original (full image)
        if original_image:
            composite.paste(original_image, (image_bounds[0], image_bounds[1]))
        
        # Create mask for processed image (left side only)
        mask = Image.new('L', (canvas_width, canvas_height), 0)
        mask_draw = ImageDraw.Draw(mask)
        mask_draw.rectangle([0, 0, split_x, canvas_height], fill=255)
        
        # Paste processed image with mask
        if processed_image:
            composite.paste(processed_image, (image_bounds[0], image_bounds[1]), mask)
        
        # Convert and display
        photo = ImageTk.PhotoImage(composite)
        self.canvas_images['composite'] = photo
        
        self.canvas.create_image(canvas_width // 2, canvas_height // 2, image=photo)
        
        # Add split line and handle
        self.render_split_line(split_x, canvas_height)
        
        # Add labels
        self.add_split_view_labels(split_x, canvas_width)
        
        # Store bounds for interaction
        self.image_bounds = image_bounds
    
    def render_split_line(self, split_x: int, canvas_height: int):
        """Render the split line and drag handle"""
        # Split line
        line_id = self.canvas.create_line(split_x, 0, split_x, canvas_height,
                                         fill='#333333', width=2,
                                         tags='split_line')
        
        # Drag handle
        handle_y = canvas_height // 2
        handle_size = 10
        
        handle_id = self.canvas.create_oval(
            split_x - handle_size, handle_y - handle_size,
            split_x + handle_size, handle_y + handle_size,
            fill='#333333', outline='#ffffff', width=2,
            tags='split_handle'
        )
        
        # Handle lines
        for i in range(-3, 4, 2):
            self.canvas.create_line(
                split_x + i, handle_y - 4,
                split_x + i, handle_y + 4,
                fill='#ffffff', width=1, tags='split_handle'
            )
    
    def get_image_to_display(self) -> Optional[Image.Image]:
        """Determine which image to display in single view mode"""
        print(f"🖼️ get_image_to_display called")
        print(f"🖼️ showing_original: {self.state.view_state.showing_original}")
        print(f"🖼️ processed_image exists: {self.state.processed_image is not None}")
        print(f"🖼️ hide_detections: {self.state.view_state.hide_detections}")
        print(f"🖼️ dust_mask exists: {self.state.dust_mask is not None}")
        
        # If showing original is explicitly requested, show original
        if self.state.view_state.showing_original and self.state.selected_image:
            print(f"🖼️ Returning selected_image (showing_original)")
            return self.state.selected_image
        # If we have a processed image (dust removed), prefer it
        elif self.state.processed_image:
            print(f"🖼️ Returning processed_image")
            return self.state.processed_image
        # If hiding detections but no processed image, show original without overlay
        elif self.state.view_state.hide_detections and self.state.dust_mask:
            print(f"🖼️ Returning selected_image (hide_detections)")
            return self.state.selected_image
        else:
            print(f"🖼️ Returning selected_image (default)")
            return self.state.selected_image
    
    def should_show_dust_overlay(self) -> bool:
        """Determine if dust overlay should be shown"""
        return (self.state.dust_mask is not None and
                not self.state.view_state.hide_detections and
                self.state.processed_image is None and
                not self.state.view_state.showing_original)
    
    def prepare_image_for_display(self, image: Image.Image, 
                                 canvas_width: int, canvas_height: int
                                ) -> Tuple[Optional[Image.Image], Tuple[int, int, int, int]]:
        """Prepare image for display with zoom and aspect ratio calculations"""
        if not image:
            return None, (0, 0, 0, 0)
        
        # Calculate aspect ratio fit
        image_aspect = image.size[0] / image.size[1]
        canvas_aspect = canvas_width / canvas_height
        
        if image_aspect > canvas_aspect:
            # Image is wider - fit to width
            display_width = canvas_width
            display_height = int(canvas_width / image_aspect)
        else:
            # Image is taller - fit to height
            display_height = canvas_height
            display_width = int(canvas_height * image_aspect)
        
        # Apply zoom
        zoom = self.state.view_state.zoom_scale
        zoomed_width = int(display_width * zoom)
        zoomed_height = int(display_height * zoom)
        
        # Calculate position with pan offset
        offset_x, offset_y = self.state.view_state.drag_offset
        pos_x = (canvas_width - zoomed_width) // 2 + int(offset_x)
        pos_y = (canvas_height - zoomed_height) // 2 + int(offset_y)
        
        # Resize image
        display_image = image.resize((zoomed_width, zoomed_height), Image.Resampling.LANCZOS)
        
        return display_image, (pos_x, pos_y, zoomed_width, zoomed_height)
    
    def render_dust_overlay(self, image_bounds: Tuple[int, int, int, int], alpha: float = None):
        """Render dust overlay on top of image"""
        if not self.state.dust_mask:
            return
        
        if alpha is None:
            alpha = self.state.view_state.overlay_opacity
        
        # Prepare dust mask for display
        mask_image, _ = self.prepare_image_for_display(
            self.state.dust_mask, image_bounds[2], image_bounds[3]
        )
        
        if not mask_image:
            return
        
        # Convert to RGBA and apply red color
        mask_rgba = mask_image.convert('RGBA')
        mask_array = np.array(mask_rgba)
        
        # Create red overlay where mask is white
        red_overlay = np.zeros_like(mask_array)
        red_overlay[:, :, 0] = mask_array[:, :, 0]  # Red channel from mask
        red_overlay[:, :, 3] = (mask_array[:, :, 0] * alpha).astype(np.uint8)  # Alpha from mask
        
        overlay_image = Image.fromarray(red_overlay, 'RGBA')
        overlay_photo = ImageTk.PhotoImage(overlay_image)
        self.canvas_images['overlay'] = overlay_photo
        
        self.canvas.create_image(
            image_bounds[0] + image_bounds[2] // 2,
            image_bounds[1] + image_bounds[3] // 2,
            image=overlay_photo
        )
    
    def add_view_header(self):
        """Add header label for current view"""
        canvas_width = self.canvas.winfo_width() or 800
        
        # Determine header text and color
        if self.state.view_state.hide_detections and self.state.dust_mask:
            text = "🖼️ Original Image"
            color = SimpleModernColors.ACCENT_BLUE
        elif self.state.view_state.showing_original and self.state.processed_image:
            text = "🖼️ Original Image (Hold to Compare)"
            color = SimpleModernColors.ACCENT_BLUE
        elif self.state.processed_image:
            text = "✨ Dust-Free Result"
            color = SimpleModernColors.ACCENT_ORANGE
        elif self.state.dust_mask:
            text = "🔍 Dust Detection Preview"
            color = SimpleModernColors.ACCENT_RED
        elif self.state.selected_image:
            text = "🖼️ Original Image"
            color = SimpleModernColors.ACCENT_BLUE
        else:
            text = "🖼️ No Image Selected"
            color = SimpleModernColors.TEXT_MEDIUM
        
        # Calculate dimensions
        text_width = len(text) * 8 + 20
        header_height = 36
        
        # Create modern header background with rounded corners effect
        header_bg = self.canvas.create_rectangle(
            20, 20, 
            20 + text_width, 20 + header_height,
            fill=SimpleModernColors.BG_MEDIUM, outline=SimpleModernColors.BG_LIGHT, width=1
        )
        
        # Create header text with modern typography
        header_text = self.canvas.create_text(
            20 + 12, 20 + header_height // 2, 
            text=text, anchor='w',
            font=("Helvetica", 13, "bold"), 
            fill=color
        )
    
    def add_side_by_side_labels(self):
        """Add labels for side-by-side view"""
        canvas_width = self.canvas.winfo_width() or 800
        half_width = canvas_width // 2
        
        # Original label with modern styling
        orig_bg = self.canvas.create_rectangle(
            20, 20, 
            20 + 140, 20 + 32, 
            fill=SimpleModernColors.BG_MEDIUM, 
            outline=SimpleModernColors.ACCENT_BLUE, width=1
        )
        self.canvas.create_text(
            20 + 70, 20 + 16, 
            text="🖼️ Original",
            font=("Helvetica", 13, "bold"), 
            fill=SimpleModernColors.ACCENT_BLUE
        )
        
        # Processed label (if available)
        if self.state.processed_image:
            label_x = half_width + 20
            proc_bg = self.canvas.create_rectangle(
                label_x, 20, 
                label_x + 120, 20 + 32,
                fill=SimpleModernColors.BG_MEDIUM, 
                outline=SimpleModernColors.ACCENT_GREEN, width=1
            )
            self.canvas.create_text(
                label_x + 60, 20 + 16, 
                text="✨ Dust-Free",
                font=("Helvetica", 13, "bold"), 
                fill=SimpleModernColors.ACCENT_GREEN
            )
    
    def add_split_view_labels(self, split_x: int, canvas_width: int):
        """Add labels for split view"""
        # Original label (left side)
        if split_x > 100:
            self.canvas.create_rectangle(20, 20, 140, 50, fill='white', outline='#007AFF')
            self.canvas.create_text(80, 35, text="🖼️ Original",
                                   font=("SF Pro Display", 11, "bold"), fill='#007AFF')
        
        # Processed label (right side)
        if split_x < canvas_width - 100:
            label_x = canvas_width - 140
            self.canvas.create_rectangle(label_x, 20, label_x + 120, 50,
                                       fill='white', outline='#34C759')
            self.canvas.create_text(label_x + 60, 35, text="✨ Dust-Free",
                                   font=("SF Pro Display", 11, "bold"), fill='#34C759')
    
    # MARK: - Event Handlers
    
    def on_mouse_down(self, event):
        """Handle mouse down events"""
        self.last_mouse_pos = (event.x, event.y)
        
        # Check for split line interaction in split view
        if self.state.view_state.processing_mode == ProcessingMode.SPLIT_SLIDER:
            if self.is_near_split_line(event.x):
                self.split_dragging = True
                self.config(cursor='sb_h_double_arrow')
                return
        
        # Handle tool interactions
        if self.state.view_state.tool_mode == ToolMode.ERASER:
            self.apply_eraser_at_point(event.x, event.y)
        elif self.state.view_state.tool_mode == ToolMode.BRUSH:
            self.apply_brush_at_point(event.x, event.y)
        elif self.state.view_state.space_key_pressed or self.state.view_state.zoom_scale > 1.0:
            self.is_panning = True
            self.pan_start_offset = self.state.view_state.drag_offset
            self.config(cursor='fleur')
    
    def on_mouse_drag(self, event):
        """Handle mouse drag events"""
        if not self.last_mouse_pos:
            return
        
        dx = event.x - self.last_mouse_pos[0]
        dy = event.y - self.last_mouse_pos[1]
        
        if self.split_dragging:
            # Update split position
            canvas_width = self.canvas.winfo_width() or 800
            self.split_position = max(0.0, min(1.0, event.x / canvas_width))
            self.update_canvas()
        elif self.is_panning:
            # Update pan offset
            if self.pan_start_offset:
                new_offset = (
                    self.pan_start_offset[0] + dx,
                    self.pan_start_offset[1] + dy
                )
                self.state.view_state.drag_offset = new_offset
                self.state.notify_observers()
        elif self.state.view_state.tool_mode == ToolMode.ERASER:
            self.apply_eraser_at_point(event.x, event.y)
        elif self.state.view_state.tool_mode == ToolMode.BRUSH:
            self.apply_brush_at_point(event.x, event.y)
        
        self.last_mouse_pos = (event.x, event.y)
    
    def on_mouse_up(self, event):
        """Handle mouse up events"""
        if self.split_dragging:
            self.split_dragging = False
            self.config(cursor='')
        elif self.is_panning:
            self.is_panning = False
            self.config(cursor='')
        elif self.state.view_state.tool_mode in [ToolMode.ERASER, ToolMode.BRUSH]:
            self.state.end_brush_stroke()
        
        self.last_mouse_pos = None
        self.pan_start_offset = None
    
    def on_double_click(self, event):
        """Handle double click to reset zoom"""
        self.state.reset_zoom()
    
    def on_mouse_wheel(self, event):
        """Handle mouse wheel for zooming"""
        if event.delta > 0:
            self.state.zoom_in()
        else:
            self.state.zoom_out()
    
    def on_space_press(self, event):
        """Handle space key press"""
        self.state.view_state.space_key_pressed = True
    
    def on_space_release(self, event):
        """Handle space key release"""
        self.state.view_state.space_key_pressed = False
    
    def on_canvas_resize(self, event):
        """Handle canvas resize"""
        self.update_canvas()
    
    def on_image_drop(self, event):
        """Handle image file drop"""
        files = self.tk.splitlist(event.data)
        if files and self.callbacks.get('handle_drop'):
            self.callbacks['handle_drop'](files)
    
    def is_near_split_line(self, x: int, tolerance: int = 10) -> bool:
        """Check if point is near split line"""
        canvas_width = self.canvas.winfo_width() or 800
        split_x = canvas_width * self.split_position
        return abs(x - split_x) <= tolerance
    
    def apply_eraser_at_point(self, x: int, y: int):
        """Apply eraser tool at given point"""
        if not self.state.dust_mask:
            return
        
        # Convert canvas coordinates to image coordinates
        image_point = self.canvas_to_image_coordinates(x, y)
        if not image_point:
            return
        
        if self.callbacks.get('eraser_click'):
            self.callbacks['eraser_click'](image_point, self.canvas.winfo_width(), self.canvas.winfo_height())
    
    def apply_brush_at_point(self, x: int, y: int):
        """Apply brush tool at given point"""
        if not self.state.dust_mask:
            return
        
        # Convert canvas coordinates to image coordinates
        image_point = self.canvas_to_image_coordinates(x, y)
        if not image_point:
            return
        
        if self.callbacks.get('brush_click'):
            self.callbacks['brush_click'](image_point, self.canvas.winfo_width(), self.canvas.winfo_height())
    
    def canvas_to_image_coordinates(self, canvas_x: int, canvas_y: int) -> Optional[Tuple[float, float]]:
        """Convert canvas coordinates to image coordinates"""
        if not self.image_bounds or not self.state.selected_image:
            return None
        
        bounds_x, bounds_y, bounds_w, bounds_h = self.image_bounds
        
        # Check if point is within image bounds
        if (canvas_x < bounds_x or canvas_x > bounds_x + bounds_w or
            canvas_y < bounds_y or canvas_y > bounds_y + bounds_h):
            return None
        
        # Convert to relative coordinates (0-1)
        rel_x = (canvas_x - bounds_x) / bounds_w
        rel_y = (canvas_y - bounds_y) / bounds_h
        
        # Apply zoom/pan transformations
        zoom = self.state.view_state.zoom_scale
        offset_x, offset_y = self.state.view_state.drag_offset
        
        # Account for zoom and pan
        adj_x = (rel_x - 0.5) / zoom + 0.5 - (offset_x / (bounds_w * zoom))
        adj_y = (rel_y - 0.5) / zoom + 0.5 - (offset_y / (bounds_h * zoom))
        
        # Convert to image pixel coordinates
        img_w, img_h = self.state.selected_image.size
        pixel_x = adj_x * img_w
        pixel_y = adj_y * img_h
        
        return (pixel_x, pixel_y)
    
    def on_mouse_motion(self, event):
        """Handle mouse motion for brush cursor"""
        if self.state.view_state.tool_mode in (ToolMode.BRUSH, ToolMode.ERASER):
            self.update_brush_cursor(event.x, event.y)
        else:
            self.hide_brush_cursor()
    
    def update_brush_cursor(self, x, y):
        """Update brush cursor position and size"""
        # Hide old cursor
        if self.brush_cursor_id:
            self.canvas.delete(self.brush_cursor_id)
        
        # Get brush size (actual pixel size regardless of zoom)
        brush_size = self.state.view_state.brush_size
        
        # Calculate display size (brush size on screen, accounting for current display scale)
        display_size = brush_size * self.display_scale
        
        # Create cursor circle
        x1 = x - display_size // 2
        y1 = y - display_size // 2
        x2 = x + display_size // 2
        y2 = y + display_size // 2
        
        # Different colors for brush vs eraser
        if self.state.view_state.tool_mode == ToolMode.BRUSH:
            outline_color = SimpleModernColors.ACCENT_GREEN
            fill_color = SimpleModernColors.ACCENT_GREEN + "40"  # Semi-transparent
        else:  # ERASER
            outline_color = SimpleModernColors.ACCENT_ORANGE
            fill_color = SimpleModernColors.ACCENT_ORANGE + "40"  # Semi-transparent
        
        self.brush_cursor_id = self.canvas.create_oval(
            x1, y1, x2, y2,
            outline=outline_color, 
            fill=fill_color,
            width=2
        )
        self.cursor_visible = True
    
    def hide_brush_cursor(self):
        """Hide the brush cursor"""
        if self.brush_cursor_id and self.cursor_visible:
            self.canvas.delete(self.brush_cursor_id)
            self.brush_cursor_id = None
            self.cursor_visible = False
    
    def update_cursor_for_tool_change(self):
        """Update cursor when tool mode changes"""
        if self.state.view_state.tool_mode in (ToolMode.BRUSH, ToolMode.ERASER):
            # Set custom cursor for tools
            self.canvas.config(cursor="none")  # Hide default cursor
        else:
            # Reset to default cursor
            self.canvas.config(cursor="")
            self.hide_brush_cursor()
