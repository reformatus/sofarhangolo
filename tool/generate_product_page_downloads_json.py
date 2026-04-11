#!/usr/bin/env python3

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def run_gh_api(path: str) -> object:
    output = subprocess.check_output(
        ["gh", "api", path],
        text=True,
    )
    return json.loads(output)


def classify_asset(name: str) -> str | None:
    lower = name.lower()
    if lower.endswith(".exe"):
        return "windowsInstaller"
    if lower.endswith(".msix"):
        return "windowsStore"
    if lower.endswith(".dmg"):
        return "macosDmg"
    if lower.endswith(".flatpak"):
        return "linuxFlatpak"
    if lower.endswith(".apk"):
        return "androidApk"
    if lower.endswith(".ipa"):
        return "iosIpa"
    return None


def simplify_release(release: dict) -> dict | None:
    if release.get("draft"):
        return None

    assets = []
    for asset in release.get("assets", []):
        kind = classify_asset(asset.get("name", ""))
        if kind is None:
            continue
        assets.append(
            {
                "kind": kind,
                "name": asset["name"],
                "downloadUrl": asset["browser_download_url"],
                "downloadCount": asset["download_count"],
                "sizeBytes": asset["size"],
            }
        )

    return {
        "track": "prerelease" if release.get("prerelease") else "stable",
        "tagName": release["tag_name"],
        "htmlUrl": release["html_url"],
        "publishedAt": release.get("published_at"),
        "assets": assets,
    }


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "Usage: generate_product_page_downloads_json.py <owner/repo> <output-path>",
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

        if simplified["track"] == "stable" and stable is None:
            stable = simplified
        if simplified["track"] == "prerelease" and prerelease is None:
            prerelease = simplified

        if stable is not None and prerelease is not None:
            break

    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "stable": stable,
        "prerelease": prerelease,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
