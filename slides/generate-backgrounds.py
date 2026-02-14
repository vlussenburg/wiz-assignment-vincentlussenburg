"""Generate slide backgrounds using Ideogram API."""

import json
import os
import urllib.request
from concurrent.futures import ThreadPoolExecutor

API_KEY = os.environ["IDEOGRAM_API_KEY"]
OUTPUT_DIR = "backgrounds"

# Simple, clean abstract gradients — white dominant, subtle blue accents
SLIDES = [
    ("02-architecture",      "white gradient background with faint light blue geometric lines"),
    ("03-what-i-built",      "white gradient background with faint light blue grid pattern"),
    ("04-how-i-built",       "white gradient background with faint light blue circuit traces"),
    ("05-misconfigs",        "white gradient background with faint light orange and blue corners"),
    ("06-app-vulns",         "white gradient background with faint light blue binary dots"),
    ("07-security-controls", "white gradient background with faint light blue and green accents"),
    ("08-pipelines",         "white gradient background with faint light blue flowing lines"),
    ("09-attack-chain",      "white gradient background with faint light red chain links at edges"),
    ("10-live-demo",         "white gradient background with faint light blue terminal cursor"),
    ("11-business-risks",    "white gradient background with faint light red downward lines"),
    ("12-wiz-value",         "white gradient background with faint light blue cloud shapes"),
    ("13-challenges",        "white gradient background with faint light blue puzzle outlines"),
    ("14-do-differently",    "white gradient background with faint light green upward arrows"),
    ("15-bonus-slides",      "white gradient background with faint light blue code brackets and gear shapes"),
    ("16-resources",         "white gradient background with faint light blue bookmark shapes"),
]

os.makedirs(OUTPUT_DIR, exist_ok=True)


def generate(name: str, prompt: str) -> None:
    body = json.dumps({
        "prompt": prompt,
        "aspect_ratio": "16x9",
        "style_type": "DESIGN",
        "rendering_speed": "TURBO",
        "magic_prompt": "OFF",
        "negative_prompt": "text words letters numbers logos writing typography",
    }).encode()

    req = urllib.request.Request(
        "https://api.ideogram.ai/v1/ideogram-v3/generate",
        data=body,
        headers={"Api-Key": API_KEY, "Content-Type": "application/json"},
    )

    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())
        url = data["data"][0]["url"]
        urllib.request.urlretrieve(url, f"{OUTPUT_DIR}/{name}.png")
        print(f"  OK: {name}.png")
    except Exception as e:
        print(f"  FAIL: {name} — {e}")


print(f"Generating {len(SLIDES)} backgrounds via Ideogram API...")
with ThreadPoolExecutor(max_workers=4) as pool:
    pool.map(lambda s: generate(*s), SLIDES)

count = len([f for f in os.listdir(OUTPUT_DIR) if f.endswith(".png")])
print(f"Done: {count}/{len(SLIDES)} backgrounds generated.")
