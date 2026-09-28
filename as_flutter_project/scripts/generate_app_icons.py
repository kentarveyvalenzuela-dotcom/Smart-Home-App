#!/usr/bin/env python3
"""
Generate Smart Home App launcher icons using PIL
Creates a lightbulb icon with gradient background
"""
import os
from PIL import Image, ImageDraw

# Android icon sizes
ANDROID_SIZES = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}

def create_smart_home_icon(size):
    """Create a smart home icon with lightbulb design"""
    # Create image with RGBA
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Background - blue gradient effect (solid blue for simplicity)
    # Rounded rectangle background
    padding = int(size * 0.1)
    corner_radius = int(size * 0.2)

    # Draw rounded rectangle background
    draw.rounded_rectangle(
        [padding, padding, size - padding, size - padding],
        radius=corner_radius,
        fill=(30, 60, 114)  # Dark blue #1E3C72
    )

    # Calculate positions
    center_x = size // 2
    bulb_center_y = int(size * 0.42)
    bulb_radius = int(size * 0.22)

    # Draw light rays first (behind bulb)
    ray_color = (255, 215, 0, 180)  # Gold with transparency
    ray_length = int(size * 0.08)
    ray_start = bulb_radius + int(size * 0.05)

    # Draw 8 rays around the bulb
    import math
    for i in range(8):
        angle = i * 45 * math.pi / 180
        x1 = center_x + int(ray_start * math.cos(angle))
        y1 = bulb_center_y + int(ray_start * math.sin(angle))
        x2 = center_x + int((ray_start + ray_length) * math.cos(angle))
        y2 = bulb_center_y + int((ray_start + ray_length) * math.sin(angle))
        draw.line([(x1, y1), (x2, y2)], fill=(255, 215, 0), width=max(2, size // 48))

    # Draw bulb glow (larger circle behind)
    glow_radius = bulb_radius + int(size * 0.05)
    draw.ellipse(
        [center_x - glow_radius, bulb_center_y - glow_radius,
         center_x + glow_radius, bulb_center_y + glow_radius],
        fill=(255, 215, 0, 100)  # Semi-transparent gold
    )

    # Draw main bulb (yellow/gold)
    draw.ellipse(
        [center_x - bulb_radius, bulb_center_y - bulb_radius,
         center_x + bulb_radius, bulb_center_y + bulb_radius],
        fill=(255, 200, 50),  # Bright gold
        outline=(255, 215, 0),
        width=max(1, size // 48)
    )

    # Draw highlight on bulb
    highlight_x = center_x - int(bulb_radius * 0.4)
    highlight_y = bulb_center_y - int(bulb_radius * 0.4)
    highlight_r = int(bulb_radius * 0.3)
    draw.ellipse(
        [highlight_x - highlight_r, highlight_y - highlight_r,
         highlight_x + highlight_r, highlight_y + highlight_r],
        fill=(255, 255, 255, 150)
    )

    # Draw bulb base (screw part)
    base_width = int(bulb_radius * 0.8)
    base_height = int(size * 0.08)
    base_top = bulb_center_y + bulb_radius - int(size * 0.02)

    draw.rounded_rectangle(
        [center_x - base_width//2, base_top,
         center_x + base_width//2, base_top + base_height],
        radius=2,
        fill=(192, 192, 192),  # Silver
        outline=(128, 128, 128)
    )

    # Draw socket
    socket_width = int(base_width * 0.9)
    socket_height = int(size * 0.05)
    socket_top = base_top + base_height

    draw.ellipse(
        [center_x - socket_width//2, socket_top,
         center_x + socket_width//2, socket_top + socket_height],
        fill=(169, 169, 169),
        outline=(105, 105, 105)
    )

    return img.convert('RGBA')

def main():
    # Paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.dirname(script_dir)
    res_dir = os.path.join(project_dir, 'android', 'app', 'src', 'main', 'res')

    print("🎨 Generating Smart Home App launcher icons...")
    print()

    # Generate icons for each Android density
    for folder, size in ANDROID_SIZES.items():
        output_dir = os.path.join(res_dir, folder)
        os.makedirs(output_dir, exist_ok=True)

        icon = create_smart_home_icon(size)
        output_path = os.path.join(output_dir, 'ic_launcher.png')

        # Convert to RGB for PNG without alpha issues
        background = Image.new('RGBA', icon.size, (30, 60, 114, 255))
        background.paste(icon, mask=icon.split()[3])
        background.convert('RGB').save(output_path, 'PNG')

        print(f"  ✅ Generated: {folder}/ic_launcher.png ({size}x{size})")

    # Generate web icons
    web_dir = os.path.join(project_dir, 'web', 'icons')
    os.makedirs(web_dir, exist_ok=True)

    for web_size, filename in [(192, 'Icon-192.png'), (512, 'Icon-512.png'),
                                (192, 'Icon-maskable-192.png'), (512, 'Icon-maskable-512.png')]:
        icon = create_smart_home_icon(web_size)
        background = Image.new('RGBA', icon.size, (30, 60, 114, 255))
        background.paste(icon, mask=icon.split()[3])
        background.convert('RGB').save(os.path.join(web_dir, filename), 'PNG')
        print(f"  ✅ Generated: web/icons/{filename} ({web_size}x{web_size})")

    # Generate favicon
    icon = create_smart_home_icon(32)
    background = Image.new('RGBA', icon.size, (30, 60, 114, 255))
    background.paste(icon, mask=icon.split()[3])
    background.convert('RGB').save(os.path.join(project_dir, 'web', 'favicon.png'), 'PNG')
    print(f"  ✅ Generated: web/favicon.png (32x32)")

    print()
    print("🎉 All icons generated successfully!")

if __name__ == '__main__':
    main()

