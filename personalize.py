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
    "README.md",
    "trains/community/android-agent/item.yaml",
    "trains/community/android-agent/app_versions.json",
    "trains/community/android-agent/1.0.0/app.yaml",
    "trains/community/android-agent/1.0.0/ix_values.yaml",
    "trains/community/android-agent/1.0.0/templates/docker-compose.yaml",
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

    print()
    print("Patching files...")

    for f in FILES_TO_PATCH:
        replace_in_file(f, "Joshuacarley", username)
        replace_in_file(f, "joshuacarley", username.lower())

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
    print(f"  5. In TrueNAS → Apps → Manage Catalogs → Add Catalog:")
    print(f"     https://github.com/{username}/android-agent-catalog")
    print()
    print(f"  6. Search 'Android Agent' → Install → fill in your tokens")
    print(f"     (Storage is auto-provisioned, no pre-install needed.)")
    print()

if __name__ == "__main__":
    main()
