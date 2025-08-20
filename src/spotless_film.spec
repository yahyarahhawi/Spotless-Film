# -*- mode: python ; coding: utf-8 -*-

block_cipher = None

a = Analysis(
    ['spotless_film_modern.py'],
    pathex=[],
    binaries=[],
    datas=[
        ('weights/*.pth', 'weights'),  # Include model weights
        ('*.py', '.'),  # Include all Python modules
    ],
    hiddenimports=[
        'torch',
        'torchvision', 
        'PIL',
        'PIL.Image',
        'PIL.ImageTk',
        'customtkinter',
        'tkinter',
        'numpy',
        'cv2',
        'threading',
        'dataclasses',
        'enum',
        'typing',
        'lama_cleaner',
        'lama_cleaner.model_manager',
        'lama_cleaner.schema',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        'matplotlib',
        'jupyter',
        'notebook',
        'ipython',
        'pandas',
        'scipy',
        'sklearn',
        'tensorflow',
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='SpotlessFilm',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,  # Set to True if you want console for debugging
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=None,  # Add icon path here if you have one: 'icon.ico'
)

# For macOS, create an app bundle
app = BUNDLE(
    exe,
    name='SpotlessFilm.app',
    icon=None,  # Add icon path here if you have one: 'icon.icns'
    bundle_identifier='com.spotlessfilm.app',
    info_plist={
        'NSHighResolutionCapable': 'True',
        'NSRequiresAquaSystemAppearance': 'False',
    },
)