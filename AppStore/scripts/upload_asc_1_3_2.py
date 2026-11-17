#!/usr/bin/env python3
"""Upload TreeletHub 1.3.2 metadata, screenshots, and creative assets to ASC."""

from __future__ import annotations

import hashlib
import json
import time
from pathlib import Path

import jwt
import requests

KEY_PATH = Path("/Users/timshu/TreeletProjects/treelethub/AuthKey_DM8L65H449.p8")
KEY_ID = "DM8L65H449"
ISSUER = "f3ef070d-7afe-44fb-a4d2-72d438c38f71"
BASE = "https://api.appstoreconnect.apple.com"

ROOT = Path(__file__).resolve().parents[1]
META = Path(__file__).resolve().parents[2] / "fastlane" / "metadata"

IOS_APP = "6762348247"
MAC_APP = "6762348258"
IOS_VER = "257324fb-3a18-4e7e-95d1-4eb996099e31"
MAC_VER = "1b4ef7d7-6528-4e6c-9135-c1633d8789ad"
IOS_LOCS = {
    "en-US": "0858e0dc-74f9-4799-aee6-09e3ffe7804b",
    "zh-Hans": "626f9735-d321-4d4a-8d79-8eaeab58dd39",
}
MAC_LOCS = {
    "en-US": "01128f1f-a2b6-49b6-bea3-fdaa650028e6",
    "zh-Hans": "60eb52fe-5bed-41fc-9cec-7ed6fba6f78e",
}


def token() -> str:
    now = int(time.time())
    return jwt.encode(
        {"iss": ISSUER, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
        KEY_PATH.read_text(),
        algorithm="ES256",
        headers={"kid": KEY_ID},
    )


def api(method: str, path: str, **kwargs):
    headers = kwargs.pop("headers", {})
    headers["Authorization"] = "Bearer " + token()
    headers.setdefault("Accept", "application/json")
    if "json" in kwargs:
        headers["Content-Type"] = "application/json"
    r = requests.request(method, BASE + path, headers=headers, timeout=180, **kwargs)
    if r.status_code >= 400:
        raise RuntimeError(f"{method} {path} -> {r.status_code}: {r.text[:1500]}")
    return r.json() if r.content else {}


def upload_binary(operations: list, data: bytes) -> None:
    for op in operations:
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        length = op.get("length")
        offset = op.get("offset", 0)
        chunk = data[offset : offset + length] if length is not None else data[offset:]
        r = requests.request(op.get("method", "PUT"), op["url"], headers=headers, data=chunk, timeout=180)
        if r.status_code >= 400:
            raise RuntimeError(f"upload chunk failed {r.status_code}: {r.text[:300]}")


def wait_shot(shot_id: str) -> dict:
    for _ in range(80):
        attrs = api("GET", f"/v1/appScreenshots/{shot_id}")["data"]["attributes"]
        state = (attrs.get("assetDeliveryState") or {}).get("state")
        if state in ("COMPLETE", "APPROVED"):
            return attrs
        if state in ("FAILED", "INVALID"):
            raise RuntimeError(f"{shot_id} {state} {attrs}")
        time.sleep(2)
    raise RuntimeError(f"timeout screenshot {shot_id}")


def wait_creative(image_id: str) -> dict:
    for _ in range(80):
        attrs = api("GET", f"/v1/appAssetLibraryImages/{image_id}")["data"]["attributes"]
        state = attrs.get("state") or (attrs.get("assetDeliveryState") or {}).get("state")
        if state in ("PREPARE_FOR_SUBMISSION", "COMPLETE", "APPROVED", "WAITING_FOR_REVIEW"):
            return attrs
        if state in ("FAILED", "REJECTED", "INVALID"):
            raise RuntimeError(f"{image_id} {state} {attrs}")
        time.sleep(2)
    raise RuntimeError(f"timeout creative {image_id}")


def read_meta(platform: str, locale: str, name: str) -> str | None:
    path = META / platform / locale / f"{name}.txt"
    if not path.exists():
        return None
    return path.read_text(encoding="utf-8").strip()


def patch_localization(loc_id: str, platform: str, locale: str) -> None:
    attrs = {}
    for key, file in [
        ("description", "description"),
        ("keywords", "keywords"),
        ("marketingUrl", None),
        ("promotionalText", "promotional_text"),
        ("supportUrl", None),
        ("whatsNew", "release_notes"),
    ]:
        if file is None:
            continue
        val = read_meta(platform, locale, file)
        if val is not None:
            attrs[key] = val
    if not attrs:
        return
    api(
        "PATCH",
        f"/v1/appStoreVersionLocalizations/{loc_id}",
        json={"data": {"type": "appStoreVersionLocalizations", "id": loc_id, "attributes": attrs}},
    )
    print(f"patched {platform} {locale} keys={list(attrs)}")


def patch_app_info_subtitle(app_id: str, locale: str, subtitle: str) -> None:
    """Subtitle lives on appInfoLocalization, not version localization."""
    infos = api("GET", f"/v1/apps/{app_id}/appInfos")["data"]
    if not infos:
        print("no appInfos for", app_id)
        return
    # Prefer EDITABLE / PREPARE_FOR_DISTRIBUTION
    info = infos[0]
    for cand in infos:
        state = (cand.get("attributes") or {}).get("appStoreState") or (cand.get("attributes") or {}).get("state")
        if state and "PREPARE" in str(state):
            info = cand
            break
    locs = api("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"]
    loc = next((l for l in locs if l["attributes"].get("locale") == locale), None)
    if not loc:
        print("no appInfoLocalization", locale)
        return
    api(
        "PATCH",
        f"/v1/appInfoLocalizations/{loc['id']}",
        json={
            "data": {
                "type": "appInfoLocalizations",
                "id": loc["id"],
                "attributes": {"subtitle": subtitle},
            }
        },
    )
    print(f"patched subtitle {locale}: {subtitle}")


def ensure_shot_set(loc_id: str, display: str) -> str:
    sets = api("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")["data"]
    by = {s["attributes"]["screenshotDisplayType"]: s for s in sets}
    if display in by:
        return by[display]["id"]
    created = api(
        "POST",
        "/v1/appScreenshotSets",
        json={
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": display},
                "relationships": {
                    "appStoreVersionLocalization": {
                        "data": {"type": "appStoreVersionLocalizations", "id": loc_id}
                    }
                },
            }
        },
    )["data"]
    print("created set", display, created["id"])
    return created["id"]


