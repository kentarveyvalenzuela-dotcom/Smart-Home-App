#!/usr/bin/env python3
"""
Convert bulb SVG to Android launcher icons.
Requires: cairosvg and Pillow packages
"""

import os
import sys
from pathlib import Path

def generate_android_icons():
    """Generate Android launcher icons from SVG"""
    
    try:
        from cairosvg import svg2png
        from PIL import Image
    except ImportError:
        print("❌ Missing required packages. Installing...")
        os.system("pip install cairosvg pillow -q")
        from cairosvg import svg2png
        from PIL import Image
    
    svg_path = "assets/bulb_icon.svg"
    
    if not Path(svg_path).exists():
        print(f"❌ SVG file not found: {svg_path}")
        return False
    
    # Android icon sizes
    sizes = {
        'ldpi': 36,
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192,
    }
    
    base_dir = "android/app/src/main/res"
    
    print("🎨 Generating Android launcher icons...")
    
    for density, size in sizes.items():
        output_dir = Path(f"{base_dir}/mipmap-{density}")
        output_dir.mkdir(parents=True, exist_ok=True)
        output_file = output_dir / "ic_launcher.png"
        
        # Convert SVG to PNG at specified size
        try:
            svg2png(url=svg_path, write_to=str(output_file), output_width=size, output_height=size)
            print(f"✅ {density:8s} ({size:3d}x{size:3d}) -> {output_file}")
        except Exception as e:
            print(f"❌ {density}: {e}")
            return False
    
    # Also create adaptive icon (Android 8+)
    adaptive_dir = Path(f"{base_dir}/mipmap-anydpi-v33")
    adaptive_dir.mkdir(parents=True, exist_ok=True)
    
    # For foreground: use the same icon at 192x192
    fg_output = adaptive_dir.parent / "mipmap-xxxhdpi" / "ic_launcher_foreground.png"
    fg_output.parent.mkdir(parents=True, exist_ok=True)
    svg2png(url=svg_path, write_to=str(fg_output), output_width=192, output_height=192)
    print(f"✅ Adaptive foreground -> {fg_output}")
    
    print("\n✅ All Android launcher icons generated successfully!")
    return True

if __name__ == "__main__":
    success = generate_android_icons()
    sys.exit(0 if success else 1)
