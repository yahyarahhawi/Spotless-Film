#!/usr/bin/env python3
"""
UI Components for Dust Removal App

Custom UI components matching Spotless-Film's professional interface.
"""

import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from tkinterdnd2 import DND_FILES
from PIL import Image, ImageTk
import numpy as np
from typing import Optional, Callable, Tuple
import threading
from dust_removal_state import DustRemovalState, ProcessingMode, ToolMode
from simple_modern_theme import SimpleModernColors


class ModernWidgets:
    """Helper class for creating modern UI widgets"""
    
    @staticmethod
    def create_icon_button(parent, text, icon="", command=None, style="TButton", **kwargs):
        """Create a modern icon button"""
        button_text = f"{icon} {text}" if icon else text
        btn = ttk.Button(parent, text=button_text, command=command, style=style, **kwargs)
        return btn
    
    @staticmethod
    def create_square_button(parent, text, icon="", command=None, style="Tool.TButton", **kwargs):
        """Create a square button for tools"""
        button_text = f"{icon}\n{text}" if icon else text
        btn = ttk.Button(parent, text=button_text, command=command, style=style, 
                        width=8, **kwargs)
        return btn
    
    @staticmethod
    def create_section(parent, title):
        """Create a collapsible section"""
        section = ttk.LabelFrame(parent, text=title, style="Card.TLabelFrame")
        return section
    
    @staticmethod
    def create_card(parent):
        """Create a card-style frame"""
        frame = ttk.Frame(parent, style="Card.TFrame")
        return frame
    
    @staticmethod
    def create_value_display(parent, label, value):
        """Create a label-value display pair"""
        frame = ttk.Frame(parent)
        label_widget = ttk.Label(frame, text=label, style="Secondary.TLabel")
        label_widget.pack(side='left')
        value_widget = ttk.Label(frame, text=value, style="Mono.TLabel")
        value_widget.pack(side='right')
        return frame, value_widget
    
    @staticmethod
    def add_visual_separator(parent, orient='horizontal'):
        """Add a visual separator"""
        sep = ttk.Separator(parent, orient=orient)
        if orient == 'vertical':
            sep.pack(side='left', fill='y', padx=8)
        else:
            sep.pack(fill='x', pady=8)
        return sep


class SpotlessFrame(ttk.Frame):
    """Base frame with Spotless Film styling"""
    
    def __init__(self, parent, style="TFrame", **kwargs):
        super().__init__(parent, style=style, **kwargs)
        self.configure(relief='flat', borderwidth=0)


