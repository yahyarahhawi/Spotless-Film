#!/usr/bin/env python3
"""
Quick test script to test dust removal functionality
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))

from PIL import Image
import numpy as np
from image_processing import ImageProcessingService
import cv2

def test_basic_inpainting():
    """Test basic CV2 TELEA inpainting"""
    print("🧪 Testing basic CV2 TELEA inpainting...")
    
    # Create a simple test image (100x100 red square)
    test_image = Image.new('RGB', (100, 100), color='red')
    
    # Create a simple test mask (white circle in center)
    mask_array = np.zeros((100, 100), dtype=np.uint8)
    cv2.circle(mask_array, (50, 50), 20, 255, -1)
    test_mask = Image.fromarray(mask_array, mode='L')
    
    print(f"Test image size: {test_image.size}")
    print(f"Test mask size: {test_mask.size}")
    
    try:
        # Convert PIL images to numpy arrays
        image_np = np.array(test_image.convert('RGB'))
        mask_np = np.array(test_mask.convert('L'))
        
        print(f"Image shape: {image_np.shape}, Mask shape: {mask_np.shape}")
        
        # Test TELEA inpainting
        result = cv2.inpaint(image_np, mask_np, inpaintRadius=5, flags=cv2.INPAINT_TELEA)
        result_image = Image.fromarray(result)
        
        print("✅ Basic TELEA inpainting successful!")
        print(f"Result image size: {result_image.size}")
        return True
        
    except Exception as e:
        print(f"❌ Basic TELEA inpainting failed: {e}")
        return False

def test_dilate_mask():
    """Test mask dilation"""
    print("🧪 Testing mask dilation...")
    
    try:
        # Create a simple test mask
        mask_array = np.zeros((100, 100), dtype=np.uint8)
        cv2.circle(mask_array, (50, 50), 10, 255, -1)
        test_mask = Image.fromarray(mask_array, mode='L')
        
        # Test dilation
        dilated = ImageProcessingService.dilate_mask(test_mask)
        
        print("✅ Mask dilation successful!")
        print(f"Original mask size: {test_mask.size}, Dilated mask size: {dilated.size}")
        return True
        
    except Exception as e:
        print(f"❌ Mask dilation failed: {e}")
        return False

def test_blend_images():
    """Test image blending"""
    print("🧪 Testing image blending...")
    
    try:
        # Create test images
        original = Image.new('RGB', (100, 100), color='red')
        inpainted = Image.new('RGB', (100, 100), color='blue')
        
        # Create mask
        mask_array = np.zeros((100, 100), dtype=np.uint8)
        cv2.circle(mask_array, (50, 50), 20, 255, -1)
        mask = Image.fromarray(mask_array, mode='L')
        
        # Test blending
        blended = ImageProcessingService.blend_images(original, inpainted, mask)
        
        print("✅ Image blending successful!")
        print(f"Blended image size: {blended.size}")
        return True
        
    except Exception as e:
        print(f"❌ Image blending failed: {e}")
        return False

if __name__ == "__main__":
    print("🧪 Running dust removal component tests...")
    
    tests = [
        test_basic_inpainting,
        test_dilate_mask, 
        test_blend_images
    ]
    
    passed = 0
    total = len(tests)
    
    for test in tests:
        if test():
            passed += 1
        print()
    
    print(f"🧪 Test Results: {passed}/{total} tests passed")
    
    if passed == total:
        print("✅ All tests passed! Dust removal components are working.")
    else:
        print("❌ Some tests failed. Check the components above.")