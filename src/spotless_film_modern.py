#!/usr/bin/env python3
"""
Spotless Film - Modern Professional Version

A professional-grade macOS-style interface using CustomTkinter combined with
professional UI components for advanced dust removal workflow.
"""

import customtkinter as ctk
from tkinter import filedialog, messagebox
from tkinterdnd2 import TkinterDnD
import threading
from pathlib import Path
import sys
from PIL import Image, ImageTk
import numpy as np
import torch
import os
import time
from typing import Optional, List, Tuple

# Add current directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from dust_removal_state import DustRemovalState, ProcessingMode, ToolMode
from ui_components import SpotlessSidebar, SpotlessToolbar, ZoomControls
from professional_canvas import SpotlessCanvas
from image_processing import ImageProcessingService, LamaInpainter, BrushTools, ProcessingTask, UNet
from simple_modern_theme import SimpleModernTheme
try:
    from gl_image_view import GLImageView, OPENGL_AVAILABLE, GL_IMPORT_ERROR
except Exception as e:
    OPENGL_AVAILABLE = False
    GL_IMPORT_ERROR = str(e)

# Set appearance and theme
ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("blue")

class SpotlessFilmModern:
    """Modern professional Spotless Film application with macOS-style UI"""
    
    def __init__(self):
        # Create main window with drag-and-drop support
        self.root = TkinterDnD.Tk()
        self.root.title("✨ Spotless Film - AI-Powered Film Restoration")
        self.root.geometry("1400x900")
        self.root.minsize(1000, 700)
        
        # Initialize state
        self.state = DustRemovalState(self.root)
        # Preview (downscaled) images for faster display
        self.preview_selected_image = None
        self.preview_processed_image = None
        # Split view caches
        self._split_cached_size = None
        self._split_resized_original = None
        self._split_resized_processed = None
        self._split_cached_signature = None
        
        # Initialize split view position
        self.split_position = 0.5  # Default to middle
        
        # Apply professional theme (skip for CustomTkinter compatibility)
        # self.theme = SimpleModernTheme(self.root)
        
        # Processing components
        self.lama_inpainter: Optional[LamaInpainter] = None
        self.processing_task: Optional[ProcessingTask] = None
        
        # Callback dictionary for UI components
        self.callbacks = {
            'import_image': self.import_image,
            'detect_dust': self.detect_dust,
            'remove_dust': self.remove_dust,
            'export_image': self.export_image,
            'threshold_changed': self.on_threshold_changed,
            'handle_drop': self.handle_file_drop,
            'eraser_click': self.apply_eraser_at_point,
            'brush_click': self.apply_brush_at_point
        }
        
        # Setup UI
        self.setup_ui()
        
        # Load models
        self.load_models_async()
        
        # Setup keyboard shortcuts
        self.setup_keyboard_shortcuts()
        
        print("✨ Spotless Film (Modern Professional) initialized")
    
    def setup_ui(self):
        """Setup the professional three-pane interface"""
        # Main container with CustomTkinter styling
        self.main_frame = ctk.CTkFrame(self.root, corner_radius=0, fg_color="#1E1E1E")
        self.main_frame.pack(fill='both', expand=True)
        
        # Create three-pane layout using grid
        self.main_frame.grid_columnconfigure(1, weight=1)
        self.main_frame.grid_rowconfigure(0, weight=1)
        
        # Left sidebar (CustomTkinter styled)
        self.setup_modern_sidebar()
        
        # Center panel with toolbar and canvas
        self.setup_center_panel()
        
        # Status bar
        self.setup_status_bar()
        
        # Add observer for state changes
        self.state.add_observer(self.update_ui)
    
    def setup_modern_sidebar(self):
        """Setup the modern CustomTkinter sidebar matching macOS design"""
        # Sidebar frame with macOS-style dark background
        self.sidebar_frame = ctk.CTkFrame(self.main_frame, width=280, corner_radius=0, 
                                         fg_color="#2A2A2A")
        self.sidebar_frame.grid(row=0, column=0, sticky="nsew", padx=(0, 1))
        self.sidebar_frame.grid_rowconfigure(10, weight=1)  # Empty space
        self.sidebar_frame.grid_propagate(False)
        
        # Create macOS-style sidebar content
        self.create_macos_sidebar_content()
    
    def create_macos_sidebar_content(self):
        """Create macOS-style sidebar content with collapsible sections"""
        # App header with icon
        header_frame = ctk.CTkFrame(self.sidebar_frame, fg_color="transparent")
        header_frame.grid(row=0, column=0, sticky="ew", padx=20, pady=(20, 10))
        
        # App icon and title
        title_label = ctk.CTkLabel(header_frame, text="✨ Dust Remover", 
                                  font=ctk.CTkFont(size=18, weight="bold"))
        title_label.pack(anchor="w")
        
        subtitle_label = ctk.CTkLabel(header_frame, text="AI-powered film restoration",
                                     font=ctk.CTkFont(size=11), text_color="#888888")
        subtitle_label.pack(anchor="w", pady=(2, 0))
        
        # Import section (collapsible)
        self.create_collapsible_section("Import", 1, self.create_import_section)
        
        # Detection section (collapsible)
        self.create_collapsible_section("Detection", 2, self.create_detection_section)
        
        # Dust Removal section (collapsible)
        self.create_collapsible_section("Dust Removal", 3, self.create_removal_section)
    
    def create_collapsible_section(self, title, row, content_creator):
        """Create a collapsible section matching macOS design"""
        # Section frame
        section_frame = ctk.CTkFrame(self.sidebar_frame, fg_color="transparent")
        section_frame.grid(row=row, column=0, sticky="ew", padx=15, pady=(10, 0))
        
        # Header button (clickable to expand/collapse)
        header_btn = ctk.CTkButton(section_frame, text=f"▼ {title}",
                                  font=ctk.CTkFont(size=13, weight="bold"),
                                  fg_color="transparent", text_color="#CCCCCC",
                                  hover_color="#3A3A3A", anchor="w", height=30)
        header_btn.pack(fill="x")
        
        # Content frame
        content_frame = ctk.CTkFrame(section_frame, fg_color="transparent")
        content_frame.pack(fill="x", pady=(5, 0))
        
        # Store reference for toggling
        setattr(self, f"{title.lower().replace(' ', '_')}_content", content_frame)
        setattr(self, f"{title.lower().replace(' ', '_')}_expanded", True)
        
        # Create content
        content_creator(content_frame)
        
        # Setup toggle functionality
        def toggle_section():
            current_state = getattr(self, f"{title.lower().replace(' ', '_')}_expanded")
            new_state = not current_state
            setattr(self, f"{title.lower().replace(' ', '_')}_expanded", new_state)
            
            header_btn.configure(text=f"{'▼' if new_state else '▶'} {title}")
            
            if new_state:
                content_frame.pack(fill="x", pady=(5, 0))
            else:
                content_frame.pack_forget()
        
        header_btn.configure(command=toggle_section)
    
    def create_import_section(self, parent):
        """Create import section content matching macOS design"""
        # Status indicator
        self.import_status_frame = ctk.CTkFrame(parent, fg_color="transparent")
        self.import_status_frame.pack(fill="x", pady=(0, 10))
        
        self.import_status_label = ctk.CTkLabel(self.import_status_frame, text="● Image Loaded",
                                               font=ctk.CTkFont(size=12), text_color="#4CAF50")
        # Initially hidden - will show when image is loaded
        
        # Image info
        self.image_info_frame = ctk.CTkFrame(parent, fg_color="transparent")
        self.image_info_frame.pack(fill="x", pady=(0, 10))
        
        self.size_label = ctk.CTkLabel(self.image_info_frame, text="Size:",
                                      font=ctk.CTkFont(size=10), text_color="#888888")
        
        self.colorspace_label = ctk.CTkLabel(self.image_info_frame, text="Color Space:",
                                           font=ctk.CTkFont(size=10), text_color="#888888")
        
        # Choose File button
        self.import_btn = ctk.CTkButton(parent, text="📁 Choose File",
                                       command=self.safe_import_image,
                                       font=ctk.CTkFont(size=12),
                                       height=32, fg_color="#4A4A4A",
                                       hover_color="#5A5A5A")
        self.import_btn.pack(fill="x", pady=(0, 5))
        self._importing = False
    
    def create_detection_section(self, parent):
        """Create detection section content matching macOS design"""
        # Detect button
        self.detect_btn = ctk.CTkButton(parent, text="🔍 Detect Dust",
                                       command=self.detect_dust,
                                       font=ctk.CTkFont(size=12),
                                       height=32, state="disabled",
                                       fg_color="#4A4A4A", hover_color="#5A5A5A")
        self.detect_btn.pack(fill="x", pady=(0, 15))

        # Threshold container (used for show/hide like Swift UI)
        self.threshold_frame = ctk.CTkFrame(parent, fg_color="transparent")
        self.threshold_frame.pack(fill="x", pady=(0, 0))

        # Sensitivity header with live value
        header_row = ctk.CTkFrame(self.threshold_frame, fg_color="transparent")
        header_row.pack(fill="x")
        sensitivity_label = ctk.CTkLabel(header_row, text="🎯 Sensitivity",
                                        font=ctk.CTkFont(size=12, weight="bold"))
        sensitivity_label.pack(side="left")
        self.threshold_value_label = ctk.CTkLabel(header_row, text=f"{self.state.processing_state.threshold:.3f}",
                                                 font=ctk.CTkFont(size=11), text_color="#CCCCCC")
        self.threshold_value_label.pack(side="right")

        # Sensitivity slider with labels
        slider_frame = ctk.CTkFrame(self.threshold_frame, fg_color="transparent")
        slider_frame.pack(fill="x", pady=(0, 5))

        # Labels for slider
        labels_frame = ctk.CTkFrame(slider_frame, fg_color="transparent")
        labels_frame.pack(fill="x")
        less_label = ctk.CTkLabel(labels_frame, text="Less Sensitive",
                                 font=ctk.CTkFont(size=9), text_color="#888888")
        less_label.pack(side="left")
        more_label = ctk.CTkLabel(labels_frame, text="More Sensitive",
                                 font=ctk.CTkFont(size=9), text_color="#888888")
        more_label.pack(side="right")

        # Slider
        self.threshold_slider = ctk.CTkSlider(slider_frame, from_=0.001, to=0.05,
                                             command=self.on_threshold_changed,
                                             number_of_steps=50)
        self.threshold_slider.set(float(self.state.processing_state.threshold))
        self.threshold_slider.pack(fill="x", pady=(5, 0))

        # Helper text
        help_label = ctk.CTkLabel(self.threshold_frame, text="Adjust to fine-tune dust detection",
                                 font=ctk.CTkFont(size=9), text_color="#666666")
        help_label.pack(anchor="w", pady=(5, 0))
    
    def create_removal_section(self, parent):
        """Create dust removal section content matching macOS design"""
        # Remove button
        self.remove_btn = ctk.CTkButton(parent, text="🧹 Remove Dust",
                                       command=self.remove_dust,
                                       font=ctk.CTkFont(size=12),
                                       height=32, state="disabled",
                                       fg_color="#4A4A4A", hover_color="#5A5A5A")
        self.remove_btn.pack(fill="x", pady=(0, 10))
        
        # Processing time display
        self.processing_time_frame = ctk.CTkFrame(parent, fg_color="transparent")
        self.processing_time_frame.pack(fill="x")
        
        time_title = ctk.CTkLabel(self.processing_time_frame, text="Processing Time:",
                                 font=ctk.CTkFont(size=10), text_color="#888888")
        time_title.pack(anchor="w")
        
        self.processing_time_label = ctk.CTkLabel(self.processing_time_frame, text="0.00s",
                                                 font=ctk.CTkFont(size=12), text_color="#CCCCCC")
        self.processing_time_label.pack(anchor="w")
    
    def setup_center_panel(self):
        """Setup the center panel with toolbar and professional canvas"""
        # Center frame
        self.center_frame = ctk.CTkFrame(self.main_frame, corner_radius=0, fg_color="#2A2A2A")
        self.center_frame.grid(row=0, column=1, sticky="nsew", padx=(1, 0))
        self.center_frame.grid_columnconfigure(0, weight=1)
        self.center_frame.grid_rowconfigure(1, weight=1)
        
        # Professional toolbar (converted to CustomTkinter)
        self.setup_modern_toolbar()
        
        # Canvas area frame
        self.canvas_frame = ctk.CTkFrame(self.center_frame, corner_radius=0)
        self.canvas_frame.grid(row=1, column=0, sticky="nsew")
        self.canvas_frame.grid_columnconfigure(0, weight=1)
        self.canvas_frame.grid_rowconfigure(0, weight=1)  # Canvas row (expandable)
        self.canvas_frame.grid_rowconfigure(1, weight=0)  # Zoom controls row (fixed height)
        
        # Simple CustomTkinter canvas
        canvas_container = ctk.CTkFrame(self.canvas_frame, fg_color="transparent")
        canvas_container.grid(row=0, column=0, sticky="nsew", padx=10, pady=10)
        canvas_container.grid_columnconfigure(0, weight=1)
        canvas_container.grid_rowconfigure(0, weight=1)
        
        # Prefer OpenGL viewer when available, fallback to Canvas
        self.use_gl = OPENGL_AVAILABLE
        print(f"[GL] OPENGL_AVAILABLE={OPENGL_AVAILABLE}; import_error={GL_IMPORT_ERROR}")
        if self.use_gl:
            try:
                print("[GL] Initializing GLImageView…")
                self.gl_view = GLImageView(canvas_container, width=800, height=600)
                self.gl_view.grid(row=0, column=0, sticky="nsew")
                print("[GL] GLImageView initialized")
            except Exception as e:
                self.use_gl = False
                print(f"[GL] Failed to init GLImageView, falling back to Canvas: {e}")
        if not self.use_gl:
            print("[GL] Using Tk canvas fallback")
            # Create simple canvas for image display (darker background to match macOS)
            self.canvas = ctk.CTkCanvas(canvas_container, bg="#1E1E1E", highlightthickness=0)
            self.canvas.grid(row=0, column=0, sticky="nsew")
        
        # Bind canvas events
        if not self.use_gl:
            self.canvas.bind('<Configure>', self.on_canvas_resize)
            self.canvas.bind('<Button-1>', self.on_canvas_click)
            self.canvas.bind('<B1-Motion>', self.on_canvas_drag)
            self.canvas.bind('<ButtonRelease-1>', self.on_canvas_release)
            self.canvas.bind('<MouseWheel>', self.on_mouse_wheel)
            self.canvas.bind('<Button-4>', self.on_mouse_wheel)  # Linux scroll up
            self.canvas.bind('<Button-5>', self.on_mouse_wheel)  # Linux scroll down
            self.canvas.bind('<Motion>', self.on_mouse_motion)  # For brush cursor
        
        # Initialize zoom/pan state (kept in central state)
        self.is_panning = False
        self.last_mouse_pos = None
        if not self.use_gl:
            self.canvas.focus_set()  # Allow canvas to receive key events
        
        # Brush cursor state
        self.brush_cursor_id = None
        self.cursor_visible = False
        
        # Throttle/quality controls for zoom rendering on Tk canvas
        self._zoom_redraw_job = None
        self._zoom_finalize_delay_ms = 120
        self._current_resample = None  # None => high quality (LANCZOS); otherwise temporary
        
        # Canvas item handles for fast pan
        self.image_item_id = None
        self.overlay_item_id = None
        
        # Show welcome message or GL clear
        if not self.use_gl:
            self.show_welcome_message()
        
        # Add zoom controls under the canvas
        self.setup_zoom_controls_under_canvas()
    
    def setup_zoom_controls_under_canvas(self):
        """Setup zoom controls under the canvas"""
        # Zoom controls frame under the canvas
        zoom_frame = ctk.CTkFrame(self.canvas_frame, height=50, corner_radius=8, 
                                 fg_color="#3A3A3A")
        zoom_frame.grid(row=1, column=0, sticky="ew", padx=10, pady=(0, 10))
        zoom_frame.grid_propagate(False)
        
        # Center the zoom controls
        controls_container = ctk.CTkFrame(zoom_frame, fg_color="transparent")
        controls_container.pack(expand=True)
        
        # Zoom out button
        self.zoom_out_btn = ctk.CTkButton(controls_container, text="−", width=35, height=35,
                                         command=self.zoom_out,
                                         font=ctk.CTkFont(size=16, weight="bold"),
                                         fg_color="#5A5A5A", hover_color="#6A6A6A")
        self.zoom_out_btn.pack(side="left", padx=5)
        
        # Zoom percentage display
        self.zoom_label = ctk.CTkLabel(controls_container, text="100%", width=60,
                                      font=ctk.CTkFont(size=12, family="Monaco"))
        self.zoom_label.pack(side="left", padx=5)
        
        # Zoom in button
        self.zoom_in_btn = ctk.CTkButton(controls_container, text="+", width=35, height=35,
                                        command=self.zoom_in,
                                        font=ctk.CTkFont(size=16, weight="bold"),
                                        fg_color="#5A5A5A", hover_color="#6A6A6A")
        self.zoom_in_btn.pack(side="left", padx=5)
        
        # Reset zoom button
        self.reset_zoom_btn = ctk.CTkButton(controls_container, text="⌂", width=35, height=35,
                                           command=self.reset_zoom,
                                           font=ctk.CTkFont(size=14),
                                           fg_color="#5A5A5A", hover_color="#6A6A6A")
        self.reset_zoom_btn.pack(side="left", padx=(10, 5))
    
    def setup_modern_toolbar(self):
        """Setup macOS-style toolbar with proper tools and overlay controls"""
        toolbar_frame = ctk.CTkFrame(self.center_frame, height=60, corner_radius=0, 
                                    fg_color="#3A3A3A")
        toolbar_frame.grid(row=0, column=0, sticky="ew", pady=(0, 1))
        toolbar_frame.grid_columnconfigure(1, weight=1)
        toolbar_frame.grid_propagate(False)
        
        # Left side tools (matching macOS layout)
        left_tools_frame = ctk.CTkFrame(toolbar_frame, fg_color="transparent")
        left_tools_frame.grid(row=0, column=0, sticky="w", padx=20, pady=10)
        
        # Eraser button (square style)
        self.eraser_btn = ctk.CTkButton(left_tools_frame, text="⬜\nEraser", width=80, height=50,
                                       command=self.toggle_eraser_tool,
                                       font=ctk.CTkFont(size=10),
                                       fg_color="#5A5A5A", hover_color="#6A6A6A")
        self.eraser_btn.pack(side="left", padx=(0, 8))
        
        # Brush button (square style)
        self.brush_btn = ctk.CTkButton(left_tools_frame, text="⬛\nBrush", width=80, height=50,
                                     command=self.toggle_brush_tool,
                                     font=ctk.CTkFont(size=10),
                                     fg_color="#5A5A5A", hover_color="#6A6A6A")
        self.brush_btn.pack(side="left", padx=(0, 8))
        
        # Brush size controls (conditional - only show when brush/eraser active)
        self.brush_size_frame = ctk.CTkFrame(left_tools_frame, fg_color="transparent")
        
        self.brush_size_label_text = ctk.CTkLabel(self.brush_size_frame, text="Size:", 
                                                 font=ctk.CTkFont(size=11), text_color="#CCCCCC")
        self.brush_size_label_text.pack(side="left")
        
        self.brush_size_slider = ctk.CTkSlider(self.brush_size_frame, from_=5, to=100, width=120,
                                              command=self.on_brush_size_changed)
        self.brush_size_slider.pack(side="left", padx=(8, 8))
        
        self.brush_size_value_label = ctk.CTkLabel(self.brush_size_frame, text="20px", width=40,
                                                  font=ctk.CTkFont(size=11, family="Monaco"), 
                                                  text_color="#CCCCCC")
        self.brush_size_value_label.pack(side="left")
        
        
        # Center view mode button (single cycling button)
        center_frame = ctk.CTkFrame(toolbar_frame, fg_color="transparent")
        center_frame.grid(row=0, column=1, pady=10)
        
        # Single cycling view mode button
        self.view_cycle_btn = ctk.CTkButton(center_frame, text="🔍 Single", width=120, height=35,
                                           command=self.cycle_view_mode,
                                           font=ctk.CTkFont(size=12),
                                           fg_color="#007AFF", hover_color="#0051D0")
        self.view_cycle_btn.pack(side="left", padx=2)
    
    def cycle_view_mode(self):
        """Cycle through view modes"""
        modes = [ProcessingMode.SINGLE, ProcessingMode.SIDE_BY_SIDE, ProcessingMode.SPLIT_SLIDER]
        current_index = modes.index(self.state.view_state.processing_mode)
        next_mode = modes[(current_index + 1) % len(modes)]
        self.set_view_mode(next_mode)
        
        # Update button text
        mode_text = {
            ProcessingMode.SINGLE: "🔍 Single",
            ProcessingMode.SIDE_BY_SIDE: "🔄 Side by Side",
            ProcessingMode.SPLIT_SLIDER: "✂️ Split View"
        }
        self.view_cycle_btn.configure(text=mode_text[next_mode])
    
    def toggle_eraser_tool(self):
        """Toggle eraser tool"""
        if self.state.view_state.tool_mode == ToolMode.ERASER:
            self.state.set_tool_mode(ToolMode.NONE)
            self.eraser_btn.configure(text="⬜\nEraser", fg_color="#5A5A5A")
            self.brush_size_frame.pack_forget()
        else:
            self.state.set_tool_mode(ToolMode.ERASER)
            self.eraser_btn.configure(text="✅\nEraser", fg_color="#FF6B35")
            self.brush_btn.configure(text="⬛\nBrush", fg_color="#5A5A5A")
            self.brush_size_frame.pack(side="left", padx=(20, 0))
        
        # Update cursor
        self.update_cursor_for_tool_change()
    
    def toggle_brush_tool(self):
        """Toggle brush tool"""
        if self.state.view_state.tool_mode == ToolMode.BRUSH:
            self.state.set_tool_mode(ToolMode.NONE)
            self.brush_btn.configure(text="⬛\nBrush", fg_color="#5A5A5A")
            self.brush_size_frame.pack_forget()
        else:
            self.state.set_tool_mode(ToolMode.BRUSH)
            self.brush_btn.configure(text="✅\nBrush", fg_color="#4CAF50")
            self.eraser_btn.configure(text="⬜\nEraser", fg_color="#5A5A5A")
            self.brush_size_frame.pack(side="left", padx=(20, 0))
        
        # Update cursor
        self.update_cursor_for_tool_change()
    
    def on_brush_size_changed(self, value):
        """Handle brush size change"""
        size = int(float(value))
        self.state.view_state.brush_size = size
        self.brush_size_value_label.configure(text=f"{size}px")
        
        # Right side overlay controls
        right_controls_frame = ctk.CTkFrame(toolbar_frame, fg_color="transparent")
        right_controls_frame.grid(row=0, column=2, sticky="e", padx=20, pady=10)
        
        # Overlay toggle and controls
        overlay_frame = ctk.CTkFrame(right_controls_frame, fg_color="transparent")
        overlay_frame.pack(side="right")
        
        # Timer display (matching macOS)
        self.timer_label = ctk.CTkLabel(overlay_frame, text="⏱ 2.47s",
                                       font=ctk.CTkFont(size=12), text_color="#CCCCCC")
        self.timer_label.pack(side="right", padx=(0, 20))
        
        # Overlay toggle button
        self.overlay_toggle_btn = ctk.CTkButton(overlay_frame, text="👁 Overlay", width=80, height=35,
                                              command=self.toggle_overlay,
                                              font=ctk.CTkFont(size=11),
                                              fg_color="#007AFF", hover_color="#0051D0")
        self.overlay_toggle_btn.pack(side="right", padx=(0, 10))
        
        # Opacity section
        opacity_frame = ctk.CTkFrame(overlay_frame, fg_color="transparent")
        opacity_frame.pack(side="right", padx=(0, 10))
        
        opacity_label = ctk.CTkLabel(opacity_frame, text="Opacity",
                                    font=ctk.CTkFont(size=10), text_color="#888888")
        opacity_label.pack()
        
        # Opacity slider frame
        opacity_slider_frame = ctk.CTkFrame(opacity_frame, fg_color="transparent")
        opacity_slider_frame.pack(fill="x")
        
        # Opacity slider (matching macOS design)
        self.opacity_slider = ctk.CTkSlider(opacity_slider_frame, from_=0.0, to=1.0,
                                           command=self.on_opacity_changed,
                                           number_of_steps=20, width=100)
        self.opacity_slider.set(0.5)  # 50% default
        self.opacity_slider.pack(side="left")
        
        # Opacity percentage
        self.opacity_label = ctk.CTkLabel(opacity_slider_frame, text="50%",
                                         font=ctk.CTkFont(size=10), text_color="#CCCCCC")
        self.opacity_label.pack(side="right", padx=(5, 0))
        
        # Initialize overlay state
        self.overlay_visible = True
        self.overlay_opacity = 0.5  # 50% default
        
        # Initialize zoom UI to 100%
        self.update_zoom_ui()
    
    def toggle_overlay(self):
        """Toggle dust overlay visibility"""
        self.overlay_visible = not self.overlay_visible
        if hasattr(self.state, 'view_state'):
            self.state.view_state.hide_detections = not self.overlay_visible
        
        # Update button appearance
        if self.overlay_visible:
            self.overlay_toggle_btn.configure(text="👁 Overlay", fg_color="#007AFF")
        else:
            self.overlay_toggle_btn.configure(text="👁 Hidden", fg_color="#666666")
        
        # Refresh display
        self.display_image()
    
    def on_opacity_changed(self, value):
        """Handle opacity slider changes"""
        opacity_percent = int(value * 100)
        self.opacity_label.configure(text=f"{opacity_percent}%")
        
        # Store opacity for overlay rendering
        self.overlay_opacity = value
        
        # Refresh display if overlay is visible
        if self.overlay_visible:
            self.display_image()
    
    
    def setup_status_bar(self):
        """Setup modern status bar"""
        self.status_frame = ctk.CTkFrame(self.main_frame, height=30, corner_radius=0)
        self.status_frame.grid(row=1, column=0, columnspan=2, sticky="ew")
        self.status_frame.grid_columnconfigure(1, weight=1)
        self.status_frame.grid_propagate(False)
        
        # Device info
        device_text = f"Device: {self.state.device}"
        self.device_label = ctk.CTkLabel(self.status_frame, text=device_text,
                                        font=ctk.CTkFont(size=10), text_color="gray60")
        self.device_label.grid(row=0, column=0, sticky="w", padx=10)
        
        # Status message
        self.status_label = ctk.CTkLabel(self.status_frame, text="Ready - Import an image to begin",
                                        font=ctk.CTkFont(size=10), text_color="gray70")
        self.status_label.grid(row=0, column=1, sticky="w", padx=10)
        
        # LaMa status
        self.lama_label = ctk.CTkLabel(self.status_frame, text="LaMa: Loading...",
                                      font=ctk.CTkFont(size=10), text_color="gray60")
        self.lama_label.grid(row=0, column=2, sticky="e", padx=10)
    
    def show_welcome_message(self):
        """Show welcome message on canvas"""
        self.canvas.delete('all')
        canvas_width = self.canvas.winfo_width() or 800
        canvas_height = self.canvas.winfo_height() or 600
        
        center_x = canvas_width // 2
        center_y = canvas_height // 2
        
        # Welcome text with modern styling
        self.canvas.create_text(center_x, center_y - 60, text="✨",
                               font=("Helvetica", 64), fill="#4a9eff")
        self.canvas.create_text(center_x, center_y, text="Spotless Film",
                               font=("Helvetica", 24, "bold"), fill="white")
        self.canvas.create_text(center_x, center_y + 35, text="Drag and drop an image here to begin",
                               font=("Helvetica", 14), fill="gray")
        self.canvas.create_text(center_x, center_y + 65, text="or use the Import button",
                               font=("Helvetica", 12), fill="gray")
        self.canvas.create_text(center_x, center_y + 95, text="Supported formats: PNG, JPEG, TIFF, BMP",
                               font=("Helvetica", 10), fill="#666666")
    
    def on_canvas_resize(self, event):
        """Handle canvas resize"""
        if self.use_gl:
            # GL view resizes automatically; just redraw
            if hasattr(self, 'gl_view'):
                self.gl_view.after_idle(self.gl_view.redraw)
        else:
            if hasattr(self, 'photo') and self.state.selected_image:
                self.display_image()
            else:
                self.show_welcome_message()
    
    def on_canvas_click(self, event):
        """Handle canvas click for split view interaction"""
        # Tool interactions first
        if self.state.view_state.tool_mode == ToolMode.ERASER and self.state.dust_mask is not None:
            cw, ch = self.canvas.winfo_width(), self.canvas.winfo_height()
            self.apply_eraser_at_point((event.x, event.y), cw, ch)
            return
        if self.state.view_state.tool_mode == ToolMode.BRUSH and self.state.dust_mask is not None:
            cw, ch = self.canvas.winfo_width(), self.canvas.winfo_height()
            self.apply_brush_at_point((event.x, event.y), cw, ch)
            return

        # Begin panning only when space is held (even if zoomed)
        if self.state.view_state.space_key_pressed:
            self.is_panning = True
            self.last_mouse_pos = (event.x, event.y)
            return

        if self.state.view_state.processing_mode == ProcessingMode.SPLIT_SLIDER and hasattr(self, 'photo_split'):
            canvas_width = self.canvas.winfo_width()
            canvas_height = self.canvas.winfo_height()
            img_left, img_top, img_w, img_h = self._get_split_bounds(canvas_width, canvas_height)
            if img_w > 0 and img_h > 0 and img_left <= event.x <= img_left + img_w and img_top <= event.y <= img_top + img_h:
                relative_x = (event.x - img_left) / float(img_w)
                self.split_position = max(0.05, min(0.95, relative_x))
                self.display_image()
    
    def on_canvas_drag(self, event):
        """Handle canvas drag for split view interaction or panning when zoomed"""
        # Tool drags
        if self.state.view_state.tool_mode == ToolMode.ERASER and self.state.dust_mask is not None:
            cw, ch = self.canvas.winfo_width(), self.canvas.winfo_height()
            self.apply_eraser_at_point((event.x, event.y), cw, ch)
            return
        if self.state.view_state.tool_mode == ToolMode.BRUSH and self.state.dust_mask is not None:
            cw, ch = self.canvas.winfo_width(), self.canvas.winfo_height()
            self.apply_brush_at_point((event.x, event.y), cw, ch)
            return

        # Panning when zoomed or space pressed
        if self.is_panning and self.last_mouse_pos is not None:
            dx = event.x - self.last_mouse_pos[0]
            dy = event.y - self.last_mouse_pos[1]
            off_x, off_y = self.state.view_state.drag_offset
            self.state.view_state.drag_offset = (off_x + dx, off_y + dy)
            self.last_mouse_pos = (event.x, event.y)
            # Move existing canvas items without re-rendering
            if self.image_item_id is not None:
                canvas_w = self.canvas.winfo_width() or 1
                canvas_h = self.canvas.winfo_height() or 1
                center_x = canvas_w // 2 + int(self.state.view_state.drag_offset[0])
                center_y = canvas_h // 2 + int(self.state.view_state.drag_offset[1])
                self.canvas.coords(self.image_item_id, center_x, center_y)
                if self.overlay_item_id is not None:
                    self.canvas.coords(self.overlay_item_id, center_x, center_y)
            return

        # Otherwise, handle split slider dragging directly
        if self.state.view_state.processing_mode == ProcessingMode.SPLIT_SLIDER and hasattr(self, 'photo_split'):
            canvas_width = self.canvas.winfo_width()
            canvas_height = self.canvas.winfo_height()
            img_left, img_top, img_w, img_h = self._get_split_bounds(canvas_width, canvas_height)
            if img_w > 0 and img_h > 0 and img_left <= event.x <= img_left + img_w and img_top <= event.y <= img_top + img_h:
                relative_x = (event.x - img_left) / float(img_w)
                self.split_position = max(0.05, min(0.95, relative_x))
                self.display_image()
    
    def display_image(self, image=None):
        """Display image on canvas based on current view mode"""
        try:
            # Get canvas size
            if self.use_gl:
                canvas_width = self.gl_view.width
                canvas_height = self.gl_view.height
            else:
                canvas_width = self.canvas.winfo_width()
                canvas_height = self.canvas.winfo_height()
            
            if canvas_width <= 1 or canvas_height <= 1:
                return
            
            # Clear canvas first
            self.canvas.delete('all')
            
            # Handle different view modes
            mode = self.state.view_state.processing_mode
            print(f"🖼️ Displaying in {mode} mode")
            
            if mode == ProcessingMode.SINGLE:
                if self.use_gl:
                    self.display_single_view_gl(canvas_width, canvas_height)
                else:
                    self.display_single_view(canvas_width, canvas_height, image)
            elif mode == ProcessingMode.SIDE_BY_SIDE:
                self.display_side_by_side_view(canvas_width, canvas_height)
            elif mode == ProcessingMode.SPLIT_SLIDER:
                self.display_split_view(canvas_width, canvas_height)
            
        except Exception as e:
            print(f"Error displaying image: {e}")
    
    def display_single_view(self, canvas_width, canvas_height, image=None):
        """Display single image view"""
        # Smart image selection - prefer processed image if available
        if image is None:
            if self.state.processed_image:
                image = self.preview_processed_image or self.state.processed_image
                print("🖼️ Single view: Using processed image")
            else:
                image = self.preview_selected_image or self.state.selected_image
                print("🖼️ Single view: Using selected image")
        else:
            print(f"🖼️ Single view: Using provided image")
        
        if not image:
            return
        
        # Create working image from chosen source (preview/full)
        display_image = image.copy()
        
        # Determine if we're showing processed (for info; we now allow overlay on both)
        is_processed_display = (
            (self.state.processed_image is not None) and 
            (image is self.preview_processed_image or image is self.state.processed_image)
        )
        
        # Compute base fit size within margins
        margin = 40
        base_w = canvas_width - margin
        base_h = canvas_height - margin
        img_ratio = display_image.size[0] / display_image.size[1]
        canvas_ratio = base_w / base_h if base_h > 0 else 1.0
        if img_ratio > canvas_ratio:
            fitted_w = base_w
            fitted_h = int(base_w / img_ratio)
        else:
            fitted_h = base_h
            fitted_w = int(base_h * img_ratio)

        # Apply zoom
        zoom = max(1.0, float(self.state.view_state.zoom_scale))
        disp_w = max(1, int(fitted_w * zoom))
        disp_h = max(1, int(fitted_h * zoom))

        # Choose resampling quality (interactive zoom uses faster filter)
        resample = self._current_resample or Image.Resampling.LANCZOS
        display_image = display_image.resize((disp_w, disp_h), resample)

        # Calculate position with pan offset
        off_x, off_y = self.state.view_state.drag_offset
        center_x = canvas_width // 2 + int(off_x)
        center_y = canvas_height // 2 + int(off_y)

        # Convert to PhotoImage
        self.photo = ImageTk.PhotoImage(display_image)

        # Display image centered with pan offset
        self.image_item_id = self.canvas.create_image(center_x, center_y, image=self.photo)

        # If overlay visible, render as a separate canvas image for speed
        if (self.state.dust_mask and getattr(self, 'overlay_visible', True)):
            overlay_img = self.create_overlay_layer((disp_w, disp_h))
            if overlay_img is not None:
                self.photo_overlay = ImageTk.PhotoImage(overlay_img)
                self.overlay_item_id = self.canvas.create_image(center_x, center_y, image=self.photo_overlay)
            else:
                self.overlay_item_id = None
        else:
            self.overlay_item_id = None

        # Store bounds for hit-testing/brush mapping (top-left, size)
        self.image_item_bounds = (center_x - disp_w // 2, center_y - disp_h // 2, disp_w, disp_h)
    
    def display_side_by_side_view(self, canvas_width, canvas_height):
        """Display side-by-side comparison view"""
        if not self.state.selected_image:
            return
        
        print("🖼️ Rendering side-by-side view")
        
        # Calculate dimensions for each side
        half_width = canvas_width // 2
        margin = 20
        
        # Original image (left side)
        original_image = self.state.selected_image.copy()
        
        # Add dust overlay to original if available and overlay is visible
        if self.state.dust_mask and getattr(self, 'overlay_visible', True):
            # Use fast overlay at display size
            pass
        
        # Resize original image
        original_image.thumbnail((half_width - margin, canvas_height - 40), Image.Resampling.LANCZOS)
        self.photo_left = ImageTk.PhotoImage(original_image)
        
        # Display original on left
        left_x = half_width // 2
        self.canvas.create_image(left_x, canvas_height // 2, image=self.photo_left)
        self.canvas.create_text(left_x, 20, text="Original", fill="white", font=("Arial", 12, "bold"))
        
        # Processed image (right side) if available
        if self.state.processed_image:
            processed_image = self.state.processed_image.copy()
            processed_image.thumbnail((half_width - margin, canvas_height - 40), Image.Resampling.LANCZOS)
            self.photo_right = ImageTk.PhotoImage(processed_image)
            
            # Display processed on right
            right_x = half_width + (half_width // 2)
            self.canvas.create_image(right_x, canvas_height // 2, image=self.photo_right)
            self.canvas.create_text(right_x, 20, text="Processed", fill="white", font=("Arial", 12, "bold"))
        else:
            # Show placeholder text
            right_x = half_width + (half_width // 2)
            self.canvas.create_text(right_x, canvas_height // 2, text="Process image to see result", 
                                  fill="gray", font=("Arial", 14))
        
        # Draw separator line
        self.canvas.create_line(half_width, 0, half_width, canvas_height, fill="white", width=2)
    
    def display_split_view(self, canvas_width, canvas_height):
        """Display split slider view with proper image compositing"""
        if not self.state.selected_image:
            return
        
        print("🖼️ Rendering split view")
        
        # If no processed image, show single view
        if not self.state.processed_image:
            self.display_single_view(canvas_width, canvas_height)
            return
        
        # Choose preview images for performance
        base_original = self.preview_selected_image or self.state.selected_image
        base_processed = self.preview_processed_image or self.state.processed_image

        # Add dust overlay to original if visible (baked-in in split)
        if self.state.dust_mask and getattr(self, 'overlay_visible', True):
            base_original = self.create_overlay_image(base_original)

        # Calculate base fit size while maintaining aspect ratio
        display_width = canvas_width - 40
        display_height = canvas_height - 40
        img_ratio = base_original.size[0] / base_original.size[1]
        canvas_ratio = display_width / display_height
        if img_ratio > canvas_ratio:
            fit_w = display_width
            fit_h = int(display_width / img_ratio)
        else:
            fit_h = display_height
            fit_w = int(display_height * img_ratio)

        # Apply zoom
        zoom = max(1.0, float(self.state.view_state.zoom_scale))
        new_width = max(1, int(fit_w * zoom))
        new_height = max(1, int(fit_h * zoom))

        # Build a signature so cache invalidates on content changes (mask/process/opacity)
        overlay_flag = bool(self.state.dust_mask and getattr(self, 'overlay_visible', True))
        mask_token = id(self.state.dust_mask) if overlay_flag else None
        orig_token = id(base_original)
        proc_token = id(base_processed)
        cache_size = (new_width, new_height)
        signature = (cache_size, orig_token, proc_token, overlay_flag, mask_token, float(getattr(self, 'overlay_opacity', 0.5)))

        # Cache resized images for current size/content to make slider smooth
        if self._split_cached_signature != signature:
            resample = self._current_resample or Image.Resampling.LANCZOS
            self._split_resized_original = base_original.resize(cache_size, resample)
            self._split_resized_processed = base_processed.resize(cache_size, resample)
            self._split_cached_size = cache_size
            self._split_cached_signature = signature
        
        # Get split position (default to middle)
        split_position = getattr(self, 'split_position', 0.5)
        split_x_image = int(cache_size[0] * split_position)
        
        # Create composite image
        composite = Image.new('RGB', cache_size)
        
        # Left side: processed image
        if split_x_image > 0:
            left_crop = self._split_resized_processed.crop((0, 0, split_x_image, cache_size[1]))
            composite.paste(left_crop, (0, 0))
        
        # Right side: original image
        if split_x_image < cache_size[0]:
            right_crop = self._split_resized_original.crop((split_x_image, 0, cache_size[0], cache_size[1]))
            composite.paste(right_crop, (split_x_image, 0))
        
        # Convert to PhotoImage
        self.photo_split = ImageTk.PhotoImage(composite)
        
        # Calculate position to center the image
        display_x = canvas_width // 2
        display_y = canvas_height // 2
        
        # Display the composite image
        split_item = self.canvas.create_image(display_x, display_y, image=self.photo_split)
        # Store bounds for tool hit-testing in split view
        self.image_item_bounds = (display_x - (cache_size[0] // 2), display_y - (cache_size[1] // 2), cache_size[0], cache_size[1])
        
        # Calculate split line position on canvas
        canvas_split_x = display_x - (cache_size[0] // 2) + split_x_image
        
        # Draw split line
        line_y1 = display_y - (cache_size[1] // 2)
        line_y2 = display_y + (cache_size[1] // 2)
        self.canvas.create_line(canvas_split_x, line_y1, canvas_split_x, line_y2, fill="white", width=3)
        
        # Add labels
        left_label_x = display_x - (cache_size[0] // 2) + (split_x_image // 2)
        right_label_x = canvas_split_x + ((display_x + (cache_size[0] // 2) - canvas_split_x) // 2)
        label_y = line_y1 + 20
        
        self.canvas.create_text(left_label_x, label_y, text="Processed", fill="white", font=("Arial", 10, "bold"))
        self.canvas.create_text(right_label_x, label_y, text="Original", fill="white", font=("Arial", 10, "bold"))

    def _get_split_bounds(self, canvas_width: int, canvas_height: int):
        """Return (left, top, width, height) of the split-view image rect on the canvas."""
        # Compute the same size math used by display_split_view
        base_original = self.preview_selected_image or self.state.selected_image
        if base_original is None:
            return (0, 0, 0, 0)
        display_width = canvas_width - 40
        display_height = canvas_height - 40
        img_ratio = base_original.size[0] / base_original.size[1]
        canvas_ratio = display_width / display_height
        if img_ratio > canvas_ratio:
            fit_w = display_width
            fit_h = int(display_width / img_ratio)
        else:
            fit_h = display_height
            fit_w = int(display_height * img_ratio)
        zoom = max(1.0, float(self.state.view_state.zoom_scale))
        new_w = max(1, int(fit_w * zoom))
        new_h = max(1, int(fit_h * zoom))
        left = (canvas_width - new_w) // 2
        top = (canvas_height - new_h) // 2
        return (left, top, new_w, new_h)
    
    def display_single_view_gl(self, canvas_width, canvas_height):
        """GL-backed single view rendering."""
        if not self.state.selected_image:
            return
        # Base image preference: processed if available
        base = (self.preview_processed_image or self.state.processed_image) if self.state.processed_image else (self.preview_selected_image or self.state.selected_image)
        overlay_img = None
        is_processed_display = (self.state.processed_image is not None) and (base is self.preview_processed_image or base is self.state.processed_image)
        if (self.state.dust_mask and getattr(self, 'overlay_visible', True) and not is_processed_display):
            # Provide an overlay RGBA the same size as base; GL scales it efficiently.
            overlay_img = self.create_overlay_layer(base.size)
        # Upload/update textures and draw
        self.gl_view.set_images(base, overlay_img)
        self.gl_view.set_view(self.state.view_state.zoom_scale, self.state.view_state.drag_offset)
    
    def create_overlay_image(self, base_image):
        """Create image with dust overlay (matches Swift app visualization)"""
        try:
            print("🎨 Creating dust overlay...")
            
            # Convert base image to RGB if needed
            if base_image.mode != 'RGB':
                base_image = base_image.convert('RGB')
            
            # Get dust mask
            dust_mask = self.state.dust_mask
            if not dust_mask:
                return base_image
            
            # Ensure mask is same size as image
            if dust_mask.size != base_image.size:
                dust_mask = dust_mask.resize(base_image.size, Image.Resampling.NEAREST)
            
            # Convert to numpy arrays
            base_array = np.array(base_image).astype(np.float32)
            mask_array = np.array(dust_mask).astype(np.float32) / 255.0
            
            # Create colored overlay (red dust detection)
            overlay_color = np.array([255, 0, 0], dtype=np.float32)  # Red
            overlay_alpha = float(getattr(self, 'overlay_opacity', 0.5))
            
            # Apply overlay where mask is white (dust detected)
            for i in range(3):  # RGB channels
                base_array[:, :, i] = (base_array[:, :, i] * (1 - mask_array * overlay_alpha) + 
                                     overlay_color[i] * mask_array * overlay_alpha)
            
            # Convert back to image
            overlay_image = Image.fromarray(np.clip(base_array, 0, 255).astype(np.uint8))
            
            print("✅ Dust overlay created")
            return overlay_image
            
        except Exception as e:
            print(f"❌ Error creating overlay: {e}")
            return base_image

    def create_overlay_layer(self, display_size):
        """Fast path: build an RGBA overlay at display size only."""
        try:
            if not self.state.dust_mask:
                return None
            # Always base overlay on the full-res mask and scale to the current display size
            mask = self.state.dust_mask
            if mask.size != display_size:
                mask = mask.resize(display_size, Image.Resampling.NEAREST)
            mask_array = np.array(mask.convert('L'), dtype=np.uint8)
            alpha = float(getattr(self, 'overlay_opacity', 0.5))
            a = (mask_array.astype(np.float32) * alpha).clip(0, 255).astype(np.uint8)
            rgb = np.zeros((display_size[1], display_size[0], 3), dtype=np.uint8)
            rgb[:, :, 0] = mask_array  # red
            rgba = np.dstack([rgb, a])
            return Image.fromarray(rgba, 'RGBA')
        except Exception:
            return None

    # MARK: - Zoom / Pan Controls

    def zoom_in(self):
        """Zoom in using centralized state and refresh UI"""
        print(f"[UI] zoom_in from {self.state.view_state.zoom_scale:.3f}")
        self.state.zoom_in()
        self.update_zoom_ui()
        if self.state.selected_image:
            if self.use_gl:
                self.gl_view.set_view(self.state.view_state.zoom_scale, self.state.view_state.drag_offset)
            else:
                self.display_image()

    def zoom_out(self):
        """Zoom out using centralized state and refresh UI"""
        print(f"[UI] zoom_out from {self.state.view_state.zoom_scale:.3f}")
        self.state.zoom_out()
        self.update_zoom_ui()
        if self.state.selected_image:
            if self.use_gl:
                self.gl_view.set_view(self.state.view_state.zoom_scale, self.state.view_state.drag_offset)
            else:
                self.display_image()

    def reset_zoom(self):
        """Reset zoom and pan"""
        print("[UI] reset_zoom")
        self.state.reset_zoom()
        self.update_zoom_ui()
        if self.state.selected_image:
            if self.use_gl:
                self.gl_view.set_view(self.state.view_state.zoom_scale, self.state.view_state.drag_offset)
            else:
                self.display_image()

    def on_mouse_wheel(self, event):
        """Smooth, cursor-anchored zoom for wheel or pinch gestures"""
        if self.use_gl:
            # For GL view, reuse the same math, then push view to GL
            # Determine scroll direction/magnitude
            raw = 0
            if hasattr(event, 'delta') and event.delta:
                raw = event.delta
            elif hasattr(event, 'num'):
                raw = 120 if event.num == 4 else -120
            if raw == 0:
                return
            step = 1.10
            factor = step if raw > 0 else 1/step
            old_zoom = float(self.state.view_state.zoom_scale)
            new_zoom = max(1.0, min(5.0, old_zoom * factor))
            if abs(new_zoom - old_zoom) < 1e-3:
                return
            # Anchor at cursor (approximate since GL computes fit internally)
            off_x, off_y = self.state.view_state.drag_offset
            self.state.view_state.drag_offset = (off_x, off_y)
            self.state.view_state.zoom_scale = new_zoom
            self.update_zoom_ui()
            self.gl_view.set_view(self.state.view_state.zoom_scale, self.state.view_state.drag_offset)
            return
        # Determine scroll direction/magnitude (supports macOS/Windows/Linux)
        raw = 0
        if hasattr(event, 'delta') and event.delta:
            raw = event.delta
        elif hasattr(event, 'num'):
            raw = 120 if event.num == 4 else -120

        if raw == 0:
            return

        # Zoom factor with smoothing
        step = 1.10
        factor = step if raw > 0 else 1/step

        # Current zoom and clamp range
        old_zoom = float(self.state.view_state.zoom_scale)
        new_zoom = max(1.0, min(5.0, old_zoom * factor))
        if abs(new_zoom - old_zoom) < 1e-3:
            return

        # Cursor-anchored zoom: adjust pan so the point under cursor stays put
        cx, cy = event.x, event.y
        off_x, off_y = self.state.view_state.drag_offset
        # Translate from canvas center to apply offset relative to center
        canvas_w = self.canvas.winfo_width() or 1
        canvas_h = self.canvas.winfo_height() or 1
        center_x = canvas_w / 2 + off_x
        center_y = canvas_h / 2 + off_y
        # Vector from current image center to cursor
        vx = cx - center_x
        vy = cy - center_y
        # How that vector changes with zoom
        scale_ratio = new_zoom / max(1e-6, old_zoom)
        new_vx = vx * scale_ratio
        new_vy = vy * scale_ratio
        # Compute new offset so the cursor-target stays stationary
        new_center_x = cx - new_vx
        new_center_y = cy - new_vy
        self.state.view_state.drag_offset = (new_center_x - canvas_w / 2, new_center_y - canvas_h / 2)

        # During fast wheel, use faster resize for responsiveness
        if self._zoom_redraw_job is None:
            self._current_resample = Image.Resampling.BILINEAR

        # Commit zoom and refresh
        self.state.view_state.zoom_scale = new_zoom
        self.update_zoom_ui()
        self.display_image()

        # Schedule a high-quality redraw after the wheel stops
        if self._zoom_redraw_job is not None:
            try:
                self.root.after_cancel(self._zoom_redraw_job)
            except Exception:
                pass
        def _finalize_redraw():
            self._current_resample = None
            self.display_image()
            self._zoom_redraw_job = None
        self._zoom_redraw_job = self.root.after(self._zoom_finalize_delay_ms, _finalize_redraw)

    def on_canvas_release(self, event):
        """Handle mouse release, stop panning if needed"""
        self.is_panning = False
        self.last_mouse_pos = None
        # End brush stroke if any tool is active
        if self.state.view_state.tool_mode in (ToolMode.BRUSH, ToolMode.ERASER):
            self.state.end_brush_stroke()

    def update_zoom_ui(self):
        """Update zoom label and button states to reflect current zoom"""
        if hasattr(self, 'zoom_label'):
            percent = int(self.state.view_state.zoom_scale * 100)
            self.zoom_label.configure(text=f"{percent}%")
        if hasattr(self, 'zoom_out_btn'):
            self.zoom_out_btn.configure(state=("normal" if self.state.view_state.zoom_scale > 1.0 else "disabled"))
    
    def update_ui(self):
        """Update UI based on state changes"""
        # Keep zoom UI in sync with state changes
        self.update_zoom_ui()
        # Update button states
        has_image = self.state.selected_image is not None
        has_dust_mask = self.state.dust_mask is not None
        has_processed = self.state.processed_image is not None
        has_prediction = self.state.raw_prediction_mask is not None
        
        # Update button states
        if hasattr(self, 'detect_btn'):
            self.detect_btn.configure(state="normal" if has_image and not self.state.processing_state.is_detecting else "disabled")
        if hasattr(self, 'remove_btn'):
            self.remove_btn.configure(state="normal" if has_dust_mask and not self.state.processing_state.is_removing else "disabled")
        if hasattr(self, 'export_btn'):
            self.export_btn.configure(state="normal" if has_processed else "disabled")
        
        # Show/Hide threshold slider (matches Swift app behavior)
        if hasattr(self, 'threshold_frame'):
            if has_prediction:
                self.threshold_frame.pack(fill="x", padx=15, pady=(0, 15))
            else:
                self.threshold_frame.pack_forget()
        
        # Update import status and image info
        if hasattr(self, 'import_status_label') and has_image:
            self.import_status_label.pack(anchor="w")
            # Update image info
            if hasattr(self, 'size_label') and self.state.selected_image:
                size = self.state.selected_image.size
                self.size_label.configure(text=f"Size: {size[0]} x {size[1]}")
                self.size_label.pack(anchor="w")
            if hasattr(self, 'colorspace_label'):
                self.colorspace_label.configure(text="Color Space: NSCalibratedRGBColorSpace")
                self.colorspace_label.pack(anchor="w")
        elif hasattr(self, 'import_status_label'):
            self.import_status_label.pack_forget()
            if hasattr(self, 'size_label'):
                self.size_label.pack_forget()
            if hasattr(self, 'colorspace_label'):
                self.colorspace_label.pack_forget()
        
        # Update processing time
        if hasattr(self, 'processing_time_label') and hasattr(self.state.processing_state, 'processing_time'):
            if self.state.processing_state.processing_time > 0:
                time_text = f"{self.state.processing_state.processing_time:.2f}s"
                self.processing_time_label.configure(text=time_text)
        
        # Update toolbar timer
        if hasattr(self, 'timer_label') and hasattr(self.state.processing_state, 'processing_time'):
            if self.state.processing_state.processing_time > 0:
                time_text = f"⏱ {self.state.processing_state.processing_time:.2f}s"
                self.timer_label.configure(text=time_text)
        
        # Show/Hide export section  
        if hasattr(self, 'export_frame'):
            if has_processed:
                self.export_frame.grid(row=4, column=0, sticky="ew", padx=20, pady=(0, 15))
            else:
                self.export_frame.grid_forget()
        
        # Update toolbar button states if they exist
        if hasattr(self, 'view_cycle_btn'):
            self.update_tool_buttons()
        
        # Display current image
        if self.state.selected_image:
            self.display_image()
        
        # Update processing button text
        if hasattr(self, 'detect_btn'):
            if self.state.processing_state.is_detecting:
                self.detect_btn.configure(text="🔍  Detecting...")
            else:
                self.detect_btn.configure(text="🔍  Detect Dust")
        
        if hasattr(self, 'remove_btn'):        
            if self.state.processing_state.is_removing:
                self.remove_btn.configure(text="✨  Removing...")
            else:
                self.remove_btn.configure(text="✨  Remove Dust")
    

    def build_preview_image(self, image, long_side: int = 2048):
        """Create a downscaled preview with long side capped at 2K for fast display."""
        try:
            if image is None:
                return None
            w, h = image.size
            if max(w, h) <= long_side:
                return image.copy()
            if w >= h:
                new_w = long_side
                new_h = max(1, int(h * (long_side / float(w))))
            else:
                new_h = long_side
                new_w = max(1, int(w * (long_side / float(h))))
            return image.resize((new_w, new_h), Image.Resampling.LANCZOS)
        except Exception as e:
            print(f"Preview build failed: {e}")
            return image
    
    def update_tool_buttons(self):
        """Update tool button states"""
        tool_mode = self.state.view_state.tool_mode
        
        # Reset buttons
        self.brush_btn.configure(fg_color=("gray75", "gray25"))
        self.eraser_btn.configure(fg_color=("gray75", "gray25"))
        
        # Highlight active tool
        if tool_mode == ToolMode.BRUSH:
            self.brush_btn.configure(fg_color=("#1f538d", "#14375e"))
        elif tool_mode == ToolMode.ERASER:
            self.eraser_btn.configure(fg_color=("#1f538d", "#14375e"))
    
    def safe_import_image(self):
        """Safe wrapper for import_image to prevent multiple dialogs"""
        if self._importing:
            print("🔵 Import already in progress, ignoring click")
            return
        
        self._importing = True
        self.import_btn.configure(text="📁  Loading...", state="disabled")
        
        try:
            self.import_image()
        finally:
            self._importing = False
            self.import_btn.configure(text="📁  Choose Image", state="normal")
    
    def import_image(self):
        """Import an image file"""
        print("🔵 Import image button clicked")
        try:
            print("🔵 Opening file dialog...")
            file_path = filedialog.askopenfilename(
                title="Select Image",
                initialdir=os.path.expanduser("~"),  # Start in home directory
                filetypes=[
                    ("Image files", "*.jpg *.jpeg *.png *.tiff *.bmp"),
                    ("JPEG files", "*.jpg *.jpeg"),
                    ("PNG files", "*.png"),
                    ("TIFF files", "*.tiff *.tif"),
                    ("All files", "*.*")
                ]
            )
            
            print(f"🔵 File dialog returned: '{file_path}' (type: {type(file_path)})")
            
            if file_path and file_path.strip():  # Check for valid path
                print(f"🔵 Valid file path, loading: {file_path}")
                self.load_image(file_path)
            else:
                print("🔵 No file selected or empty path")
                
        except Exception as e:
            print(f"❌ Error in import_image: {e}")
            import traceback
            traceback.print_exc()
            messagebox.showerror("Error", f"Failed to open file dialog: {str(e)}")
    
    def load_image(self, file_path: str):
        """Load image from file path"""
        print(f"🔵 Loading image: {file_path}")
        try:
            # Check if file exists
            if not os.path.exists(file_path):
                raise FileNotFoundError(f"File not found: {file_path}")
            
            # Load image
            image = Image.open(file_path)
            self.state.selected_image = image
            # Build preview version for faster display
            self.preview_selected_image = self.build_preview_image(image)
            self.state.reset_processing()
            
            filename = os.path.basename(file_path)
            print(f"✅ Image loaded: {filename} ({image.size[0]}x{image.size[1]})")
            print(f"✅ State.selected_image set: {self.state.selected_image is not None}")
            print(f"✅ Can detect dust now: {self.state.can_detect_dust}")
            
            # Update UI
            self.status_label.configure(text=f"Image loaded: {filename}")
            
            # Enable detect button
            if hasattr(self, 'detect_btn'):
                self.detect_btn.configure(state="normal")
            
            # Update canvas display
            self.update_ui()
            
        except Exception as e:
            error_msg = f"Failed to load image: {str(e)}"
            print(f"❌ {error_msg}")
            self.status_label.configure(text=error_msg, text_color="red")
            messagebox.showerror("Error", error_msg)
    
    def handle_file_drop(self, files: List[str]):
        """Handle drag and drop files"""
        if not files:
            return
        
        file_path = files[0]
        if file_path.lower().endswith(('.jpg', '.jpeg', '.png', '.tiff', '.tif', '.bmp')):
            self.load_image(file_path)
        else:
            messagebox.showerror("Error", "Please drop a valid image file")
    
    
    # MARK: - Processing Operations
    
    def detect_dust(self):
        """Detect dust in the selected image"""
        print(f"🔍 Detect dust called")
        print(f"🔍 Selected image: {self.state.selected_image is not None}")
        print(f"🔍 U-Net model: {self.state.unet_model is not None}")
        print(f"🔍 Is detecting: {self.state.processing_state.is_detecting}")
        print(f"🔍 Is removing: {self.state.processing_state.is_removing}")
        print(f"🔍 Can detect dust: {self.state.can_detect_dust}")
        
        # Deselect active tools during generation for clarity
        self.state.set_tool_mode(ToolMode.NONE)

        if not self.state.can_detect_dust:
            print("❌ Cannot detect dust - preconditions not met")
            return
        
        self.state.processing_state.is_detecting = True
        self.state.notify_observers()
        
        def progress_callback(progress: float):
            self.root.after_idle(lambda: self.status_label.configure(
                text=f"Detecting dust... {int(progress * 100)}%"
            ))
        
        def completion_callback(result: np.ndarray, processing_time: float):
            try:
                self.state.raw_prediction_mask = result
                self.state.processing_state.processing_time = processing_time
                
                # Create initial binary mask
                self.update_dust_mask_with_threshold()
                
                # Store original mask for brush modifications
                self.state.original_dust_mask = self.state.dust_mask.copy() if self.state.dust_mask else None
                
                # Create low-res mask for performance
                self.state.create_low_res_mask()
                
                # Clear undo history and save initial state
                self.state.clear_mask_history()
                if self.state.dust_mask:
                    self.state.save_mask_to_history()
                
                self.state.processing_state.is_detecting = False
                self.status_label.configure(text=f"Dust detected in {processing_time:.2f}s", text_color="green")
                self.state.notify_observers()
                
                print(f"✅ Dust detection completed in {processing_time:.2f}s")
                
            except Exception as e:
                self.handle_processing_error(e, "dust detection")
        
        def error_callback(error: Exception):
            self.handle_processing_error(error, "dust detection")
        
        # Start processing task using the simple method (matches Swift macOS app)
        def detect_worker():
            try:
                print("🔍 Starting dust detection...")
                start_time = time.time()
                
                # Use the exact prediction method from main.ipynb
                result = ImageProcessingService.predict_dust_mask(
                    self.state.unet_model,
                    self.state.selected_image,
                    threshold=0.5,  # Default threshold, will be adjustable
                    window_size=1024,
                    stride=512,
                    device=self.state.device,
                    progress_callback=progress_callback
                )
                
                processing_time = time.time() - start_time
                completion_callback(result, processing_time)
                
            except Exception as e:
                error_callback(e)
        
        self.processing_task = threading.Thread(target=detect_worker)
        self.processing_task.daemon = True
        
        self.processing_task.start()
    
    def remove_dust(self):
        """Remove dust using AI inpainting"""
        print(f"🎯 Remove dust called - can_remove_dust: {self.state.can_remove_dust}")
        print(f"🎯 State check - dust_mask: {self.state.dust_mask is not None}, is_detecting: {self.state.processing_state.is_detecting}, is_removing: {self.state.processing_state.is_removing}")
        
        if not self.state.can_remove_dust:
            print("❌ Cannot remove dust - preconditions not met")
            return
        
        # Toggle overlay visibility when starting removal, per requested UX
        try:
            self.toggle_overlay()
        except Exception as _e:
            print(f"⚠️ Overlay toggle failed (non-blocking): {_e}")
        
        # Deselect active tools when generating
        self.state.set_tool_mode(ToolMode.NONE)

        # 1) Generate a fast preview inpaint immediately for responsiveness (2K preview path)
        try:
            if self.preview_selected_image is not None and self.state.dust_mask is not None:
                # Build a preview-sized mask
                preview_size = self.preview_selected_image.size
                preview_mask = self.state.dust_mask.resize(preview_size, Image.Resampling.NEAREST)
                # Dilate at fixed radius 5 in preview scale
                preview_mask_dilated = ImageProcessingService.dilate_mask(preview_mask, kernel_size=5)
                # Inpaint once on preview
                preview_processed = self.perform_cv2_inpainting(self.preview_selected_image.convert('RGB'), preview_mask_dilated)
                self.preview_processed_image = preview_processed
                # Switch view for quick feedback
                self.state.set_processing_mode(ProcessingMode.SPLIT_SLIDER)
                self.state.notify_observers()
                print("🎯 Preview inpaint generated for instant feedback")
                # Ensure active view updates immediately
                # Invalidate split cache so new preview is used
                self._split_cached_signature = None
                self.display_image()
        except Exception as e:
            print(f"⚠️ Preview inpaint failed: {e}")

        self.state.processing_state.is_removing = True
        self.state.notify_observers()
        
        def completion_callback(result: Image.Image, processing_time: float):
            # Schedule GUI updates on main thread
            def update_ui():
                try:
                    print(f"🎯 Completion callback called with result: {type(result)}, time: {processing_time:.2f}s")
                    self.state.processed_image = result
                    print(f"🎯 Processed image set: {self.state.processed_image is not None}")
                    self.state.processing_state.processing_time = processing_time
                    self.state.processing_state.is_removing = False
                    
                    # Auto-switch to split view
                    print(f"🎯 Switching to SPLIT_SLIDER mode...")
                    self.state.set_processing_mode(ProcessingMode.SPLIT_SLIDER)
                    print(f"🎯 Current processing mode: {self.state.view_state.processing_mode}")
                    
                    self.status_label.configure(text=f"Dust removed in {processing_time:.2f}s", text_color="green")
                    
                    # Force multiple UI updates to ensure refresh
                    print(f"🎯 Forcing UI updates...")
                    self.state.notify_observers()
                    
                    # Force immediate display update with processed image
                    # Invalidate split cache to pick up new processed preview/full-res
                    try:
                        self.preview_processed_image = self.build_preview_image(self.state.processed_image)
                    except Exception as _e:
                        print(f"⚠️ Failed to build processed preview: {_e}")
                    self._split_cached_signature = None
                    self.root.after_idle(lambda: self.display_image())
                    print(f"🎯 Direct display_image update scheduled")
                    
                    # Force window refresh
                    self.root.after_idle(lambda: self.root.update_idletasks())
                    print(f"🎯 Window refresh scheduled")
                    
                    print(f"✅ Dust removal completed in {processing_time:.2f}s")
                    
                except Exception as e:
                    print(f"❌ Error in completion callback: {e}")
                    self.handle_processing_error(e, "dust removal")
            
            self.root.after_idle(update_ui)
        
        def error_callback(error: Exception):
            def handle_error():
                print(f"❌ Error callback called: {error}")
                self.handle_processing_error(error, "dust removal")
            
            self.root.after_idle(handle_error)
        
        # Start processing task
        print("🎯 Starting ProcessingTask...")
        self.processing_task = ProcessingTask(
            target_func=self.perform_dust_removal,
            callback=completion_callback,
            error_callback=error_callback
        )
        
        self.processing_task.start()
        print("🎯 ProcessingTask started")
    
    def perform_dust_removal(self) -> Image.Image:
        """Perform the actual dust removal process using CV2 inpainting"""
        print(f"🎨 perform_dust_removal called")
        print(f"🎨 Selected image available: {self.state.selected_image is not None}")
        print(f"🎨 Dust mask available: {self.state.dust_mask is not None}")
        
        if not self.state.selected_image or not self.state.dust_mask:
            raise ValueError("Missing required components for dust removal")
        
        print("🎨 Starting CV2 inpainting process...")
        
        # Dilate mask for better coverage
        print("🎨 Dilating mask...")
        dilated_mask = ImageProcessingService.dilate_mask(self.state.dust_mask)
        
        # Convert to RGB for processing
        print("🎨 Converting image to RGB...")
        image_rgb = self.state.selected_image.convert('RGB')
        
        # Perform CV2 inpainting using the fallback method
        print("🎨 Performing CV2 inpainting...")
        inpainted = self.perform_cv2_inpainting(image_rgb, dilated_mask)
        
        # Blend with original using mask
        print("🎨 Blending images...")
        final_result = ImageProcessingService.blend_images(
            image_rgb, inpainted, dilated_mask
        )
        # Build preview for processed image
        self.preview_processed_image = self.build_preview_image(final_result)
        
        print("🎨 Dust removal process completed!")
        return final_result
    
    def perform_cv2_inpainting(self, image: Image.Image, mask: Image.Image) -> Image.Image:
        """Perform single-pass CV2 TELEA inpainting (fast)."""
        import cv2
        
        # Convert PIL images to numpy arrays
        image_np = np.array(image.convert('RGB'))
        mask_np = np.array(mask.convert('L'))
        
        print(f"🔍 Image shape: {image_np.shape}, Mask shape: {mask_np.shape}")
        result = cv2.inpaint(image_np, mask_np, inpaintRadius=5, flags=cv2.INPAINT_TELEA)
        print("✅ CV2 single-pass inpainting completed (radius=5)")
        return Image.fromarray(result)
    
    def export_image(self):
        """Export processed image"""
        if not self.state.processed_image:
            messagebox.showwarning("Warning", "No processed image to export")
            return
        
        file_path = filedialog.asksaveasfilename(
            title="Save Processed Image",
            defaultextension=".png",
            filetypes=[
                ("PNG files", "*.png"),
                ("JPEG files", "*.jpg"),
                ("TIFF files", "*.tiff"),
                ("All files", "*.*")
            ]
        )
        
        if file_path:
            try:
                # Save with high quality
                if file_path.lower().endswith('.jpg') or file_path.lower().endswith('.jpeg'):
                    self.state.processed_image.save(file_path, 'JPEG', quality=95)
                else:
                    self.state.processed_image.save(file_path)
                
                filename = os.path.basename(file_path)
                print(f"✅ Image saved: {filename}")
                self.status_label.configure(text=f"Image saved: {filename}")
                
                # Show in file manager
                if os.name == 'nt':  # Windows
                    os.startfile(os.path.dirname(file_path))
                elif os.name == 'posix':  # macOS/Linux
                    os.system(f'open "{os.path.dirname(file_path)}"')
                    
            except Exception as e:
                self.state.show_error(f"Failed to save image: {str(e)}")
    
    # MARK: - UI Interaction Methods
    
    def set_view_mode(self, mode: ProcessingMode):
        """Set processing mode and update display"""
        print(f"🖼️ Switching to {mode} view mode")
        self.state.set_processing_mode(mode)
        # Update button states
        self.update_view_buttons()
        # Force immediate display update
        self.display_image()
    
    def cycle_view_mode(self):
        """Cycle through view modes with camera button"""
        modes = [ProcessingMode.SINGLE, ProcessingMode.SIDE_BY_SIDE, ProcessingMode.SPLIT_SLIDER]
        current_mode = self.state.view_state.processing_mode
        
        try:
            current_index = modes.index(current_mode)
            next_index = (current_index + 1) % len(modes)
        except ValueError:
            next_index = 0
        
        next_mode = modes[next_index]
        print(f"🖼️ Camera button: cycling from {current_mode} to {next_mode}")
        self.set_view_mode(next_mode)
    
    def toggle_brush_tool(self):
        """Toggle brush tool"""
        if self.state.view_state.tool_mode == ToolMode.BRUSH:
            self.state.set_tool_mode(ToolMode.NONE)
        else:
            self.state.set_tool_mode(ToolMode.BRUSH)
    
    def toggle_eraser_tool(self):
        """Toggle eraser tool"""
        if self.state.view_state.tool_mode == ToolMode.ERASER:
            self.state.set_tool_mode(ToolMode.NONE)
        else:
            self.state.set_tool_mode(ToolMode.ERASER)
    
    def setup_keyboard_shortcuts(self):
        """Setup professional keyboard shortcuts"""
        # Global shortcuts
        self.root.bind('<Control-o>', lambda e: self.import_image())
        self.root.bind('<Control-s>', lambda e: self.export_image())
        self.root.bind('<Control-z>', lambda e: self.undo_mask_change())
        # macOS Command+Z and Meta+Z fallback
        self.root.bind('<Command-z>', lambda e: self.undo_mask_change())
        self.root.bind('<Meta-z>', lambda e: self.undo_mask_change())
        self.root.bind('<space>', lambda e: self.toggle_space_mode(True))
        self.root.bind('<KeyRelease-space>', lambda e: self.toggle_space_mode(False))
        self.root.bind('<m>', lambda e: self.toggle_dust_overlay())
        self.root.bind('<c>', lambda e: self.toggle_compare_mode())
        self.root.bind('<e>', lambda e: self.toggle_eraser_tool())
        self.root.bind('<b>', lambda e: self.toggle_brush_tool())
        
        # Focus management
        self.root.focus_set()
    
    def toggle_dust_overlay(self):
        """Toggle dust overlay visibility (M key like Swift app)"""
        if self.state.dust_mask:
            hide_detections = getattr(self.state, 'hide_detections', False)
            self.state.hide_detections = not hide_detections
            print(f"🎭 Dust overlay: {'hidden' if self.state.hide_detections else 'visible'}")
            # Refresh display
            if self.state.selected_image:
                self.display_image()
    
    def toggle_space_mode(self, pressed: bool):
        """Toggle space key mode for panning"""
        self.state.view_state.space_key_pressed = pressed
        # When space is released, stop any panning drag
        if not pressed:
            self.is_panning = False
            self.last_mouse_pos = None
        self.state.notify_observers()
    
    def toggle_compare_mode(self):
        """Cycle through compare modes"""
        modes = [ProcessingMode.SINGLE, ProcessingMode.SIDE_BY_SIDE, ProcessingMode.SPLIT_SLIDER]
        current_index = modes.index(self.state.view_state.processing_mode)
        next_mode = modes[(current_index + 1) % len(modes)]
        self.state.set_processing_mode(next_mode)
    
    def undo_mask_change(self):
        """Undo last mask change"""
        if self.state.can_undo:
            self.state.undo_last_mask_change()
    
    def on_threshold_changed(self, value):
        """Handle real-time threshold slider changes (matches Swift app)"""
        threshold = float(value)
        
        # Update the displayed value
        self.threshold_value_label.configure(text=f"{threshold:.3f}")
        
        # Update the state threshold
        self.state.processing_state.threshold = threshold
        
        # Immediately update the dust mask if we have a prediction
        if self.state.raw_prediction_mask is not None:
            self.update_dust_mask_with_threshold_realtime()
    
    def load_models_async(self):
        """Load models asynchronously"""
        def load_models():
            try:
                print("🤖 Starting model loading...")
                
                # Look for model files
                model_paths = self.find_model_files()
                print(f"🤖 Model paths found: {model_paths}")
                
                if model_paths['unet']:
                    print(f"🤖 Loading U-Net model from: {model_paths['unet']}")
                    self.state.unet_model = ImageProcessingService.load_model(
                        model_paths['unet'], self.state.device
                    )
                    print(f"🤖 U-Net model loaded successfully: {self.state.unet_model is not None}")
                    self.root.after_idle(lambda: self.status_label.configure(text="U-Net model loaded"))
                else:
                    print("❌ No U-Net model file found!")
                    self.root.after_idle(lambda: self.status_label.configure(
                        text="No model file found", text_color="red"
                    ))
                
                # Initialize LaMa
                print("🤖 Initializing LaMa...")
                self.lama_inpainter = LamaInpainter()
                self.state.lama_inpainter = self.lama_inpainter
                
                lama_status = "✅ Available" if self.lama_inpainter.available else "❌ Unavailable"
                print(f"🤖 LaMa status: {lama_status}")
                self.root.after_idle(lambda: self.lama_label.configure(text=f"LaMa: {lama_status}"))
                
                if self.state.unet_model:
                    print("🤖 All models loaded successfully")
                    self.root.after_idle(lambda: self.status_label.configure(
                        text="Ready - Drag image or use Import", text_color="green"
                    ))
                else:
                    print("❌ U-Net model failed to load")
                
            except Exception as e:
                print(f"❌ Error loading models: {e}")
                import traceback
                traceback.print_exc()
                self.root.after_idle(lambda: self.status_label.configure(
                    text="Model loading failed", text_color="red"
                ))
        
        thread = threading.Thread(target=load_models)
        thread.daemon = True
        thread.start()
    
    def find_model_files(self) -> dict:
        """Find model files - prioritize the specific weights file from main.ipynb"""
        model_paths = {'unet': None, 'lama': None}
        
        # First, look for the exact weights file mentioned in main.ipynb
        exact_weight_path = Path(__file__).parent / "weights" / "v5_bce_unet_epoch30.pth"
        if exact_weight_path.exists():
            model_paths['unet'] = str(exact_weight_path)
            print(f"✅ Found exact weights file: {exact_weight_path}")
            return model_paths
        
        # Fallback: search in common locations
        search_dirs = [
            Path(__file__).parent / "weights",
            Path(__file__).parent / "checkpoints", 
            Path.cwd() / "models",
            Path.cwd() / "checkpoints",
            Path.cwd() / "weights",
            Path.cwd().parent / "models",
            Path.cwd().parent / "checkpoints",
        ]
        
        for search_dir in search_dirs:
            if search_dir.exists():
                print(f"🔍 Searching in: {search_dir}")
                # Look for U-Net models (prioritize v5 and v6 models from notebook)
                for pattern in ["v5_*.pth", "v6_*.pth", "*unet*.pth", "*.pth"]:
                    unet_files = list(search_dir.glob(pattern))
                    if unet_files:
                        # Sort by name to get latest version
                        unet_files.sort(reverse=True)
                        model_paths['unet'] = str(unet_files[0])
                        print(f"✅ Found weights file: {unet_files[0]}")
                        break
                
                if model_paths['unet']:
                    break
        
        return model_paths
    
    # MARK: - Processing Support Methods
    
    def handle_processing_error(self, error: Exception, operation: str):
        """Handle processing errors"""
        self.state.processing_state.is_detecting = False
        self.state.processing_state.is_removing = False
        error_msg = f"{operation.capitalize()} failed: {str(error)}"
        self.state.show_error(error_msg)
        self.status_label.configure(text="Error occurred", text_color="red")
        self.state.notify_observers()
        print(f"❌ {error_msg}")
    
    def update_dust_mask_with_threshold(self):
        """Update dust mask based on current threshold"""
        if self.state.raw_prediction_mask is None or not self.state.selected_image:
            return
        
        # Create new binary mask
        new_mask = ImageProcessingService.create_binary_mask(
            self.state.raw_prediction_mask,
            self.state.processing_state.threshold,
            self.state.selected_image.size
        )
        
        self.state.dust_mask = new_mask
        self.state.create_low_res_mask()
        self.state.notify_observers()
    
    def update_dust_mask_with_threshold_realtime(self):
        """Real-time threshold updates (matches Swift app behavior)"""
        if self.state.raw_prediction_mask is None or not self.state.selected_image:
            return
        
        print(f"🎚️ Updating threshold to {self.state.processing_state.threshold:.3f}")
        
        # Create new binary mask with current threshold
        new_mask = ImageProcessingService.create_binary_mask(
            self.state.raw_prediction_mask,
            self.state.processing_state.threshold,
            self.state.selected_image.size
        )
        
        if new_mask:
            self.state.dust_mask = new_mask
            self.state.create_low_res_mask()
            
            # Immediately update the display
            self.update_ui()
            
            print(f"✅ Mask updated with threshold {self.state.processing_state.threshold:.3f}")
    
    # MARK: - Brush Tool Operations
    
    def apply_eraser_at_point(self, point: Tuple[float, float], canvas_width: int, canvas_height: int):
        """Apply eraser tool at given point"""
        if not self.state.dust_mask:
            return
        
        # Start brush stroke
        self.state.start_brush_stroke()
        
        # Get low-res mask for performance
        low_res_mask = self.state.get_low_res_mask()
        if not low_res_mask:
            return
        
        # Convert point to low-res coordinates
        low_res_point = self.convert_to_low_res_coordinates(point, low_res_mask.size)
        if not low_res_point:
            return
        
        # Calculate brush radius for low-res mask
        scale_factor = min(low_res_mask.size) / min(canvas_width, canvas_height)
        brush_radius = max(1, int(self.state.view_state.brush_size * scale_factor))
        
        # Apply eraser with interpolation if we have a previous point
        if self.state.last_eraser_point:
            updated_mask = BrushTools.interpolated_stroke(
                low_res_mask, self.state.last_eraser_point, low_res_point, 
                brush_radius, is_erasing=True
            )
        else:
            updated_mask = BrushTools.apply_circular_brush(
                low_res_mask, low_res_point, brush_radius, is_erasing=True
            )
        
        # Update state
        self.state.last_eraser_point = low_res_point
        self.state.update_low_res_mask(updated_mask)
    
    def apply_brush_at_point(self, point: Tuple[float, float], canvas_width: int, canvas_height: int):
        """Apply brush tool at given point"""
        if not self.state.dust_mask:
            return
        
        # Start brush stroke
        self.state.start_brush_stroke()
        
        # Get low-res mask for performance
        low_res_mask = self.state.get_low_res_mask()
        if not low_res_mask:
            return
        
        # Convert point to low-res coordinates
        low_res_point = self.convert_to_low_res_coordinates(point, low_res_mask.size)
        if not low_res_point:
            return
        
        # Calculate brush radius for low-res mask
        scale_factor = min(low_res_mask.size) / min(canvas_width, canvas_height)
        brush_radius = max(1, int(self.state.view_state.brush_size * scale_factor))
        
        # Apply brush with interpolation if we have a previous point
        if self.state.last_brush_point:
            updated_mask = BrushTools.interpolated_stroke(
                low_res_mask, self.state.last_brush_point, low_res_point, 
                brush_radius, is_erasing=False
            )
        else:
            updated_mask = BrushTools.apply_circular_brush(
                low_res_mask, low_res_point, brush_radius, is_erasing=False
            )
        
        # Update state
        self.state.last_brush_point = low_res_point
        self.state.update_low_res_mask(updated_mask)
    
    def convert_to_low_res_coordinates(self, point: Tuple[float, float], 
                                     low_res_size: Tuple[int, int]) -> Optional[Tuple[float, float]]:
        """Convert canvas point to low-res mask coordinates"""
        if not self.state.selected_image:
            return None
        
        # If we have display bounds, map canvas point back to image coords accounting for zoom/pan
        if hasattr(self, 'image_item_bounds') and self.image_item_bounds:
            left, top, disp_w, disp_h = self.image_item_bounds
            canvas_x, canvas_y = point
            if canvas_x < left or canvas_x > left + disp_w or canvas_y < top or canvas_y > top + disp_h:
                return None
            # Relative within displayed image
            rel_x = (canvas_x - left) / float(disp_w)
            rel_y = (canvas_y - top) / float(disp_h)
            # Map to original image pixel coords
            orig_w, orig_h = self.state.selected_image.size
            img_x = rel_x * orig_w
            img_y = rel_y * orig_h
            # Then to low-res coords
            scale_x = low_res_size[0] / float(orig_w)
            scale_y = low_res_size[1] / float(orig_h)
            low_res_x = img_x * scale_x
            low_res_y = img_y * scale_y
        else:
            # Fallback mapping (assumes point is already in image space)
            original_size = self.state.selected_image.size
            scale_x = low_res_size[0] / original_size[0]
            scale_y = low_res_size[1] / original_size[1]
            low_res_x = point[0] * scale_x
            low_res_y = point[1] * scale_y
        
        # Bounds check
        if (low_res_x < 0 or low_res_x >= low_res_size[0] or
            low_res_y < 0 or low_res_y >= low_res_size[1]):
            return None
        
        return (low_res_x, low_res_y)
    
    # MARK: - Brush Cursor Methods
    
    def on_mouse_motion(self, event):
        """Handle mouse motion for brush cursor"""
        if not self.use_gl and hasattr(self.state, 'view_state') and self.state.view_state.tool_mode in (ToolMode.BRUSH, ToolMode.ERASER):
            self.update_brush_cursor(event.x, event.y)
        else:
            self.hide_brush_cursor()
    
    def update_brush_cursor(self, x, y):
        """Update brush cursor position and size"""
        if self.use_gl:
            return  # Skip for OpenGL view
            
        # Hide old cursor
        if self.brush_cursor_id:
            self.canvas.delete(self.brush_cursor_id)
        
        # Get brush size (actual pixel size regardless of zoom)
        brush_size = getattr(self.state.view_state, 'brush_size', 20)
        
        # Calculate display size (brush size on screen, accounting for current zoom)
        zoom_scale = getattr(self.state.view_state, 'zoom_scale', 1.0)
        display_size = brush_size * zoom_scale
        
        # Create cursor circle
        x1 = x - display_size // 2
        y1 = y - display_size // 2
        x2 = x + display_size // 2
        y2 = y + display_size // 2
        
        # Different colors for brush vs eraser
        if self.state.view_state.tool_mode == ToolMode.BRUSH:
            outline_color = "#4CAF50"  # Green
            fill_color = "#4CAF5040"  # Semi-transparent green
        else:  # ERASER
            outline_color = "#FF6B35"  # Orange
            fill_color = "#FF6B3540"  # Semi-transparent orange
        
        self.brush_cursor_id = self.canvas.create_oval(
            x1, y1, x2, y2,
            outline=outline_color, 
            fill=fill_color,
            width=2
        )
        self.cursor_visible = True
    
    def hide_brush_cursor(self):
        """Hide the brush cursor"""
        if not self.use_gl and self.brush_cursor_id and self.cursor_visible:
            self.canvas.delete(self.brush_cursor_id)
            self.brush_cursor_id = None
            self.cursor_visible = False
    
    def update_cursor_for_tool_change(self):
        """Update cursor when tool mode changes"""
        if not self.use_gl:
            if hasattr(self.state, 'view_state') and self.state.view_state.tool_mode in (ToolMode.BRUSH, ToolMode.ERASER):
                # Set custom cursor for tools
                self.canvas.config(cursor="none")  # Hide default cursor
            else:
                # Reset to default cursor
                self.canvas.config(cursor="")
                self.hide_brush_cursor()

    # MARK: - Application Lifecycle
    
    def run(self):
        """Run the application"""
        try:
            self.root.mainloop()
        except KeyboardInterrupt:
            print("\nApplication interrupted by user")
        except Exception as e:
            print(f"\nApplication error: {e}")
            messagebox.showerror("Fatal Error", f"Application error: {e}")
        finally:
            self.cleanup()
    
    def cleanup(self):
        """Cleanup resources"""
        if self.processing_task and self.processing_task.is_running():
            print("Waiting for processing task to complete...")
            self.processing_task.join(timeout=5.0)
        
        print("✨ Spotless Film App closed")


def main():
    """Main entry point"""
    print("✨ Starting Spotless Film (Modern Professional Version)...")
    print("Features:")
    print("  • Professional three-pane macOS-style interface")
    print("  • Advanced AI dust detection (U-Net)")
    print("  • State-of-the-art inpainting (LaMa)")
    print("  • Multiple view modes (Single, Side-by-Side, Split)")
    print("  • Professional brush tools with undo")
    print("  • Real-time threshold adjustment")
    print("  • Zoom/pan with performance optimization")
    print("  • CustomTkinter modern styling")
    print()
    
    try:
        app = SpotlessFilmModern()
        app.run()
    except ImportError as e:
        print("❌ Missing dependencies. Please install:")
        print("   pip install customtkinter tkinterdnd2")
        print(f"   Error: {e}")
    except Exception as e:
        print(f"Failed to start application: {e}")
        messagebox.showerror("Startup Error", f"Failed to start application: {e}")

if __name__ == "__main__":
    main()