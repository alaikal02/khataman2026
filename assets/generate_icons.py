import os
from PIL import Image, ImageDraw, ImageFont

def draw_font_icon(font_path, font_size, size_px, is_adaptive=False):
    # Create canvas
    canvas = Image.new("RGBA", (size_px, size_px), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    
    # Load MaterialIcons font
    font = ImageFont.truetype(font_path, font_size)
    
    # Character code for Icons.menu_book_rounded (\uf8b4)
    char_code = "\uf8b4"
    
    # Get exact bounding box
    bbox = draw.textbbox((0, 0), char_code, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    
    # Center perfectly
    x = (size_px - text_w) / 2 - bbox[0]
    y = (size_px - text_h) / 2 - bbox[1]
    
    # Draw pure white book icon
    draw.text((x, y), char_code, font=font, fill=(255, 255, 255, 255))
    return canvas

def draw_gradient_background(size_px, color1, color2):
    # Create linear gradient from Top-Left to Bottom-Right
    base = Image.new("RGBA", (size_px, size_px))
    for y in range(size_px):
        for x in range(size_px):
            # Diagonal ratio along TL-to-BR
            ratio = (x + y) / (size_px * 2)
            r = int(color1[0] + (color2[0] - color1[0]) * ratio)
            g = int(color1[1] + (color2[1] - color1[1]) * ratio)
            b = int(color1[2] + (color2[2] - color1[2]) * ratio)
            base.putpixel((x, y), (r, g, b, 255))
    return base

def generate_all_icons():
    os.makedirs("assets/images", exist_ok=True)
    
    font_path = "/home/el-fajra/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf"
    
    # Light Theme Gradient: [Color(0xFF2ECC71), Color(0xFF1A8A4A)]
    light_c1 = (46, 204, 113)
    light_c2 = (26, 138, 74)
    
    # Dark Theme Gradient: [Color(0xFF0F3E2B), Color(0xFF1B593F)]
    dark_c1 = (15, 62, 43)
    dark_c2 = (27, 89, 63)
    
    # 1. Generate Light Theme App Icon (app_icon.png)
    # Size 512x512, font size 260px (perfectly scaled and centered, around 50% width)
    icon_light = draw_gradient_background(512, light_c1, light_c2)
    book_light = draw_font_icon(font_path, 268, 512)
    icon_light.alpha_composite(book_light)
    icon_light.save("assets/images/app_icon.png", "PNG")
    print("Successfully generated assets/images/app_icon.png")

    # 2. Generate Dark Theme App Icon (app_icon_dark.png)
    icon_dark = draw_gradient_background(512, dark_c1, dark_c2)
    book_dark = draw_font_icon(font_path, 268, 512)
    icon_dark.alpha_composite(book_dark)
    icon_dark.save("assets/images/app_icon_dark.png", "PNG")
    print("Successfully generated assets/images/app_icon_dark.png")

    # 3. Generate Android Adaptive Foreground Icon (adaptive_foreground.png)
    # Transparent background, font size 220px to fit perfectly within safe-zone
    adaptive_foreground = draw_font_icon(font_path, 220, 512)
    adaptive_foreground.save("assets/images/adaptive_foreground.png", "PNG")
    print("Successfully generated assets/images/adaptive_foreground.png")

if __name__ == "__main__":
    generate_all_icons()