class SpotlessSidebar(SpotlessFrame):
    """Spotless Film sidebar matching the original interface"""
    
    def __init__(self, parent, state: DustRemovalState, callbacks: dict, **kwargs):
        super().__init__(parent, **kwargs)
        self.state = state
        self.callbacks = callbacks
        
        self.setup_ui()
        self.state.add_observer(self.update_ui)
    
    def setup_ui(self):
        """Setup sidebar UI"""
        self.configure(bg=SimpleModernColors.BG_MEDIUM)
        
        # Header section
        self.header_frame = self.create_header()
        self.header_frame.pack(fill='x', padx=16, pady=20)
        
        # Separator
        sep = ttk.Separator(self, orient='horizontal')
        sep.pack(fill='x', padx=16, pady=8)
        
        # Main content with scrolling
        self.canvas = tk.Canvas(self, highlightthickness=0)
        self.scrollbar = ttk.Scrollbar(self, orient="vertical", command=self.canvas.yview)
        self.scrollable_frame = ttk.Frame(self.canvas)
        
        self.scrollable_frame.bind(
            "<Configure>",
            lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all"))
        )
        
        self.canvas.create_window((0, 0), window=self.scrollable_frame, anchor="nw")
        self.canvas.configure(yscrollcommand=self.scrollbar.set)
        
        # Import section
        self.import_section = self.create_import_section()
        self.import_section.pack(fill='x', padx=16, pady=8)
        
        # Detection section
        self.detection_section = self.create_detection_section()
        self.detection_section.pack(fill='x', padx=16, pady=8)
        
        # Removal section (conditional)
        self.removal_section = self.create_removal_section()
        
        self.canvas.pack(side="left", fill="both", expand=True)
        self.scrollbar.pack(side="right", fill="y")
    
    def create_header(self) -> ttk.Frame:
        """Create header with app branding"""
        frame = ttk.Frame(self)
        
        # Icon container
        icon_container = ttk.Frame(frame)
        icon_container.pack(pady=(0, 8))
        
        # App icon with gradient-like effect using multiple labels
        icon_bg = ttk.Label(icon_container, text="●", 
                           font=("Helvetica", 40),
                           foreground=SimpleModernColors.ACCENT_BLUE)
        icon_bg.pack()
        
        # Sparkle overlay
        icon_sparkle = ttk.Label(icon_container, text="✨", 
                                font=("Helvetica", 20),
                                foreground=SimpleModernColors.TEXT_WHITE)
        icon_sparkle.place(relx=0.5, rely=0.5, anchor='center')
        
        # Title
        title_label = ttk.Label(frame, text="Spotless Film", 
                               style="Title.TLabel")
        title_label.pack(pady=(0, 4))
        
        # Subtitle
        subtitle_label = ttk.Label(frame, text="AI-powered film restoration",
                                  style="Subtitle.TLabel")
        subtitle_label.pack()
        
        return frame
    
    def create_import_section(self) -> ttk.LabelFrame:
        """Create import section"""
        section = ModernWidgets.create_section(self.scrollable_frame, "Import")
        
        # Drop zone or file info
        self.image_info_frame = ttk.Frame(section)
        self.image_info_frame.pack(fill='x', pady=(0, 12))
        
        # Import button
        self.import_btn = ModernWidgets.create_icon_button(
            section, "Choose File", "📁",
            command=self.callbacks.get('import_image'),
            style='Accent.TButton'
        )
        self.import_btn.pack(fill='x')
        
        return section
    
    def create_detection_section(self) -> ttk.LabelFrame:
        """Create detection section"""
        section = ModernWidgets.create_section(self.scrollable_frame, "Detection")
        
        # Detect button
        self.detect_btn = ModernWidgets.create_icon_button(
            section, "Detect Dust", "🔍",
            command=self.callbacks.get('detect_dust'),
            style='TButton'
        )
        self.detect_btn.pack(fill='x', pady=(0, 12))
        
        # Threshold controls (conditional)
        self.threshold_frame = ModernWidgets.create_card(section)
        self.threshold_frame.configure(padding=12)
        
        threshold_label = ttk.Label(self.threshold_frame, text="Sensitivity",
                                   style="Secondary.TLabel")
        threshold_label.pack(anchor='w', pady=(0, 8))
        
        # Threshold value display
        value_frame = ttk.Frame(self.threshold_frame)
        value_frame.pack(fill='x', pady=(0, 8))
        
        self.threshold_value_label = ttk.Label(value_frame, 
                                              text=f"{self.state.processing_state.threshold:.3f}",
                                              style="Mono.TLabel")
        self.threshold_value_label.pack()
        
        # Threshold slider
        self.threshold_scale = ttk.Scale(self.threshold_frame, from_=0.001, to=0.1,
                                        orient='horizontal',
                                        style='Orange.Horizontal.TScale',
                                        command=self.on_threshold_changed)
        self.threshold_scale.set(self.state.processing_state.threshold)
        self.threshold_scale.pack(fill='x', pady=(0, 8))
        
        # Labels
        labels_frame = ttk.Frame(self.threshold_frame)
        labels_frame.pack(fill='x')
        ttk.Label(labels_frame, text="Less Sensitive", style="Tertiary.TLabel").pack(side='left')
        ttk.Label(labels_frame, text="More Sensitive", style="Tertiary.TLabel").pack(side='right')
        
        return section
    
    def create_removal_section(self) -> ttk.LabelFrame:
        """Create dust removal section"""
        section = ModernWidgets.create_section(self.scrollable_frame, "Dust Removal")
        
        # Remove dust button
        self.remove_btn = ModernWidgets.create_icon_button(
            section, "Remove Dust", "✨",
            command=self.callbacks.get('remove_dust'),
            style='Success.TButton'
        )
        self.remove_btn.pack(fill='x', pady=(0, 12))
        
        # Processing time display
        self.time_frame, self.time_value_label = ModernWidgets.create_value_display(
            section, "Processing Time:", "--"
        )
        
        return section
    
    def on_threshold_changed(self, value):
        """Handle threshold slider change"""
        threshold = float(value)
        self.state.processing_state.threshold = threshold
        self.threshold_value_label.config(text=f"{threshold:.3f}")
        
        if self.callbacks.get('threshold_changed'):
            self.callbacks['threshold_changed']()
    
    def update_ui(self):
        """Update UI based on current state"""
        # Update image info
        for widget in self.image_info_frame.winfo_children():
            widget.destroy()
        
        if self.state.selected_image:
            self.create_image_info_display()
        else:
            self.create_drop_zone_display()
        
        # Update button states
        self.detect_btn.config(state='normal' if self.state.can_detect_dust else 'disabled')
        self.remove_btn.config(state='normal' if self.state.can_remove_dust else 'disabled')
        
        # Update button text for processing states
        if self.state.processing_state.is_detecting:
            self.detect_btn.config(text="🔍 Detecting...")
        else:
            self.detect_btn.config(text="🔍 Detect Dust")
        
        if self.state.processing_state.is_removing:
            self.remove_btn.config(text="✨ Removing...")
        else:
            self.remove_btn.config(text="✨ Remove Dust")
        
        # Show/hide threshold controls
        if self.state.raw_prediction_mask is not None:
            self.threshold_frame.pack(fill='x', pady=(12, 0))
        else:
            self.threshold_frame.pack_forget()
        
        # Show/hide removal section
        if self.state.dust_mask is not None:
            self.removal_section.pack(fill='x', padx=16, pady=8)
        else:
            self.removal_section.pack_forget()
        
        # Update processing time
        if self.state.processing_state.processing_time > 0:
            self.time_frame.pack(fill='x')
            self.time_value_label.config(text=f"{self.state.processing_state.processing_time:.2f}s")
        else:
            self.time_frame.pack_forget()
    
    def create_image_info_display(self):
        """Create image info display"""
        info_frame = ModernWidgets.create_card(self.image_info_frame)
        info_frame.pack(fill='x', pady=(0, 8))
        info_frame.configure(padding=12)
        
        # Status
        status_frame = ttk.Frame(info_frame)
        status_frame.pack(fill='x', pady=(0, 8))
        
        ttk.Label(status_frame, text="✓", foreground=SimpleModernColors.ACCENT_GREEN, 
                 font=("Helvetica", 14, "bold")).pack(side='left')
        ttk.Label(status_frame, text="Image Loaded",
                 style="Secondary.TLabel").pack(side='left', padx=(8, 0))
        
        # Size info
        if self.state.selected_image:
            size_text = f"{self.state.selected_image.size[0]} × {self.state.selected_image.size[1]}"
            size_frame, _ = ModernWidgets.create_value_display(info_frame, "Size:", size_text)
            size_frame.pack(fill='x')
    
    def create_drop_zone_display(self):
        """Create drop zone display"""
        drop_frame = ModernWidgets.create_card(self.image_info_frame)
        drop_frame.pack(fill='x', pady=(0, 8))
        drop_frame.configure(height=100, padding=12)
        
        # Icon and text
        content_frame = ttk.Frame(drop_frame)
        content_frame.place(relx=0.5, rely=0.5, anchor='center')
        
        # Icon with modern styling
        icon_label = ttk.Label(content_frame, text="🖼️", 
                              font=("Helvetica", 32))
        icon_label.pack(pady=(0, 4))
        
        # Main text
        ttk.Label(content_frame, text="Drop image here",
                 style="Secondary.TLabel").pack()
        
        # Supported formats
        ttk.Label(content_frame, text="PNG, JPEG, TIFF",
                 style="Tertiary.TLabel").pack(pady=(4, 0))