def replace_screenshots(set_id: str, files: list[Path]) -> None:
    existing = api("GET", f"/v1/appScreenshotSets/{set_id}/appScreenshots")["data"]
    for shot in existing:
        api("DELETE", f"/v1/appScreenshots/{shot['id']}")
        print("  delete", shot["attributes"].get("fileName"))
    for i, path in enumerate(files, 1):
        data = path.read_bytes()
        print(f"  upload {i}/{len(files)} {path.name}")
        created = api(
            "POST",
            "/v1/appScreenshots",
            json={
                "data": {
                    "type": "appScreenshots",
                    "attributes": {"fileName": path.name, "fileSize": len(data)},
                    "relationships": {
                        "appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}
                    },
                }
            },
        )["data"]
        sid = created["id"]
        ops = created["attributes"].get("uploadOperations") or []
        if not ops:
            ops = api("GET", f"/v1/appScreenshots/{sid}")["data"]["attributes"].get("uploadOperations") or []
        upload_binary(ops, data)
        api(
            "PATCH",
            f"/v1/appScreenshots/{sid}",
            json={
                "data": {
                    "type": "appScreenshots",
                    "id": sid,
                    "attributes": {
                        "uploaded": True,
                        "sourceFileChecksum": hashlib.md5(data).hexdigest(),
                    },
                }
            },
        )
        attrs = wait_shot(sid)
        asset = attrs.get("imageAsset") or {}
        print(f"    COMPLETE {asset.get('width')}x{asset.get('height')}")


