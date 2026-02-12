"""Create itch.io cover image (630x500 PNG)"""
from PIL import Image, ImageDraw, ImageFont
import os

# Create 630x500 image with gradient background
img = Image.new('RGB', (630, 500), color='#2b5278')
draw = ImageDraw.Draw(img)

# Draw gradient-like effect with rectangles
for i in range(500):
    color_val = int(43 + (72 - 43) * (i / 500))  # Gradient from #2b to #48
    draw.line([(0, i), (630, i)], fill=(color_val, 82, 120))

# Draw large icon in center-left
icon_size = 180
icon_x = 80
icon_y = 160

# Icon background circle
draw.ellipse([icon_x - 10, icon_y - 10, icon_x + icon_size + 10, icon_y + icon_size + 10],
             fill='#ffffff', outline=None)
draw.ellipse([icon_x, icon_y, icon_x + icon_size, icon_y + icon_size],
             fill='#478cbf', outline=None)

# Icon elements (scaled up)
# AI Brain
draw.ellipse([icon_x + 30, icon_y + 40, icon_x + 70, icon_y + 80], fill='#ffffff')
draw.ellipse([icon_x + 60, icon_y + 30, icon_x + 90, icon_y + 60], fill='#e8f4f8')
draw.ellipse([icon_x + 55, icon_y + 65, icon_x + 80, icon_y + 90], fill='#d0e8f0')

# Arrow
arrow_points = [(icon_x + 90, icon_y + 60), (icon_x + 110, icon_y + 60),
                (icon_x + 110, icon_y + 50), (icon_x + 130, icon_y + 70),
                (icon_x + 110, icon_y + 90), (icon_x + 110, icon_y + 80),
                (icon_x + 90, icon_y + 80)]
draw.polygon(arrow_points, fill='#ffd500')

# Pixel grid
colors = ['#ffffff', '#e8f4f8']
for row in range(3):
    for col in range(3):
        x = icon_x + 110 + col * 20
        y = icon_y + 100 + row * 20
        color_idx = (row + col) % 2
        draw.rectangle([x, y, x + 18, y + 18], fill=colors[color_idx])

# Text content
try:
    title_font = ImageFont.truetype("arialbd.ttf", 56)
    subtitle_font = ImageFont.truetype("arial.ttf", 28)
    feature_font = ImageFont.truetype("arial.ttf", 20)
except:
    title_font = ImageFont.load_default()
    subtitle_font = ImageFont.load_default()
    feature_font = ImageFont.load_default()

# Title
title = "Sprite Pipeline"
draw.text((320, 100), title, fill='#ffffff', font=title_font)

# Subtitle
subtitle = "AI-Powered Sprite Generation"
draw.text((320, 170), subtitle, fill='#e8f4f8', font=subtitle_font)

# Features
features = [
    "Generate sprites in Godot Editor",
    "Multiple art styles",
    "Batch processing",
    "Smart caching"
]

y_pos = 240
for feature in features:
    draw.text((320, y_pos), f"• {feature}", fill='#ffffff', font=feature_font)
    y_pos += 35

# Footer
footer = "For Godot 4.2+ | MIT License"
draw.text((320, 460), footer, fill='#b0c8d8', font=feature_font)

# Save cover
output_path = os.path.join(os.path.dirname(__file__), '..', 'docs', 'cover.png')
os.makedirs(os.path.dirname(output_path), exist_ok=True)
img.save(output_path, 'PNG')
print(f"[OK] Cover image created: {output_path}")