class SpotlessToolbar(SpotlessFrame):
    """Spotless Film toolbar matching the original interface"""
    
    def __init__(self, parent, state: DustRemovalState, callbacks: dict, **kwargs):
        super().__init__(parent, **kwargs)
        self.state = state
        self.callbacks = callbacks
        
        self.setup_ui()
        self.state.add_observer(self.update_ui)
    
    def setup_ui(self):
        """Setup toolbar UI"""
        self.configure(style="Toolbar.TFrame")
        
        # Add subtle border
        border_frame = ttk.Frame(self, height=1, style="TFrame")
        border_frame.configure(background=SimpleModernColors.BG_LIGHT)
        border_frame.pack(fill='x', side='bottom')
        
        # Main toolbar frame
        toolbar_frame = ttk.Frame(self, style="Toolbar.TFrame")
        toolbar_frame.pack(fill='x', padx=20, pady=12)
        
        # Tools section
        tools_frame = ttk.Frame(toolbar_frame)
        tools_frame.pack(side='left')
        
        # Eraser tool - square button
        self.eraser_btn = ModernWidgets.create_square_button(
            tools_frame, "Eraser", "⬜",
            command=self.toggle_eraser,
            style="Tool.TButton"
        )
        self.eraser_btn.pack(side='left', padx=(0, 8))
        
        # Brush tool - square button
        self.brush_btn = ModernWidgets.create_square_button(
            tools_frame, "Brush", "⬛",
            command=self.toggle_brush,
            style="Tool.TButton"
        )
        self.brush_btn.pack(side='left', padx=(0, 8))
        
        # Brush size controls (conditional)
        self.brush_size_frame = ttk.Frame(tools_frame)
        
        ttk.Label(self.brush_size_frame, text="Size:", style="Secondary.TLabel").pack(side='left')
        self.brush_size_scale = ttk.Scale(self.brush_size_frame, from_=5, to=100,
                                         orient='horizontal', length=120,
                                         style='TScale',
                                         command=self.on_brush_size_changed)
        self.brush_size_scale.set(self.state.view_state.brush_size)
        self.brush_size_scale.pack(side='left', padx=(8, 8))
        
        # Show actual brush size regardless of zoom
        actual_size = int(self.state.view_state.brush_size)
        self.brush_size_label = ttk.Label(self.brush_size_frame, 
                                         text=f"{actual_size}px",
                                         style="Mono.TLabel")
        self.brush_size_label.pack(side='left')
        
        # Separator
        ModernWidgets.add_visual_separator(toolbar_frame, orient='vertical')
        
        # View controls
        view_frame = ttk.Frame(toolbar_frame)
        view_frame.pack(side='left')
        
        # Single cycling view button that changes between all view modes
        self.view_cycle_btn = ModernWidgets.create_icon_button(
            view_frame, "Single", "🔍",
            command=self.cycle_view_mode,
            style="Tool.TButton"
        )
        self.view_cycle_btn.pack(side='left', padx=(0, 8))
        
        # Overlay toggle (separate from view modes)
        self.overlay_btn = ModernWidgets.create_icon_button(
            view_frame, "Overlay", "👁️",
            command=self.toggle_overlay,
            style="Tool.TButton"
        )
        self.overlay_btn.pack(side='left', padx=(0, 8))
        
        # Overlay opacity (conditional)
        self.opacity_frame = ttk.Frame(view_frame)
        
        ttk.Label(self.opacity_frame, text="Opacity:", style="Secondary.TLabel").pack(side='left')
        self.opacity_scale = ttk.Scale(self.opacity_frame, from_=0.1, to=1.0,
                                      orient='horizontal', length=100,
                                      style='Red.Horizontal.TScale',
                                      command=self.on_opacity_changed)
        self.opacity_scale.set(self.state.view_state.overlay_opacity)
        self.opacity_scale.pack(side='left', padx=(8, 8))
        
        self.opacity_label = ttk.Label(self.opacity_frame, 
                                      text=f"{int(self.state.view_state.overlay_opacity * 100)}%",
                                      style="Mono.TLabel")
        self.opacity_label.pack(side='left')
        
        # Right side controls
        right_frame = ttk.Frame(toolbar_frame)
        right_frame.pack(side='right')
        
        # Processing time indicator
        self.time_frame, self.time_label = ModernWidgets.create_value_display(
            right_frame, "🕰️", "--"
        )
        
        # Export button
        self.export_btn = ModernWidgets.create_icon_button(
            right_frame, "Export", "📤",
            command=self.callbacks.get('export_image'),
            style="Accent.TButton"
        )
        self.export_btn.pack(side='left', padx=(20, 0))
    
    def toggle_eraser(self):
        """Toggle eraser tool"""
        if self.state.view_state.tool_mode == ToolMode.ERASER:
            self.state.set_tool_mode(ToolMode.NONE)
        else:
            self.state.set_tool_mode(ToolMode.ERASER)
    
    def toggle_brush(self):
        """Toggle brush tool"""
        if self.state.view_state.tool_mode == ToolMode.BRUSH:
            self.state.set_tool_mode(ToolMode.NONE)
        else:
            self.state.set_tool_mode(ToolMode.BRUSH)
    
    def cycle_view_mode(self):
        """Cycle through all view modes"""
        modes = [ProcessingMode.SINGLE, ProcessingMode.SIDE_BY_SIDE, ProcessingMode.SPLIT_SLIDER]
        current_index = modes.index(self.state.view_state.processing_mode)
        next_mode = modes[(current_index + 1) % len(modes)]
        self.state.set_processing_mode(next_mode)
    
    def toggle_overlay(self):
        """Toggle overlay visibility"""
        self.state.toggle_overlay()
    
    def on_brush_size_changed(self, value):
        """Handle brush size change"""
        size = int(float(value))
        self.state.view_state.brush_size = size
        if hasattr(self, 'brush_size_label'):
            self.brush_size_label.config(text=f"{size}px")
    
    def on_opacity_changed(self, value):
        """Handle opacity change"""
        opacity = float(value)
        self.state.view_state.overlay_opacity = opacity
        if hasattr(self, 'opacity_label'):
            self.opacity_label.config(text=f"{int(opacity * 100)}%")
        self.state.notify_observers()
    
    def update_ui(self):
        """Update UI based on current state"""
        # Update tool button states
        eraser_active = self.state.view_state.tool_mode == ToolMode.ERASER
        brush_active = self.state.view_state.tool_mode == ToolMode.BRUSH
        
        self.eraser_btn.config(text="⬜\nEraser" if not eraser_active else "✅\nEraser")
        self.brush_btn.config(text="⬛\nBrush" if not brush_active else "✅\nBrush")
        
        # Show/hide brush size controls
        if eraser_active or brush_active:
            self.brush_size_frame.pack(side='left', padx=(0, 8))
        else:
            self.brush_size_frame.pack_forget()
        
        # Update view cycle button
        mode_text = {
            ProcessingMode.SINGLE: "🔍 Single",
            ProcessingMode.SIDE_BY_SIDE: "🔄 Side by Side",
            ProcessingMode.SPLIT_SLIDER: "✂️ Split View"
        }
        self.view_cycle_btn.config(text=mode_text[self.state.view_state.processing_mode])
        
        # Update overlay button
        overlay_text = "🙈 Hide" if not self.state.view_state.hide_detections else "👁️ Show"
        self.overlay_btn.config(text=f"{overlay_text} Overlay")
        
        # Show/hide opacity controls
        if self.state.dust_mask and not self.state.view_state.hide_detections:
            self.opacity_frame.pack(side='left', padx=(0, 8))
        else:
            self.opacity_frame.pack_forget()
        
        # Update processing time
        if self.state.processing_state.processing_time > 0:
            self.time_frame.pack(side='left', padx=(0, 16))
            self.time_label.config(text=f"{self.state.processing_state.processing_time:.2f}s")
        else:
            self.time_frame.pack_forget()
        
        # Update button states
        has_tools = self.state.dust_mask is not None
        self.eraser_btn.config(state='normal' if has_tools else 'disabled')
        self.brush_btn.config(state='normal' if has_tools else 'disabled')
        self.overlay_btn.config(state='normal' if has_tools else 'disabled')
        
        self.export_btn.config(state='normal' if self.state.processed_image else 'disabled')


