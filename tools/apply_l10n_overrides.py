#!/usr/bin/env python3
"""Apply l10n_overrides.json to iOS and Mac Localizable.xcstrings (guide keys synced)."""
from __future__ import annotations

import json
from pathlib import Path


def apply_bundle(path: Path, bundles: list[dict[str, dict[str, str]]]) -> int:
    data = json.loads(path.read_text(encoding="utf-8"))
    strings = data.setdefault("strings", {})
    changed = 0
    for bundle in bundles:
        for key, locs in bundle.items():
            entry = strings.setdefault(key, {"localizations": {}})
            loc = entry.setdefault("localizations", {})
            for lang, value in locs.items():
                unit = loc.setdefault(lang, {}).setdefault("stringUnit", {})
                unit["state"] = "translated"
                if unit.get("value") != value:
                    unit["value"] = value
                    changed += 1
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return changed


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    raw = json.loads((root / "tools" / "l10n_overrides.json").read_text(encoding="utf-8"))
    guide = raw["guide"]
    ios_only = raw["ios"]
    mac_only = raw["mac"]

    ios_path = root / "TreeletHub" / "Localizable.xcstrings"
    mac_path = root / "TreeletHub_Mac" / "Localizable.xcstrings"

    c1 = apply_bundle(ios_path, [guide, ios_only])
    c2 = apply_bundle(mac_path, [guide, mac_only])
    print(f"updated {ios_path.name}: ~{c1} field writes")
    print(f"updated {mac_path.name}: ~{c2} field writes")


if __name__ == "__main__":
    main()
