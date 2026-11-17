#!/usr/bin/env python3
"""Upload TreeletHub Android 1.3.2 AAB and submit production release for review."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import requests

CRED_PATH = Path.home() / ".config" / "yun" / "play-oauth.json"
PACKAGE = "com.treelet.treelethub"
VERSION_CODE = 7
VERSION_NAME = "1.3.2"
AAB_PATH = (
    Path(__file__).resolve().parents[1]
    / "app"
    / "build"
    / "outputs"
    / "bundle"
    / "release"
    / "app-release.aab"
)

# Keep Play listing notes compliance-safe (no platform trademarks / external-pay cues).
NOTES_ZH = """• 蜂巢启动墙支持键盘与鼠标遥控（若电脑伴侣端提供）
• 捏合缩放、拖动浏览与点按启动持续打磨
• 稳定性与兼容性改进"""

NOTES_EN = """• Keyboard & Mouse remote when the computer companion provides it
• Continued polish for honeycomb zoom, pan, and tap-to-launch
• Stability and compatibility improvements"""


def token() -> str:
    cred = json.loads(CRED_PATH.read_text())
    r = requests.post(
        "https://oauth2.googleapis.com/token",
        data={
            "client_id": cred["client_id"],
            "client_secret": cred["client_secret"],
            "refresh_token": cred["refresh_token"],
            "grant_type": "refresh_token",
        },
        timeout=60,
    )
    r.raise_for_status()
    return r.json()["access_token"]


def api(method: str, path: str, access: str, *, upload: bool = False, retries: int = 5, **kwargs):
    import time

    base = (
        "https://androidpublisher.googleapis.com/upload"
        if upload
        else "https://androidpublisher.googleapis.com"
    )
    url = base + path
    headers = kwargs.pop("headers", {})
    headers["Authorization"] = "Bearer " + access
    if "json" in kwargs:
        headers.setdefault("Content-Type", "application/json")
    last: Exception | None = None
    for attempt in range(1, retries + 1):
        r = requests.request(method, url, headers=headers, timeout=600, **kwargs)
        if r.status_code < 400:
            return r.json() if r.content else {}
        last = RuntimeError(f"{method} {path} -> {r.status_code}: {r.text[:1500]}")
        if r.status_code in (429, 500, 502, 503, 504) and attempt < retries:
            wait = min(2**attempt, 30)
            print(f"retry {attempt}/{retries} after {wait}s: {r.status_code}", flush=True)
            time.sleep(wait)
            continue
        raise last
    raise last  # pragma: no cover


def main() -> None:
    for label, text in (("zh", NOTES_ZH), ("en", NOTES_EN)):
        if len(text) > 500:
            raise SystemExit(f"{label} release notes too long: {len(text)}")
    if not AAB_PATH.exists():
        raise SystemExit(f"Missing AAB: {AAB_PATH}")

    access = token()
    edit = api("POST", f"/androidpublisher/v3/applications/{PACKAGE}/edits", access, json={})
    edit_id = edit["id"]
    print("edit", edit_id)

    try:
        size = AAB_PATH.stat().st_size
        print(f"upload AAB {AAB_PATH.name} ({size} bytes)")
        aab_bytes = AAB_PATH.read_bytes()
        uploaded = api(
            "POST",
            f"/androidpublisher/v3/applications/{PACKAGE}/edits/{edit_id}/bundles"
            "?uploadType=media",
            access,
            upload=True,
            headers={"Content-Type": "application/octet-stream"},
            data=aab_bytes,
        )
        print("uploaded bundle", uploaded)
        vc = int(uploaded.get("versionCode") or 0)
        if vc != VERSION_CODE:
            raise RuntimeError(f"Unexpected versionCode {vc}, expected {VERSION_CODE}")

        track_body = {
            "track": "production",
            "releases": [
                {
                    "name": f"{VERSION_CODE} ({VERSION_NAME})",
                    "versionCodes": [str(VERSION_CODE)],
                    "status": "completed",
                    "releaseNotes": [
                        {"language": "zh-CN", "text": NOTES_ZH},
                        {"language": "en-US", "text": NOTES_EN},
                    ],
                }
            ],
        }
        print("update production track → completed (full rollout / review)")
        updated = api(
            "PUT",
            f"/androidpublisher/v3/applications/{PACKAGE}/edits/{edit_id}/tracks/production",
            access,
            json=track_body,
        )
        print("track", json.dumps(updated, ensure_ascii=False)[:800])

        commit = api(
            "POST",
            f"/androidpublisher/v3/applications/{PACKAGE}/edits/{edit_id}:commit",
            access,
            json={},
        )
        print("COMMITTED", json.dumps(commit, ensure_ascii=False))
    except Exception as exc:
        print("ERROR:", exc, file=sys.stderr)
        try:
            api(
                "DELETE",
                f"/androidpublisher/v3/applications/{PACKAGE}/edits/{edit_id}",
                access,
            )
            print("edit discarded", file=sys.stderr)
        except Exception as discard_exc:
            print("discard failed:", discard_exc, file=sys.stderr)
        raise SystemExit(1)

    verify = api("POST", f"/androidpublisher/v3/applications/{PACKAGE}/edits", access, json={})
    vid = verify["id"]
    try:
        tracks = api(
            "GET",
            f"/androidpublisher/v3/applications/{PACKAGE}/edits/{vid}/tracks/production",
            access,
        )
        print("VERIFY production", json.dumps(tracks, ensure_ascii=False)[:1200])
    finally:
        api("DELETE", f"/androidpublisher/v3/applications/{PACKAGE}/edits/{vid}", access)


if __name__ == "__main__":
    main()
