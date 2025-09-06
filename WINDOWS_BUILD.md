# Building SpotlessFilm for Windows

## For Your Friend to Build on Windows:

### Prerequisites
1. **Download and install Python 3.9+** from https://python.org
   - ✅ Check "Add Python to PATH" during installation

### Build Steps
1. **Download the source code** (get the entire project folder)

2. **Open Command Prompt** (cmd) or PowerShell

3. **Navigate to the src folder:**
   ```cmd
   cd path\to\Dust-Removal-UNet\src
   ```

4. **Install required packages:**
   ```cmd
   pip install pyinstaller torch torchvision pillow customtkinter opencv-python numpy
   ```

5. **Build the executable:**
   ```cmd
   python build_executable.py
   ```

6. **Find the .exe file:**
   - Look in `distribution\SpotlessFilm.exe`
   - This is the Windows executable!

## Alternative Simple Build
If the automated script doesn't work:

```cmd
cd src
pip install pyinstaller
pyinstaller --onefile --windowed --name SpotlessFilm spotless_film_modern.py
```

The .exe will be in `dist\SpotlessFilm.exe`

## File Size
Expect ~300-800MB for the Windows executable (includes all dependencies).

## Sharing
Once built, just send the `SpotlessFilm.exe` file - no installation needed!