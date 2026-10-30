#!/usr/bin/env python3
"""Validates the privacy manifests. Runs on Linux, so no Mac is needed.

Worth having because a malformed manifest is expensive and silent: App Store
Connect refuses the UPLOAD, and the only symptom is a rejection weeks later.

It has already earned its place twice:
  - A double hyphen inside an XML comment is illegal. Writing the explanation
    in em-dash style produced a manifest that would not parse at all.
  - Declaring a reason code that does not exist, or the wrong one for how the
    data is used, is a rejection rather than a build error.

What this does NOT check is whether the manifest reached the built .app bundle.
Only the macOS job can do that, and it does.
"""
import plistlib
import sys
from pathlib import Path

# Verified against Apple's live documentation on 2026-10-30.
VALID_CATEGORIES = {
    "NSPrivacyAccessedAPICategoryFileTimestamp": {"DDA9.1", "C617.1", "3B52.1", "0A2A.1"},
    "NSPrivacyAccessedAPICategorySystemBootTime": {"35F9.1", "8FFB.1", "3D61.1"},
    "NSPrivacyAccessedAPICategoryDiskSpace": {"85F4.1", "E174.1", "7D9E.1", "B728.1"},
    "NSPrivacyAccessedAPICategoryActiveKeyboards": {"3EC4.1", "54BD.1"},
    "NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1", "1C8F.1", "C56D.1", "AC6B.1"},
}

REQUIRED_KEYS = ["NSPrivacyTracking", "NSPrivacyTrackingDomains",
                 "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes"]

# The watch reads CMLogItem.timestamp for rep counting, so it must declare boot
# time or the upload is refused.
MUST_DECLARE = {
    "ZeroLogWatch": [("NSPrivacyAccessedAPICategorySystemBootTime", "35F9.1")],
}


def check(path: Path) -> list[str]:
    problems = []
    try:
        with path.open("rb") as handle:
            manifest = plistlib.load(handle)
    except Exception as exc:                      # malformed XML lands here
        return [f"{path}: will not parse ({exc})"]

    for key in REQUIRED_KEYS:
        if key not in manifest:
            problems.append(f"{path}: missing required key {key}")

    if manifest.get("NSPrivacyTracking") is True and not manifest.get("NSPrivacyTrackingDomains"):
        problems.append(f"{path}: tracking is true but no tracking domains are listed")

    for entry in manifest.get("NSPrivacyAccessedAPITypes", []):
        category = entry.get("NSPrivacyAccessedAPIType")
        reasons = entry.get("NSPrivacyAccessedAPITypeReasons", [])
        if category not in VALID_CATEGORIES:
            problems.append(f"{path}: unknown API category {category!r}")
            continue
        if not reasons:
            problems.append(f"{path}: {category} declares no reason")
        for reason in reasons:
            if reason not in VALID_CATEGORIES[category]:
                problems.append(
                    f"{path}: {reason!r} is not a valid reason for {category}; "
                    f"expected one of {sorted(VALID_CATEGORIES[category])}")

    target = path.parent.name
    declared = {(e.get("NSPrivacyAccessedAPIType"), r)
                for e in manifest.get("NSPrivacyAccessedAPITypes", [])
                for r in e.get("NSPrivacyAccessedAPITypeReasons", [])}
    for pair in MUST_DECLARE.get(target, []):
        if pair not in declared:
            problems.append(f"{path}: {target} must declare {pair[0]} with reason {pair[1]}")

    return problems


def main() -> int:
    root = Path(__file__).resolve().parents[1] if (Path(__file__).parent / "app").exists() \
        else Path.cwd()
    manifests = sorted(root.glob("app/*/PrivacyInfo.xcprivacy"))
    if not manifests:
        print("No privacy manifests found. Expected app/<Target>/PrivacyInfo.xcprivacy")
        return 1

    problems = []
    for path in manifests:
        found = check(path)
        status = "FAIL" if found else "ok"
        print(f"[{status}] {path.relative_to(root)}")
        if not found:
            with path.open("rb") as handle:
                manifest = plistlib.load(handle)
            api = manifest.get("NSPrivacyAccessedAPITypes", [])
            summary = ", ".join(
                f"{e['NSPrivacyAccessedAPIType'].replace('NSPrivacyAccessedAPICategory', '')}"
                f"={'/'.join(e['NSPrivacyAccessedAPITypeReasons'])}" for e in api) or "none"
            print(f"       tracking={manifest['NSPrivacyTracking']} "
                  f"collected={len(manifest['NSPrivacyCollectedDataTypes'])} "
                  f"required-reason APIs: {summary}")
        problems += found

    for problem in problems:
        print(f"  -> {problem}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
