# Building SpotlessFilm Executable

This guide shows you how to create a standalone executable that your friends can run without installing Python.

## Quick Build (Recommended)

1. **Navigate to the src directory:**
   ```bash
   cd /Users/yahyarahhawi/Developer/Dust-Removal-UNet/src
   ```

2. **Run the automated build script:**
   ```bash
   python build_executable.py
   ```

The script will:
- ✅ Check and install PyInstaller
- ✅ Verify all dependencies are installed
- ✅ Clean previous builds
- ✅ Create the executable
- ✅ Package everything in a `distribution/` folder

## Manual Build (Advanced)

If you prefer manual control:

1. **Install PyInstaller:**
   ```bash
   pip install pyinstaller
   ```

2. **Build the executable:**
   ```bash
   pyinstaller --clean spotless_film.spec
   ```

## Output Files

After building, you'll find:

### macOS:
- `distribution/SpotlessFilm.app` - The application bundle
- Double-click to run, or drag to Applications folder

### Windows:
- `distribution/SpotlessFilm.exe` - The executable
- Just double-click to run

### Linux:
- `distribution/SpotlessFilm` - The executable
- Make executable: `chmod +x SpotlessFilm`

## Sharing with Friends

1. **Zip the distribution folder:**
   ```bash
   cd distribution
   zip -r SpotlessFilm.zip .
   ```

2. **Send the zip file to your friend**

3. **Your friend should:**
   - Extract the zip file
   - Double-click the executable to run
   - No Python installation needed!

## File Size Expectations

- **macOS**: ~500MB - 1GB (includes all dependencies)
- **Windows**: ~300MB - 800MB 
- **Linux**: ~400MB - 900MB

The large size is normal - it includes Python, PyTorch, and all dependencies.

## Troubleshooting

### Build Fails
- Make sure you're in the `src/` directory
- Install missing dependencies: `pip install -r requirements_spotless_film.txt`
- Try cleaning: `rm -rf build dist __pycache__`

### Executable Won't Start
- Run from terminal to see error messages
- Check system requirements (4GB+ RAM recommended)
- Make sure model weights are in the `weights/` folder

### Large File Size
- This is normal for PyTorch applications
- Consider using file compression for distribution
- Size can be reduced by excluding unused dependencies

## Model Weights

**Important**: Make sure your model weights (`.pth` files) are in the `src/weights/` directory before building. The executable will include them automatically.

## Platform-Specific Notes

### macOS
- The app may show "unidentified developer" warning
- Right-click → Open → Open to bypass security warning
- Or run: `sudo xattr -rd com.apple.quarantine SpotlessFilm.app`

### Windows
- Windows Defender may flag the executable initially
- Add exception if needed

### Linux
- Make sure the executable has run permissions
- Some distributions may need additional system libraries

## Advanced Options

Edit `spotless_film.spec` to customize:
- Add application icon
- Include/exclude specific modules
- Adjust console visibility for debugging
- Change app bundle settings

Happy building! 🚀