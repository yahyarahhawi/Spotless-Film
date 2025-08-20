#!/usr/bin/env python3
"""
Spotless Film Application Package

A professional-grade dust removal application with advanced UI/UX
matching the original Spotless-Film interface and functionality.
"""

__version__ = "2.0.0"
__author__ = "Dust Removal Team"
__description__ = "Spotless Film - AI-powered film dust removal application"

# Import main components for easy access
from .dust_removal_state import DustRemovalState, ProcessingMode, ToolMode
from .professional_dust_removal_app import SpotlessFilmApp
from .image_processing import ImageProcessingService, LamaInpainter, BrushTools
from .ui_components import SpotlessSidebar, SpotlessToolbar, ZoomControls
from .professional_canvas import SpotlessCanvas

__all__ = [
    'DustRemovalState',
    'ProcessingMode', 
    'ToolMode',
    'SpotlessFilmApp',
    'ImageProcessingService',
    'LamaInpainter',
    'BrushTools',
    'SpotlessSidebar',
    'SpotlessToolbar', 
    'ZoomControls',
    'SpotlessCanvas'
]
