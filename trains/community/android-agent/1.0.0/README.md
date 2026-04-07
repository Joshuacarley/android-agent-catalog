# Android Agent Team

Autonomous multi-agent Android CI/CD system powered by Claude Code.

Monitors your GitHub repository for issues with a configurable label
and dispatches a team of Claude-powered agents (architect, developers,
QA, devops) that write code, run builds, test on an Android emulator,
record video of the result, and deliver APKs to Telegram.

## Requirements

- TrueNAS SCALE 24.10 (Electric Eel) or newer
- A host with KVM support (`/dev/kvm` must exist)
- A GitHub personal access token (`repo`, `issues`, `pull_requests`)
- A Telegram bot token and chat ID
- Either a Claude Pro/Max subscription or an Anthropic API key

## Install

The only question this wizard asks is the dashboard port. **Everything
else is configured through a web form after install** — there are no
secrets in the catalog and no pre-install steps.

1. Click **Install**. TrueNAS auto-provisions persistent volumes and
   starts the dashboard. The other containers boot into a "waiting for
   config" loop.
2. Open `http://<your-nas>:<dashboard-port>` in your browser. You'll
   be redirected to a setup form.
3. Enter your GitHub token, Telegram credentials, Anthropic auth mode,
   and agent preferences. Click **Save & Start Agents**.
4. The dashboard restarts the worker containers, which pick up the new
   config and start polling.

If you use Claude Pro/Max subscription auth, run this one-time login
on your TrueNAS host after the agents have started:

```
sudo docker exec -it agent-coordinator claude
```
