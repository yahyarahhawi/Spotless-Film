# Spotless Film: Dust Removal for Scanned Film Photographs

A complete dust removal pipeline for scanned film photographs using deep learning. The system combines **U-Net dust detection** with **LaMa deep learning inpainting** for state-of-the-art film restoration.

## Key Features

- **Synthetic Training Data Generation**: Creates realistic dust patterns without manual annotation
- **U-Net Architecture**: Optimized for 1024x1024 grayscale dust detection  
- **LaMa Deep Learning Inpainting**: State-of-the-art texture synthesis for large dust areas
- **Complete Pipeline**: End-to-end detection and inpainting workflow
- **4x Expanded Dataset**: ~2400 diverse film photographs for training

## Project Structure

```
├── main.ipynb              # Complete development workflow
├── film-dataset/           # Training images (~2400 images)
├── models/                 # Model checkpoints (.pth files)
├── examples/               # Example input/output images
├── src/                    # Application source code
├── docs/                   # Documentation
├── checkpoints/            # Additional model checkpoints
└── CLAUDE.md              # Detailed implementation notes
```

## Quick Start

1. **Training**: Open `main.ipynb` and run the notebook cells to train the U-Net model
2. **Inference**: Use the patch-based inference pipeline for dust detection
3. **Inpainting**: Apply LaMa or fallback CV2 methods for dust removal

## Architecture

### Synthetic Data Generation
- Realistic dust patterns: elliptical blobs, linear scratches, squiggly hairs
- Enhanced randomness with ±20% parameter variations
- Per-element blur randomization for training diversity

### U-Net Model
- Encoder-decoder architecture for 1024x1024 grayscale images
- Single input/output channel for dust probability maps
- Skip connections for detail preservation
- Improved training with dice_bce_loss()

### Inference Pipeline
- Patch-based processing with 1024x1024 patches
- 512 stride (50% overlap) for seamless reconstruction
- Weighted averaging for smooth results
- Device-agnostic (MPS/CUDA/CPU support)

## Requirements

- PyTorch
- NumPy
- OpenCV
- Pillow
- LaMa-cleaner (optional, for deep learning inpainting)

## Results

The system demonstrates significant improvements over traditional CV2 inpainting methods, especially for:
- Large dust areas and complex textures
- Film grain preservation
- Natural texture synthesis
- High-resolution image processing

## Citation

If you use this work in your research, please cite:

```
Spotless Film: Deep Learning Dust Removal for Scanned Film Photographs
U-Net Architecture with Synthetic Training Data Generation
```

## License

MIT License - see LICENSE file for details.