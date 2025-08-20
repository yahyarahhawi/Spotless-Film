#!/usr/bin/env python3
"""
Simple Modern Theme for Spotless Film

A simplified, compatible modern theme system focusing on colors and layout
rather than complex ttk theming that can cause compatibility issues.
"""

import tkinter as tk
from tkinter import ttk

class SimpleModernColors:
    """Simple color palette for modern UI"""
    
    # Dark theme colors
    BG_DARK = "#1a1a1a"
    BG_MEDIUM = "#2a2a2a" 
    BG_LIGHT = "#3a3a3a"
    
    TEXT_WHITE = "#ffffff"
    TEXT_LIGHT = "#cccccc"
    TEXT_MEDIUM = "#999999"
    
    ACCENT_BLUE = "#007AFF"
    ACCENT_GREEN = "#34C759"
    ACCENT_ORANGE = "#FF9500"
    ACCENT_RED = "#FF453A"

class SimpleModernTheme:
    """Simple modern theme that focuses on what works reliably"""
    
    def __init__(self, root: tk.Tk):
        self.root = root
        self.colors = SimpleModernColors()
        self.setup_basic_theme()
    
    def setup_basic_theme(self):
        """Setup basic modern appearance"""
        # Root window
        self.root.configure(bg=self.colors.BG_DARK)
        
        # Get style object
        self.style = ttk.Style()
        
        try:
            # Use a basic theme
            self.style.theme_use("clam")
        except:
            pass
        
        # Configure what we can safely
        try:
            # Basic button style
            self.style.configure("Modern.TButton",
                               relief="flat",
                               padding=6,
                               font=("Helvetica", 10))
            
            # Accent button
            self.style.configure("Accent.TButton", 
                               relief="raised",
                               padding=8,
                               font=("Helvetica", 10, "bold"))
            
            # Labels
            self.style.configure("Modern.TLabel", font=("Helvetica", 10))
            self.style.configure("Title.TLabel", font=("Helvetica", 14, "bold"))
            self.style.configure("Small.TLabel", font=("Helvetica", 9))
            
            # Frames
            self.style.configure("Modern.TFrame", relief="flat")
            self.style.configure("Card.TFrame", relief="raised", borderwidth=1)
            
        except Exception as e:
            print(f"Theme setup warning: {e}")
    
    def apply_dark_colors(self, widget):
        """Apply dark colors to a widget"""
        try:
            widget.configure(bg=self.colors.BG_DARK)
        except:
            pass
    
    def create_modern_frame(self, parent, **kwargs):
        """Create a modern styled frame"""
        frame = tk.Frame(parent, 
                        bg=self.colors.BG_MEDIUM,
                        relief="flat",
                        bd=0,
                        **kwargs)
        return frame
    
    def create_card_frame(self, parent, **kwargs):
        """Create a card-style frame"""
        frame = tk.Frame(parent,
                        bg=self.colors.BG_LIGHT,
                        relief="raised",
                        bd=1,
                        **kwargs)
        return frame
    
    def create_modern_label(self, parent, text, style="normal", **kwargs):
        """Create a modern styled label"""
        colors = {
            "normal": self.colors.TEXT_WHITE,
            "secondary": self.colors.TEXT_LIGHT,
            "tertiary": self.colors.TEXT_MEDIUM
        }
        
        fonts = {
            "normal": ("Helvetica", 10),
            "title": ("Helvetica", 14, "bold"),
            "small": ("Helvetica", 9),
            "mono": ("Courier", 9)
        }
        
        color = colors.get(style, self.colors.TEXT_WHITE)
        font = fonts.get(style, ("Helvetica", 10))
        
        label = tk.Label(parent,
                        text=text,
                        bg=self.colors.BG_MEDIUM,
                        fg=color,
                        font=font,
                        **kwargs)
        return label
    
    def create_modern_button(self, parent, text, command=None, style="normal", **kwargs):
        """Create a modern styled button"""
        if style == "accent":
            btn = tk.Button(parent,
                          text=text,
                          command=command,
                          bg=self.colors.ACCENT_BLUE,
                          fg=self.colors.TEXT_WHITE,
                          relief="flat",
                          bd=0,
                          font=("Helvetica", 10, "bold"),
                          padx=12,
                          pady=6,
                          **kwargs)
        elif style == "success":
            btn = tk.Button(parent,
                          text=text,
                          command=command,
                          bg=self.colors.ACCENT_GREEN,
                          fg=self.colors.TEXT_WHITE,
                          relief="flat",
                          bd=0,
                          font=("Helvetica", 10, "bold"),
                          padx=12,
                          pady=6,
                          **kwargs)
        else:
            btn = tk.Button(parent,
                          text=text,
                          command=command,
                          bg=self.colors.BG_LIGHT,
                          fg=self.colors.TEXT_WHITE,
                          relief="flat",
                          bd=1,
                          font=("Helvetica", 10),
                          padx=10,
                          pady=4,
                          **kwargs)
        
        # Add hover effects
        self.add_hover_effect(btn, style)
        return btn
    
    def add_hover_effect(self, button, style="normal"):
        """Add hover effect to button"""
        original_bg = button.cget('bg')
        
        def on_enter(e):
            if style == "accent":
                button.configure(bg="#0056CC")
            elif style == "success":
                button.configure(bg="#28A745") 
            else:
                button.configure(bg=self.colors.BG_LIGHT)
        
        def on_leave(e):
            button.configure(bg=original_bg)
        
        button.bind("<Enter>", on_enter)
        button.bind("<Leave>", on_leave)