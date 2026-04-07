#!/usr/bin/env python3
"""
bot/config.py — Runtime configuration stored in the shared agent-config volume.

All 7 agent containers share /agent/config/ via a Docker named volume.
The dashboard writes config.json here through its /setup page; the
coordinator, workers, and telegram-bot read from it at boot.

Schema (all strings unless noted):

  github_token         str   required
  github_repo          str   required (owner/name)
  telegram_token       str   required
  telegram_chat_id     str   required
  anthropic_auth_mode  str   "subscription" | "api_key"   (default: subscription)
  anthropic_api_key    str   required only if auth_mode == api_key
  issue_label          str   default: "claude"
  poll_interval        int   default: 300
  developer_count      int   default: 2
  app_package          str   optional
  timezone             str   default: "America/Los_Angeles"
"""

import json
import os

CONFIG_DIR = "/agent/config"
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.json")

REQUIRED_KEYS = [
    "github_token",
    "github_repo",
    "telegram_token",
    "telegram_chat_id",
]

# Config key → container env var name
ENV_MAPPING = {
    "github_token":        "GITHUB_TOKEN",
    "github_repo":         "GITHUB_REPO",
    "telegram_token":      "TELEGRAM_TOKEN",
    "telegram_chat_id":    "TELEGRAM_CHAT_ID",
    "anthropic_api_key":   "ANTHROPIC_API_KEY",
    "anthropic_auth_mode": "CLAUDE_AUTH_MODE",
    "issue_label":         "CLAUDE_ISSUE_LABEL",
    "poll_interval":       "POLL_INTERVAL_SECONDS",
    "developer_count":     "DEVELOPER_COUNT",
    "app_package":         "APP_PACKAGE",
    "timezone":            "TZ",
}

DEFAULTS = {
    "anthropic_auth_mode": "subscription",
    "anthropic_api_key":   "",
    "issue_label":         "claude",
    "poll_interval":       300,
    "developer_count":     2,
    "app_package":         "",
    "timezone":            "America/Los_Angeles",
}


def get_config():
    """Return the saved config dict, or {} if not yet written."""
    if not os.path.exists(CONFIG_PATH):
        return {}
    try:
        with open(CONFIG_PATH) as f:
            return json.load(f)
    except Exception:
        return {}


def save_config(data):
    """Merge `data` over the existing config and persist atomically."""
    os.makedirs(CONFIG_DIR, exist_ok=True)
    merged = {**DEFAULTS, **get_config(), **data}
    tmp = CONFIG_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(merged, f, indent=2)
    os.replace(tmp, CONFIG_PATH)
    try:
        os.chmod(CONFIG_PATH, 0o600)
    except OSError:
        pass
    return merged


def is_configured():
    """Has the user completed the required fields?"""
    c = get_config()
    return all(str(c.get(k, "")).strip() for k in REQUIRED_KEYS)


def missing_required():
    c = get_config()
    return [k for k in REQUIRED_KEYS if not str(c.get(k, "")).strip()]


def get(key, default=None):
    """Read a single value with env-var fallback, for code that used to read os.environ."""
    c = get_config()
    if key in c and c[key] not in (None, ""):
        return c[key]
    env = ENV_MAPPING.get(key)
    if env and os.environ.get(env):
        return os.environ[env]
    if key in DEFAULTS:
        return DEFAULTS[key]
    return default