class ZoomControls(SpotlessFrame):
    """Zoom controls widget"""
    
    def __init__(self, parent, state: DustRemovalState, **kwargs):
        super().__init__(parent, **kwargs)
        self.state = state
        
        self.setup_ui()
        self.state.add_observer(self.update_ui)
    
    def setup_ui(self):
        """Setup zoom controls"""
        # Style the container
        self.configure(style="Card.TFrame", padding=8)
        
        # Zoom out button
        self.zoom_out_btn = ttk.Button(self, text="−", width=3,
                                      style="Tool.TButton",
                                      command=self.state.zoom_out)
        self.zoom_out_btn.pack(side='left')
        
        # Zoom level display
        self.zoom_label = ttk.Label(self, text="100%", width=6, style="Mono.TLabel")
        self.zoom_label.pack(side='left', padx=4)
        
        # Zoom in button
        self.zoom_in_btn = ttk.Button(self, text="+", width=3,
                                     style="Tool.TButton",
                                     command=self.state.zoom_in)
        self.zoom_in_btn.pack(side='left')
        
        # Reset button
        self.reset_btn = ttk.Button(self, text="⌂", width=3,
                                   style="Tool.TButton",
                                   command=self.state.reset_zoom)
        self.reset_btn.pack(side='left', padx=(8, 0))
    
    def update_ui(self):
        """Update zoom controls"""
        zoom_percent = int(self.state.view_state.zoom_scale * 100)
        self.zoom_label.config(text=f"{zoom_percent}%")
        
        # Update button states
        self.zoom_out_btn.config(state='normal' if self.state.view_state.zoom_scale > 1.0 else 'disabled')
        self.zoom_in_btn.config(state='normal' if self.state.view_state.zoom_scale < 5.0 else 'disabled')
        
        can_reset = (self.state.view_state.zoom_scale != 1.0 or 
                    self.state.view_state.drag_offset != (0.0, 0.0))
        self.reset_btn.config(state='normal' if can_reset else 'disabled')