def upload_creative(app_id: str, loc_id: str, path: Path, placement_type: str) -> str:
    # Asset library id == app id in StillOK flow
    created = api(
        "POST",
        "/v1/appAssetLibraryImages",
        json={
            "data": {
                "type": "appAssetLibraryImages",
                "attributes": {
                    "fileName": path.name,
                    "fileSize": path.stat().st_size,
                    "category": "CREATIVE_ASSETS",
                },
                "relationships": {
                    "assetLibrary": {"data": {"type": "appAssetLibraries", "id": app_id}}
                },
            }
        },
    )["data"]
    iid = created["id"]
    ops = created["attributes"].get("uploadOperations") or []
    upload_binary(ops, path.read_bytes())
    api(
        "PATCH",
        f"/v1/appAssetLibraryImages/{iid}",
        json={
            "data": {
                "type": "appAssetLibraryImages",
                "id": iid,
                "attributes": {"uploaded": True},
            }
        },
    )
    attrs = wait_creative(iid)
    print("  creative state", attrs.get("state"))
    # place on localization
    placements = api("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/placements").get("data") or []
    for p in placements:
        if (p.get("attributes") or {}).get("placementType") == placement_type:
            api("DELETE", f"/v1/appAssetLibraryPlacements/{p['id']}")
            print("  deleted old placement", placement_type)
    api(
        "POST",
        "/v1/appAssetLibraryPlacements",
        json={
            "data": {
                "type": "appAssetLibraryPlacements",
                "attributes": {
                    "placementType": placement_type,
                    "placementGroup": "DEFAULT_PROFILE",
                },
                "relationships": {
                    "appStoreVersionLocalization": {
                        "data": {"type": "appStoreVersionLocalizations", "id": loc_id}
                    },
                    "image": {"data": {"type": "appAssetLibraryImages", "id": iid}},
                },
            }
        },
    )
    print("  placed", placement_type, path.name)
    return iid


def main() -> None:
    print("== metadata ==")
    for locale, loc_id in IOS_LOCS.items():
        patch_localization(loc_id, "ios", locale)
        sub = read_meta("ios", locale, "subtitle")
        if sub:
            patch_app_info_subtitle(IOS_APP, locale, sub)
    for locale, loc_id in MAC_LOCS.items():
        patch_localization(loc_id, "mac", locale)

    print("== iOS Duo + 6.7 screenshots ==")
    for locale, loc_id in IOS_LOCS.items():
        duo_dir = ROOT / "screenshots" / "duo" / locale
        files = sorted(duo_dir.glob("*.png"))
        set_id = ensure_shot_set(loc_id, "APP_IPHONE_DUO")
        print(locale, "DUO", set_id)
        replace_screenshots(set_id, files)

        shot67 = sorted((ROOT / "screenshots" / "iphone67" / locale).glob("*.png"))
        set67 = ensure_shot_set(loc_id, "APP_IPHONE_67")
        print(locale, "67", set67)
        replace_screenshots(set67, shot67)

    print("== Mac desktop screenshots ==")
    for locale, loc_id in MAC_LOCS.items():
        files = sorted((ROOT / "screenshots" / "mac" / locale).glob("*.png"))
        set_id = ensure_shot_set(loc_id, "APP_DESKTOP")
        print(locale, "DESKTOP", set_id)
        replace_screenshots(set_id, files)

    print("== creative assets (iOS) ==")
    for locale, loc_id in IOS_LOCS.items():
        prefix = "zh" if locale.startswith("zh") else "en"
        header = ROOT / "creative" / f"{prefix}-header-3840x1646.png"
        search = ROOT / "creative" / f"{prefix}-search-3840x2560.png"
        print(locale, "header/search")
        upload_creative(IOS_APP, loc_id, header, "PRODUCT_PAGE_HEADER_ASSET")
        upload_creative(IOS_APP, loc_id, search, "APP_STORE_SEARCH_RESULTS_ASSET")

    print("DONE")


if __name__ == "__main__":
    main()
