"""Generate QR codes for slide download links."""

import qrcode
from PIL import Image, ImageDraw, ImageFont

BASE = "https://vlussenburg.github.io/wiz-assignment-vincentlussenburg"

CODES = [
    ("qr-slides.png", f"{BASE}/", "SLIDES"),
    ("qr-pdf.png", f"{BASE}/output/slides.pdf", "PDF"),
    ("qr-pptx.png", f"{BASE}/output/slides.pptx", "PPTX"),
]


def generate(filename, url, label):
    qr = qrcode.QRCode(version=1, error_correction=qrcode.constants.ERROR_CORRECT_H, box_size=10, border=2)
    qr.add_data(url)
    qr.make(fit=True)
    img = qr.make_image(fill_color="#01123f", back_color="white").convert("RGB")

    # Add label below QR code
    font_size = 28
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", font_size)
    except OSError:
        font = ImageFont.load_default()

    label_height = 40
    combined = Image.new("RGB", (img.width, img.height + label_height), "white")
    combined.paste(img, (0, 0))

    draw = ImageDraw.Draw(combined)
    bbox = draw.textbbox((0, 0), label, font=font)
    text_w = bbox[2] - bbox[0]
    draw.text(((img.width - text_w) / 2, img.height + 4), label, fill="#0054ec", font=font)

    combined.save(filename)
    print(f"Generated {filename} -> {url}")


for fname, url, label in CODES:
    generate(fname, url, label)
