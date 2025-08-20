#!/usr/bin/env python3
"""
OpenGL image preview for Spotless Film (Tkinter integration via pyopengltk)

Dependencies:
  pip install PyOpenGL pyopengltk
"""

from typing import Optional, Tuple

try:
    from pyopengltk import OpenGLFrame as TkOpenGLFrame
    from OpenGL.GL import (
        glClearColor, glClear, GL_COLOR_BUFFER_BIT,
        glViewport, glMatrixMode, GL_PROJECTION, GL_MODELVIEW,
        glLoadIdentity, glOrtho, glEnable, GL_TEXTURE_2D, glDisable,
        glBindTexture, glTexParameteri, GL_TEXTURE_MIN_FILTER, GL_TEXTURE_MAG_FILTER,
        GL_LINEAR, glTexImage2D, GL_RGBA, GL_UNSIGNED_BYTE,
        glGenTextures, glBegin, glEnd, GL_QUADS, glTexCoord2f, glVertex2f,
        glBlendFunc, glEnableClientState, glDisableClientState,
        GL_BLEND, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA
    )
    OPENGL_AVAILABLE = True
    _IMPORT_ERROR = None
except Exception as _e:
    OPENGL_AVAILABLE = False
    _IMPORT_ERROR = str(_e)

from PIL import Image
import numpy as np
import time


if OPENGL_AVAILABLE:
    class GLImageView(TkOpenGLFrame):
        """A lightweight GL viewer that draws a base image and an optional RGBA overlay."""

        def __init__(self, master=None, **kw):
            super().__init__(master, **kw)
            self.base_image: Optional[Image.Image] = None
            self.overlay_image: Optional[Image.Image] = None

            self.base_tex: Optional[int] = None
            self.overlay_tex: Optional[int] = None
            self.base_size: Tuple[int, int] = (1, 1)

            self.zoom: float = 1.0
            self.offset: Tuple[float, float] = (0.0, 0.0)

            self._needs_upload = False

    # Public API
    def set_images(self, base: Optional[Image.Image], overlay_rgba: Optional[Image.Image]):
        t0 = time.time()
        self.base_image = base
        self.overlay_image = overlay_rgba
        if base is not None:
            self.base_size = base.size
        self._needs_upload = True
        print(f"[GL] set_images: base={None if base is None else base.size}, overlay={None if overlay_rgba is None else overlay_rgba.size}")
        print(f"[GL] set_images took {(time.time()-t0)*1000:.2f} ms (flagged for upload)")
        self.after_idle(self.redraw)

    def set_view(self, zoom: float, offset: Tuple[float, float]):
        print(f"[GL] set_view: zoom={zoom:.3f}, offset=({offset[0]:.1f},{offset[1]:.1f})")
        self.zoom = max(zoom, 0.01)
        self.offset = offset
        self.after_idle(self.redraw)

        # OpenGL lifecycle
        def initgl(self):
            glClearColor(0.118, 0.118, 0.118, 1.0)  # ~#1E1E1E
            glEnable(GL_TEXTURE_2D)
            glEnable(GL_BLEND)
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

        def redraw(self):
            t0 = time.time()
            width, height = self.width, self.height
            glViewport(0, 0, width, height)
            glClear(GL_COLOR_BUFFER_BIT)

            glMatrixMode(GL_PROJECTION)
            glLoadIdentity()
            glOrtho(0, width, height, 0, -1, 1)
            glMatrixMode(GL_MODELVIEW)
            glLoadIdentity()

            if self.base_image is None:
                self.swapbuffers()
                return

            if self._needs_upload:
                self._upload_textures()

            # Compute fitted size, then apply zoom and pan
            img_w, img_h = self.base_size
            if img_w <= 0 or img_h <= 0:
                self.swapbuffers()
                return

            # Fit to view, keep aspect
            scale = min(width / img_w, height / img_h)
            disp_w = img_w * scale * self.zoom
            disp_h = img_h * scale * self.zoom
            cx = width * 0.5 + self.offset[0]
            cy = height * 0.5 + self.offset[1]

            x0 = cx - disp_w * 0.5
            y0 = cy - disp_h * 0.5
            x1 = cx + disp_w * 0.5
            y1 = cy + disp_h * 0.5

            # Draw base
            if self.base_tex is not None:
                glBindTexture(GL_TEXTURE_2D, self.base_tex)
                glBegin(GL_QUADS)
                glTexCoord2f(0.0, 1.0); glVertex2f(x0, y1)
                glTexCoord2f(1.0, 1.0); glVertex2f(x1, y1)
                glTexCoord2f(1.0, 0.0); glVertex2f(x1, y0)
                glTexCoord2f(0.0, 0.0); glVertex2f(x0, y0)
                glEnd()

            # Draw overlay
            if self.overlay_tex is not None:
                glBindTexture(GL_TEXTURE_2D, self.overlay_tex)
                glBegin(GL_QUADS)
                glTexCoord2f(0.0, 1.0); glVertex2f(x0, y1)
                glTexCoord2f(1.0, 1.0); glVertex2f(x1, y1)
                glTexCoord2f(1.0, 0.0); glVertex2f(x1, y0)
                glTexCoord2f(0.0, 0.0); glVertex2f(x0, y0)
                glEnd()

            self.swapbuffers()
            print(f"[GL] redraw done in {(time.time()-t0)*1000:.2f} ms (upload={self._needs_upload})")

    # Helpers
        def _upload_textures(self):
            t0 = time.time()
            # Base
            if self.base_image is not None:
                base_rgba = self.base_image.convert('RGBA')
                base_bytes = base_rgba.tobytes('raw', 'RGBA')
                self.base_tex = self.base_tex or glGenTextures(1)
                glBindTexture(GL_TEXTURE_2D, self.base_tex)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
                glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, base_rgba.width, base_rgba.height, 0,
                             GL_RGBA, GL_UNSIGNED_BYTE, base_bytes)

            # Overlay
            if self.overlay_image is not None:
                ov = self.overlay_image.convert('RGBA')
                ov_bytes = ov.tobytes('raw', 'RGBA')
                self.overlay_tex = self.overlay_tex or glGenTextures(1)
                glBindTexture(GL_TEXTURE_2D, self.overlay_tex)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
                glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, ov.width, ov.height, 0,
                             GL_RGBA, GL_UNSIGNED_BYTE, ov_bytes)
            else:
                self.overlay_tex = None

            self._needs_upload = False
            print(f"[GL] _upload_textures: base={None if self.base_image is None else self.base_image.size}, overlay={None if self.overlay_image is None else self.overlay_image.size}, took {(time.time()-t0)*1000:.2f} ms")
else:
    class GLImageView:  # stub to provide informative error if used when unavailable
        def __init__(self, *args, **kwargs):
            raise RuntimeError(f"OpenGL unavailable: {_IMPORT_ERROR}")


GL_IMPORT_ERROR = _IMPORT_ERROR
__all__ = ["GLImageView", "OPENGL_AVAILABLE", "GL_IMPORT_ERROR"]


