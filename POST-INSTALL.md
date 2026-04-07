# Post-Install Checklist

Work through this top to bottom after installing from the TrueNAS catalog.
Each section takes 2–5 minutes.

---

## 1 — Verify containers are running

In TrueNAS → Apps, the Android Agent app should show **Running**.
Click the app → **Logs** to see each container.

Or SSH in and run:
```bash
docker ps --filter name=agent- --format "table {{.Names}}\t{{.Status}}"
```

Expected output:
```
agent-telegram-bot    Up X minutes (healthy)
agent-dashboard       Up X minutes
agent-coordinator     Up X minutes
agent-architect       Up X minutes
agent-developer-1     Up X minutes
agent-developer-2     Up X minutes
agent-qa              Up X minutes
agent-devops          Up X minutes
```

If any container shows `Restarting` — check logs:
```bash
docker logs agent-coordinator --tail 50
```

---

## 2 — Run the health check

```bash
docker exec agent-coordinator /agent/scripts/healthcheck.sh
```

All checks should pass. Common failures:

| Failure | Fix |
|---------|-----|
| `GitHub authenticated` | Check GITHUB_TOKEN in app config |
| `KVM device accessible` | Enable Virtualization in TrueNAS + BIOS |
| `AVD (Pixel_6_API_34)` | First boot takes ~10 min to create the AVD |
| `Builds directory writable` | Check DATA_PATH permissions |

---

## 3 — Authenticate Claude (subscription mode)

This is the one step that requires SSH. You only do it once.

SSH into TrueNAS:
```bash
ssh admin@192.168.50.57
docker exec -it agent-coordinator claude
```

Claude Code will print a URL like:
```
Please visit: https://claude.ai/oauth/authorize?...
```

Open that URL on your Mac/phone, log in with your claude.ai account,
and approve access. The terminal will confirm authentication.

**That's it.** The credentials are saved to the shared volume at
`/mnt/tank/agent-data/claude-credentials` — all 7 agent containers
read from this automatically. You won't need to do this again unless
you log out or the token expires (typically 90 days).

Verify auth worked:
```bash
docker exec agent-coordinator claude --print "say hello"
# Should respond: Hello!
```

Or from Telegram: `/auth`

---

## 4 — Test Telegram bot

Open Telegram, find your bot, send:
```
/start
```

You should see the command menu. If nothing happens:
- Verify TELEGRAM_TOKEN and TELEGRAM_CHAT_ID in app config
- Check: `docker logs agent-telegram-bot --tail 30`

---

## 4 — Prepare your Android repo

**Add `CLAUDE.md` to your repo root:**

```markdown
# CLAUDE.md

## Build Command
./gradlew assembleDebug

## Test Command  
./gradlew test

## Tech Stack
- Language: Kotlin
- UI: Jetpack Compose
- Architecture: MVVM
- Min SDK: 26 / Target SDK: 34

## Package Name
com.yourcompany.yourapp

## Main Activity
com.yourcompany.yourapp.MainActivity

## Code Conventions
- Follow existing patterns in the codebase
- Never hardcode strings — use strings.xml
- Run ./gradlew assembleDebug before finishing any task
```

Commit and push this file. The agents read it before every task.

---

## 5 — Add GitHub issue label

In your Android repo → Issues → Labels → New label:
- Name: `claude`
- Color: `#7B61FF` (purple looks nice)

---

## 6 — Add the issue template (optional but recommended)

Copy this to `.github/ISSUE_TEMPLATE/agent-task.md` in your Android repo:

```markdown
---
name: Agent Task
about: Task for the Claude agent team
labels: claude
---

## Description
<!-- What needs to be done? -->

## Acceptance Criteria
- [ ] 
- [ ] 

## Files Likely Involved
<!-- Optional hints -->

## Notes for Agent
<!-- Constraints, patterns to follow -->
```

---

## 7 — Fire a test issue

Create an issue in your Android repo with the `claude` label.
Keep it simple for the first test — something like:

> **Add a version display to the About screen**
> 
> Show the app version (BuildConfig.VERSION_NAME) in the About screen.
> 
> Acceptance Criteria:
> - [ ] Version string visible on About screen
> - [ ] Passes ./gradlew assembleDebug

Within 5 minutes you should receive a Telegram message:
```
📥 New issue picked up: #1
Planning tasks now...
```

Then over the next 10–20 minutes:
```
📋 Issue #1 planned — 5 tasks created
⚙️ [architect] Starting task...
⚙️ [developer] Starting task...
✅ [developer] Task done
⚙️ [qa] Starting task...
📱 APK ready — Issue #1
🎥 Test recording for issue #1
🔀 PR opened: https://github.com/your-repo/pull/1
🎉 Issue #1 complete!
```

---

## 8 — Open the dashboard

```
http://192.168.50.57:7842
```

Bookmark this. It shows live container status, task queue,
issue progress, and lets you tail logs.

---

## Troubleshooting

### Emulator fails to boot
```bash
docker exec agent-qa ls -la /dev/kvm
# Must show: crw-rw---- 1 root kvm ...

# If missing:
# TrueNAS → System → Advanced → Enable Virtualization
# Then reboot and reinstall the app
```

### Claude Code auth errors
```bash
docker exec agent-coordinator env | grep ANTHROPIC
# Should show your key

# Test it:
docker exec agent-coordinator claude --print "say hello"
```

### GitHub push fails (no permission)
```bash
docker exec agent-coordinator gh auth status
# Check token has: repo, issues, pull_requests scopes
```

### Out of disk space during build
Gradle caches grow over time. Clean up:
```bash
docker exec agent-developer-1 bash -c "rm -rf /builds/.gradle/caches/modules-*/files-*"
```

### Tasks stuck in in-progress queue
Containers may have crashed mid-task. Unlock via Telegram:
```
/cancel 42
```

Or manually:
```bash
mv /mnt/tank/agent-data/bus/in-progress/issue-42-*.json \
   /mnt/tank/agent-data/bus/queue/
```

### Updating the app
When GitHub Actions pushes a new image, TrueNAS will show an update badge
on the app. Click Update — all config is preserved.

---

## Daily Use

| You want to... | Do this |
|---------------|---------|
| Trigger an issue | Add `claude` label on GitHub, or `/build 42` in Telegram |
| Check progress | Open dashboard at `:7842` or `/status` in Telegram |
| Review what Claude did | `/review 42` in Telegram |
| Get the APK | Check Telegram — it's sent automatically |
| Watch the test | Check Telegram — video is sent automatically |
| See the PR | Check Telegram — link is sent automatically |
| Add more developer agents | Edit app in TrueNAS → increase Developer Count → Save |
| Pause overnight | `/pause` in Telegram |
| Resume | `/resume` in Telegram |
