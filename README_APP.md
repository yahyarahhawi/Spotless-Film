# Film Dust Removal GUI Application

A simple drag-and-drop desktop application for removing dust from scanned film photographs using trained U-Net models.

## Features

- **Drag & Drop Interface** - Simply drag your image and model weights files
- **Adjustable Threshold** - Fine-tune dust detection sensitivity
- **Multiple Inpainting Methods**:
  - LaMa (Deep Learning) - State-of-the-art results
  - CV2 Advanced - Multi-pass traditional inpainting
  - CV2 TELEA - Fast Marching Method
  - CV2 Navier-Stokes - Fluid dynamics based
- **Automatic Saving** - Saves results with `_dust_removal` suffix
- **Progress Tracking** - Real-time processing updates
- **Cross-Platform** - Works on Windows, macOS, Linux

## Installation

1. **Install Python Dependencies**:
   ```bash
   pip install -r requirements_app.txt
   ```

2. **Optional - Install LaMa for Deep Learning Inpainting**:
   ```bash
   pip install lama-cleaner
   ```
   *Note: May require Rust compiler. If installation fails, the app will fall back to CV2 methods.*

## Usage

1. **Run the Application**:
   ```bash
   python dust_removal_app.py
   ```

2. **Load Files**:
   - Drag your image file (`.jpg`, `.jpeg`, `.png`) to the top area, or click "Browse Image"
   - Drag your trained model weights (`.pth` file) to the bottom area, or click "Browse Weights"

3. **Configure Settings**:
   - **Detection Threshold**: Lower values detect more dust (0.001-0.05, default: 0.005)
   - **Inpainting Method**: Choose between LaMa deep learning or CV2 traditional methods

4. **Process**:
   - Click "🎯 Remove Dust & Save"
   - Watch the progress bar and status updates
   - Result will be saved in the same directory as the original image with `_dust_removal` suffix

## Model Weights

The app works with U-Net model weights trained on the dust detection dataset. Compatible with:
- `v3_bce_unet_epoch03.pth`
- `bce_unet_epochXX.pth`
- Any `.pth` file with the same U-Net architecture

## Example Workflow

1. **Input**: `my_film_scan.jpg` + `v3_bce_unet_epoch03.pth`
2. **Settings**: Threshold = 0.005, Method = LaMa
3. **Output**: `my_film_scan_dust_removal.jpg` (automatically saved)

## Technical Details

- **Patch-based Processing**: Handles large images with 1024x1024 patches and 512-pixel stride
- **Device Detection**: Automatically uses MPS (Apple Silicon), CUDA (NVIDIA GPU), or CPU
- **Memory Efficient**: Processes images in patches to handle any size
- **Multi-threaded**: GUI remains responsive during processing

## Troubleshooting

### Common Issues

1. **"Failed to load model"**:
   - Ensure the `.pth` file is compatible with the U-Net architecture
   - Check that the file isn't corrupted

2. **"LaMa not available"**:
   - LaMa requires additional installation: `pip install lama-cleaner`
   - May need Rust compiler - use CV2 methods if installation fails

3. **Slow processing**:
   - Large images take longer to process
   - GPU/MPS acceleration significantly speeds up processing
   - Consider reducing image size for faster processing

4. **Memory errors**:
   - Close other applications to free up memory
   - The app uses patch-based processing to minimize memory usage

### Performance Tips

- **Use GPU**: Ensure CUDA (NVIDIA) or MPS (Apple Silicon) is available for faster processing
- **Optimal threshold**: Start with 0.005 and adjust based on results
- **LaMa vs CV2**: LaMa produces better results but takes longer to process

## Requirements

- Python 3.8+
- PyTorch 2.0+
- GUI libraries (tkinter, tkinterdnd2)
- Image processing libraries (OpenCV, Pillow)

## File Structure

```
dust_removal_app.py     # Main application
requirements_app.txt    # Python dependencies
README_APP.md          # This file
```

The app integrates seamlessly with the training pipeline from `main.ipynb` - simply use the trained model weights in the GUI!