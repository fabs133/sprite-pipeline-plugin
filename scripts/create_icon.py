"""Create plugin icon (128x128 PNG) using PIL"""
from PIL import Image, ImageDraw, ImageFont
import os

# Create 128x128 image with Godot blue background
img = Image.new('RGB', (128, 128), color='#478cbf')
draw = ImageDraw.Draw(img)

# AI Brain/Circuit (top left)
draw.ellipse([27, 32, 43, 48], fill='#ffffff', outline=None)  # Main circle
draw.ellipse([44, 29, 56, 41], fill='#e8f4f8', outline=None)  # Small circle 1
draw.ellipse([43, 43, 53, 53], fill='#d0e8f0', outline=None)  # Small circle 2
draw.line([35, 40, 47, 35], fill='#ffffff', width=2)  # Connection 1
draw.line([45, 45, 48, 48], fill='#ffffff', width=2)  # Connection 2

# Arrow (pipeline flow) in gold/yellow
arrow_points = [(60, 40), (75, 40), (75, 35), (85, 45), (75, 55), (75, 50), (60, 50)]
draw.polygon(arrow_points, fill='#ffd500')

# Pixel Sprite Grid (bottom right) - 3x3 checkerboard
colors = ['#ffffff', '#e8f4f8']
for row in range(3):
    for col in range(3):
        x = 75 + col * 13
        y = 70 + row * 13
        color_idx = (row + col) % 2
        draw.rectangle([x, y, x + 12, y + 12], fill=colors[color_idx])

# Add text "AI → SPRITES" at bottom
try:
    # Try to use a nice font if available
    font = ImageFont.truetype("arial.ttf", 11)
except:
    font = ImageFont.load_default()

text = "AI → SPRITES"
# Get text bbox for centering
bbox = draw.textbbox((0, 0), text, font=font)
text_width = bbox[2] - bbox[0]
text_x = (128 - text_width) // 2
draw.text((text_x, 112), text, fill='#ffffff', font=font)

# Save icon
output_path = os.path.join(os.path.dirname(__file__), '..', 'addons', 'sprite_pipeline', 'icon.png')
img.save(output_path, 'PNG')
print(f"[OK] Icon created: {output_path}")
