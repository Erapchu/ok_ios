"""Download the fixed demo photos and draw our original geometric app icon.

Run only when updating bundled assets; normal builds work completely offline.
Requires Pillow. Image URLs and authors are recorded in ASSET_CREDITS.md.
"""
from pathlib import Path
import json
import urllib.request
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "OKNative" / "Resources" / "Assets.xcassets"
PHOTOS = {
    "photo-lake": "photo-1470770841072-f978cf4d019e",
    "photo-peaks": "photo-1464822759023-fed622ff2c3b",
    "photo-forest": "photo-1441974231531-c6227db76b6e",
    "photo-valley": "photo-1500534623283-312aade485b7",
    "photo-coast": "photo-1501785888041-af3ef285b470",
    "photo-road": "photo-1469474968028-56623f02e42e",
    "avatar-alex": "photo-1500648767791-00dcc994a43e",
    "avatar-anna": "photo-1494790108377-be9c29b29330",
    "avatar-mike": "photo-1506794778202-cad84cf45f1d",
    "avatar-elena": "photo-1534528741775-53994a69daeb",
}


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def main():
    write_json(CATALOG / "Contents.json", {"info": {"author": "xcode", "version": 1}})
    for name, photo in PHOTOS.items():
        folder = CATALOG / (name + ".imageset")
        folder.mkdir(parents=True, exist_ok=True)
        width = 320 if name.startswith("avatar") else 1200
        url = f"https://images.unsplash.com/{photo}?auto=format&fit=crop&w={width}&q=85"
        request = urllib.request.Request(url, headers={"User-Agent": "OKNativePrototype/0.1"})
        with urllib.request.urlopen(request, timeout=45) as response:
            data = response.read()
        (folder / "image.jpg").write_bytes(data)
        # Verify we received a decodable image rather than an HTTP error page.
        with Image.open(folder / "image.jpg") as image:
            image.verify()
        write_json(folder / "Contents.json", {
            "images": [{"filename": "image.jpg", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
        })
        print(name)

    # An original two-person mark: warm orange field, white heads and shoulders.
    icon = Image.new("RGB", (1024, 1024))
    draw = ImageDraw.Draw(icon)
    for y in range(1024):
        t = y / 1023
        draw.line((0, y, 1024, y), fill=(round(255 - 19*t), round(145 - 47*t), round(49 - 28*t)))
    draw.ellipse((90, 90, 934, 934), outline=(255, 173, 95), width=3)
    draw.ellipse((290, 245, 466, 421), fill="white")
    draw.ellipse((558, 245, 734, 421), fill="white")
    draw.rounded_rectangle((220, 475, 488, 728), radius=128, fill="white")
    draw.rounded_rectangle((536, 475, 804, 728), radius=128, fill="white")
    draw.rounded_rectangle((385, 494, 639, 574), radius=40, fill="white")
    app_icon = CATALOG / "AppIcon.appiconset"
    app_icon.mkdir(exist_ok=True)
    icon.save(app_icon / "AppIcon.png")
    write_json(app_icon / "Contents.json", {
        "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    })
    mark = CATALOG / "AppMark.imageset"
    mark.mkdir(exist_ok=True)
    icon.resize((180, 180), Image.Resampling.LANCZOS).save(mark / "mark.png")
    write_json(mark / "Contents.json", {
        "images": [{"filename": "mark.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    })
    write_json(CATALOG / "AccentColor.colorset" / "Contents.json", {
        "colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {
            "red": "0.94", "green": "0.40", "blue": "0.10", "alpha": "1.0"}}}],
        "info": {"author": "xcode", "version": 1},
    })


if __name__ == "__main__":
    main()

