# Android Agent Team

Autonomous multi-agent Android CI/CD system powered by Claude Code.

Android Agent Team monitors your GitHub repository for issues with a
configurable label, then dispatches a team of Claude-powered agents
(architect, developers, QA, devops) that write code, run builds, test on
an Android emulator, record video of the result, and deliver APKs
directly to Telegram.

## Requirements

- TrueNAS SCALE 24.10 (Electric Eel) or newer
- A host with KVM support (`/dev/kvm` must exist on the TrueNAS host)
- A GitHub personal access token with `repo`, `issues`, and `pull_requests` scopes
- A Telegram bot token and chat ID
- Either a Claude Pro/Max subscription (recommended) or an Anthropic API key

## Install

Storage is fully managed by TrueNAS via Docker named volumes — no
pre-install script, no manual datasets.

1. Fill out the install wizard with your GitHub, Telegram, and
   Anthropic credentials.
2. Click Install. TrueNAS auto-creates the persistent volumes.
3. Once installed, open the dashboard at `http://<your-nas>:<dashboard-port>`.

See the project repository for more details:
https://github.com/Joshuacarley/android-agent-catalog
