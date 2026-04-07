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
- A dataset on your pool for agent data (e.g. `/mnt/tank/agent-data`)
- A GitHub personal access token with `repo`, `issues`, and `pull_requests` scopes
- A Telegram bot token and chat ID
- Either a Claude Pro/Max subscription (recommended) or an Anthropic API key

## Install

1. Create the data dataset on your pool before installing.
2. Fill out the install wizard with your GitHub, Telegram, Anthropic
   credentials and storage path.
3. Once installed, open the dashboard at `http://<your-nas>:<dashboard-port>`.

See the project repository for more details:
https://github.com/Joshuacarley/android-agent-catalog
