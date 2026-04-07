# Android Agent Team — TrueNAS Catalog

Autonomous Android CI/CD agent team powered by Claude Code.
Install directly from TrueNAS Apps as a one-touch catalog app.

## What It Does

Label a GitHub issue → agents write code → build APK → test on emulator → record video → send to your Telegram → open PR. No cloud CI required.

## One-Touch Install

Storage is TrueNAS-managed — no pre-install script, no manual datasets.
Docker volumes are auto-created on install and persist across upgrades.

### Step 1 — Add this catalog to TrueNAS (one-time)

1. Go to **Apps → Discover Apps**
2. Click **Manage Catalogs** (top right)
3. Click **Add Catalog**
4. Fill in:
   - **Catalog Name:** `Android Agent`
   - **Repository:** `https://github.com/Joshuacarley/android-agent-catalog`
   - **Preferred Trains:** `community`
   - **Branch:** `main`
5. Click **Save** — TrueNAS will sync the catalog (takes ~30 seconds)

---

### Step 2 — Install the app

1. Go to **Apps → Discover Apps**
2. Search for **"Android Agent"**
3. Click **Install** — the only question is the dashboard port
4. Click **Install** — done. TrueNAS auto-provisions all data volumes.

---

### Step 3 — Configure via web UI

Open `http://<your-truenas-ip>:<dashboard-port>` (default `7842`).
You'll be redirected to a setup form where you enter:

| Field | Where to get it |
|-------|----------------|
| GitHub Token | github.com/settings/tokens → New token → repo + issues + pull_requests |
| GitHub Repo | `your-org/your-android-repo` |
| Telegram Bot Token | Message @BotFather → /newbot |
| Your Telegram Chat ID | Message @userinfobot |
| Anthropic Auth Mode | Subscription (recommended) or API Key |
| Anthropic API Key | console.anthropic.com → API Keys (only if API Key mode) |

Click **Save & Start Agents**. The dashboard writes the config to a
shared volume and restarts the worker containers, which pick up the
new values within seconds.

---

### Step 4 — Prepare your Android repo

Add these two files to your Android repo and push:

**`CLAUDE.md`** (in repo root) — tells agents about your codebase:
```markdown
# CLAUDE.md
## Build Command
./gradlew assembleDebug

## Tech Stack
Kotlin, Jetpack Compose, MVVM

## Package
com.yourcompany.yourapp
```

**`.github/ISSUE_TEMPLATE/agent-task.md`** — structured issue template:
Copy from: `config/agent-task-template.md` in the android-agent package.

---

### Step 5 — Trigger your first build

Create a GitHub issue in your repo with the label `claude`.
Within 5 minutes, check your Telegram — the coordinator will notify you as work begins.

---

## Telegram Commands

Once installed, control the system from Telegram:

| Command | Description |
|---------|-------------|
| `/status` | Active jobs and container health |
| `/issues` | Open GitHub issues |
| `/build 42` | Manually trigger issue #42 |
| `/ask <prompt>` | Send a prompt directly to Claude |
| `/logs 42` | Get logs for issue #42 |
| `/cancel 42` | Unlock a stuck issue |
| `/queue` | Show pending task queue |
| `/pause` | Pause all workers |
| `/resume` | Resume all workers |

## Dashboard

After installation, open:
```
http://your-truenas-ip:7842
```

Shows live container status, task queue, issue progress, and log viewer. Auto-refreshes every 15 seconds.

## Updating

TrueNAS will notify you when a new image is available (same as any catalog app). Click **Update** in the Apps UI.

## Architecture

```
GitHub Issue (labeled 'claude')
        ↓ poll
   [Coordinator] — plans tasks → bus queue
        ↓
   [Architect]  — reviews codebase → REVIEW.md
        ↓
   [Developer×N] — implements code → build verified
        ↓
   [QA Agent]   — boots emulator → tests → records video
        ↓
   [DevOps]     — final build → Telegram APK+video → GitHub PR
```

## Resource Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 16 GB | 32 GB |
| CPU | 8 cores | 16+ cores |
| Disk | 100 GB | 500 GB NVMe |
| KVM | Required | Required |

Your T640 (dual Xeon Platinum 8260, 96 threads) handles this with room to spare.
