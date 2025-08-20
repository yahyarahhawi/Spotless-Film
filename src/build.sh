#!/bin/bash

# Simple build script for SpotlessFilm executable
# Run this from the src/ directory

echo "🚀 Building SpotlessFilm executable..."

# Check if we're in the right directory
if [ ! -f "spotless_film_modern.py" ]; then
    echo "❌ Error: Please run this script from the src/ directory"
    exit 1
fi

# Install PyInstaller if not installed
python -c "import PyInstaller" 2>/dev/null || {
    echo "📦 Installing PyInstaller..."
    pip install pyinstaller
}

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf build dist __pycache__ distribution

# Build executable
echo "🔨 Building executable..."
python build_executable.py

echo "✅ Build complete! Check the distribution/ folder"