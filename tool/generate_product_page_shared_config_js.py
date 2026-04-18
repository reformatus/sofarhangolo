#!/usr/bin/env python3

import json
import subprocess
import sys
from pathlib import Path


PLATFORM_META = {
    "android": {
        "name": "Android",
        "icon": "android",
        "stable_store": [
            {
                "url": "https://play.google.com/store/apps/details?id=org.lyricapp.sofar",
                "name": "Google Play",
            }
        ],
        "prerelease_store": [
            {
                "url": "https://play.google.com/apps/testing/org.lyricapp.sofar",
                "name": "Google Play Beta",
            }
        ],
    },
    "ios": {
        "name": "iOS",
        "icon": "phone_iphone",
        "stable_store": [
            {
                "url": "https://apps.apple.com/us/app/s%C3%B3f%C3%A1r-hangol%C3%B3/id6738664835",
                "name": "App Store",
            }
        ],
        "prerelease_store": [
            {
                "url": "https://testflight.apple.com/join/EsV5pBEN",
                "name": "TestFlight",
            }
        ],
    },
    "windows": {
        "name": "Windows",
        "icon": "desktop_windows",
        "stable_store": [],
        "prerelease_store": [],
    },
    "macos": {
        "name": "macOS",
        "icon": "laptop_mac",
        "stable_store": [],
        "prerelease_store": [],
    },
    "linux": {
        "name": "Linux",
        "icon": "terminal",
        "stable_store": [],
        "prerelease_store": [],
    },
}

ASSET_TO_PLATFORM = {
    ".apk": ("android", "APK"),
    ".ipa": ("ios", "IPA"),
    ".exe": ("windows", "Telepítő"),
    ".msix": ("windows", "MSIX csomag"),
    ".dmg": ("macos", "DMG"),
    ".flatpak": ("linux", "Flatpak"),
}

TRACK_META = {
    "stable": {
        "title": "Stabil kiadás",
        "description": "Ajánlott a legtöbb felhasználónak.",
    },
    "prerelease": {
        "title": "Előzetes kiadás",
        "description": "Új funkciók hamarabb, kisebb stabilitással.",
    },
}


def run_gh_api(path: str) -> object:
    output = subprocess.check_output(
        ["gh", "api", "-H", "Accept: application/vnd.github.html+json", path],
        text=True,
    )
    return json.loads(output)


def format_size(size_bytes: int) -> str:
    units = ["B", "KB", "MB", "GB"]
    value = float(size_bytes)
    index = 0
    while value >= 1024 and index < len(units) - 1:
        value /= 1024
        index += 1
    digits = 0 if value >= 100 or index == 0 else 1
    return f"{value:.{digits}f} {units[index]}"


def classify_asset(name: str) -> tuple[str, str] | None:
    lower = name.lower()
    for suffix, mapping in ASSET_TO_PLATFORM.items():
        if lower.endswith(suffix):
            return mapping
    return None


def strip_build_metadata(version: str) -> str:
    return version.split("+", 1)[0]


def build_platforms(track_id: str, release: dict) -> dict:
    platforms = {}
    for platform_id, meta in PLATFORM_META.items():
        platforms[platform_id] = {
            "name": meta["name"],
            "icon": meta["icon"],
            "storeOptions": list(meta["stable_store"] if track_id == "stable" else meta["prerelease_store"]),
            "downloadOptions": [],
        }

    for asset in release.get("assets", []):
        classified = classify_asset(asset.get("name", ""))
        if classified is None:
            continue
        platform_id, label = classified
        platforms[platform_id]["downloadOptions"].append(
            {
                "url": asset["browser_download_url"],
                "name": label,
                "fileName": asset["name"],
                "downloadCount": asset["download_count"],
                "downloadCountLabel": f'{asset["download_count"]} letöltés',
                "sizeBytes": asset["size"],
                "sizeLabel": format_size(asset["size"]),
            }
        )

    return platforms


def simplify_release(release: dict) -> dict | None:
    if release.get("draft"):
        return None

    track_id = "prerelease" if release.get("prerelease") else "stable"
    display_version = strip_build_metadata(release["tag_name"])
    return {
        "id": track_id,
        "title": TRACK_META[track_id]["title"],
        "version": display_version,
        "release": {
            "title": release.get("name") or display_version,
            "tag": release["tag_name"],
            "displayTag": display_version,
            "descriptionHtml": release.get("body_html") or "",
            "url": release["html_url"],
        },
        "platforms": build_platforms(track_id, release),
    }


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "Usage: generate_product_page_shared_config_js.py <owner/repo> <output-path>",
            file=sys.stderr,
        )
        return 2

    repo = sys.argv[1]
    output_path = Path(sys.argv[2])
    releases = run_gh_api(f"repos/{repo}/releases?per_page=20")

    stable = None
    prerelease = None
    for release in releases:
        simplified = simplify_release(release)
        if simplified is None:
            continue

        if simplified["id"] == "stable" and stable is None:
            stable = simplified
        if simplified["id"] == "prerelease" and prerelease is None:
            prerelease = simplified
        if stable is not None and prerelease is not None:
            break

    payload = {
        "downloads": {
            "defaultTrack": "stable" if stable is not None else "prerelease",
            "tracks": {
                "stable": stable,
                "prerelease": prerelease,
            },
        }
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        "window.sofarSharedConfig = "
        + json.dumps(payload, ensure_ascii=False, indent=2)
        + ";\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
