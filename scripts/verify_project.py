"""Fast cross-platform checks; compilation and XCTest run on the macOS runner."""
from pathlib import Path
import json
import plistlib
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def main():
    for path in [ROOT / "OKNative/Resources/Info.plist", ROOT / "OKNative/Resources/PrivacyInfo.xcprivacy"]:
        with path.open("rb") as stream:
            plistlib.load(stream)
    ET.parse(ROOT / "OKNative.xcodeproj/xcshareddata/xcschemes/OKNative.xcscheme")
    catalog = ROOT / "OKNative/Resources/Assets.xcassets"
    images = set()
    for manifest in catalog.rglob("Contents.json"):
        value = json.loads(manifest.read_text())
        for item in value.get("images", []):
            assert (manifest.parent / item["filename"]).is_file(), f"Missing asset: {manifest}"
        if manifest.parent.suffix == ".imageset":
            images.add(manifest.parent.stem)
    swift = "\n".join(p.read_text(encoding="utf-8") for p in (ROOT / "OKNative").rglob("*.swift"))
    asset_names = set(re.findall(r'"((?:photo-|avatar-)[a-z]+|AppMark)"', swift))
    assert asset_names <= images, f"Unresolved image names: {asset_names - images}"
    data = (ROOT / "OKNative/Services/DemoSocialService.swift").read_text(encoding="utf-8")
    photo_ids = re.findall(r'DemoPhoto\(id: "([^"]+)"', data)
    post_photos = re.findall(r'photoID: "([^"]+)"', data)
    assert len(photo_ids) == len(set(photo_ids)) == 6
    assert set(post_photos) <= set(photo_ids)
    assert "NSAllowsArbitraryLoads" not in (ROOT / "OKNative/Resources/Info.plist").read_text()
    print(f"Validated plists, scheme, {len(images)} image sets and demo photo references.")


if __name__ == "__main__":
    main()

