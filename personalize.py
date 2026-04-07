#!/usr/bin/env python3
"""
personalize.py — Run this once after cloning to replace placeholder values.

Usage:
    python3 personalize.py

You'll be prompted for:
  - Your GitHub username
  - (Optional) your GitHub repo name for the catalog itself
"""

import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))

FILES_TO_PATCH = [
    "catalog.json",
    "pre-install.sh",
    "README.md",
    "trains/community/android-agent/app.yaml",
    "trains/community/android-agent/docker-compose.yaml",
]

def replace_in_file(path, old, new):
    full = os.path.join(ROOT, path)
    if not os.path.exists(full):
        print(f"  ⚠️  Not found: {path}")
        return
    content = open(full).read()
    if old not in content:
        return
    open(full, "w").write(content.replace(old, new))
    print(f"  ✅ {path}")

def main():
    print("=" * 50)
    print("  Android Agent Catalog — Personalize")
    print("=" * 50)
    print()

    username = input("Your GitHub username: ").strip()
    if not username:
        print("Username required.")
        sys.exit(1)

    pool = input("TrueNAS pool name [tank]: ").strip() or "tank"

    print()
    print("Patching files...")

    for f in FILES_TO_PATCH:
        replace_in_file(f, "Joshuacarley", username)

    # Also patch pool name in pre-install.sh
    replace_in_file("pre-install.sh", 'POOL="${1:-tank}"', f'POOL="${{1:-{pool}}}"')

    print()
    print("=" * 50)
    print("  Done!")
    print("=" * 50)
    print()
    print("Next steps:")
    print(f"  1. git init && git add . && git commit -m 'init'")
    print(f"  2. Create repo on GitHub: github.com/new")
    print(f"     Name it: android-agent-catalog")
    print(f"  3. git remote add origin https://github.com/{username}/android-agent-catalog")
    print(f"     git push -u origin main")
    print()
    print(f"  4. GitHub Actions will build the Docker image (~20 min first time)")
    print(f"     Watch: https://github.com/{username}/android-agent-catalog/actions")
    print()
    print(f"  5. On TrueNAS Shell, run:")
    print(f"     curl -fsSL https://raw.githubusercontent.com/{username}/android-agent-catalog/main/pre-install.sh | bash")
    print()
    print(f"  6. In TrueNAS → Apps → Manage Catalogs → Add Catalog:")
    print(f"     https://github.com/{username}/android-agent-catalog")
    print()
    print(f"  7. Search 'Android Agent' → Install → fill in your tokens")
    print()

if __name__ == "__main__":
    main()
