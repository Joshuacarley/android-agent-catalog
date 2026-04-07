#!/usr/bin/env python3
# bot/bot.py — Two-way Telegram interface for the agent team

import asyncio
import subprocess
import os
import json
import glob
from datetime import datetime
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application, CommandHandler, CallbackQueryHandler,
    MessageHandler, filters, ContextTypes
)

TOKEN       = os.environ["TELEGRAM_TOKEN"]
CHAT_ID     = int(os.environ["TELEGRAM_CHAT_ID"])
REPO        = os.environ["GITHUB_REPO"]
BUS         = "/agent/bus"
WORKSPACES  = "/agent/workspaces"
LOGS        = "/agent/logs"
BUILDS      = "/builds"

def auth(update: Update) -> bool:
    return update.effective_chat.id == CHAT_ID

def run(cmd: str, cwd: str = None) -> str:
    result = subprocess.run(
        cmd, shell=True, capture_output=True,
        text=True, cwd=cwd
    )
    return (result.stdout + result.stderr).strip()

# ── Commands ──────────────────────────────────────────────────

async def cmd_start(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not auth(update): return
    await update.message.reply_text(
        "🤖 *Android Agent Team*\n\n"
        "Commands:\n"
        "/status — active jobs\n"
        "/issues — open GitHub issues\n"
        "/build `<number>` — trigger an issue\n"
        "/ask `<prompt>` — send prompt to Claude\n"
        "/logs `<number>` — get logs for issue\n"
        "/cancel `<number>` — cancel/unlock issue\n"
        "/agents — show all agent containers\n"
        "/pause — pause all workers\n"
        "/resume — resume all workers\n"
        "/queue — show pending tasks",
        parse_mode="Markdown"
    )

async def cmd_status(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not auth(update): return

    in_progress = run(
        f'gh issue list --repo {REPO} --label in-progress '
        f'--json number,title --jq \'.[] | "  #\\(.number): \\(.title)"\'')

    queue_count = len(glob.glob(f"{BUS}/queue/*.json"))
    done_count  = len(glob.glob(f"{BUS}/done/*.json"))

    containers = run("docker ps --format '{{.Names}}: {{.Status}}' | grep agent-")

    msg = (
        f"📊 *Agent Status*\n\n"
        f"*In Progress Issues:*\n{in_progress or '  None'}\n\n"
        f"*Queue:* {queue_count} tasks pending\n"
        f"*Done:* {done_count} tasks completed\n\n"
        f"*Containers:*\n```\n{containers}\n```"
    )
    await update.message.reply_text(msg, parse_mode="Markdown")

async def cmd_issues(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not auth(update): return
    issues = run(
        f'gh issue list --repo {REPO} --state open --limit 10 '
        f'--json number,title,labels '
        f'--jq \'.[] | "#\\(.number) [\\(.labels | map(.name) | join(","))] \\(.title)"\'')
    await update.message.reply_text(
        f"📋 *Open Issues:*\n```\n{issues or 'None'}\n```",
        parse_mode="Markdown"
    )

async def cmd_build(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not auth(update): return
    if not ctx.args:
        await update.message.reply_text("Usage: /build <issue_number>")
        return
    issue = ctx.args[0]
    await update.message.reply_text(f"🚀 Triggering issue #{issue}...")
    subprocess.Popen(
        ["/agent/scripts/coordinator-single.sh", issue],
        stdout=open(f"{LOGS}/manual-trigger-{issue}.log", "w"),
        stderr=subprocess.STDOUT
    )

async def cmd_ask(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not auth(update): return
    prompt = " ".join(ctx.args) if ctx.args else ""
    if not prompt:
        await update.message.reply_text("Usage: /ask <prompt>")
        return

    await update.message.reply_text("🧠 Asking Claude...")

    # Find most recent workspace to give context
    workspaces = sorted(glob.glob(f"{WORKSPACES}/issue-*"), reverse=True)
    cwd = workspaces[0] if workspaces else BUILDS

    result = run(
        f'claude --print --allowedTools "Edit,Write,Read,Bash" "{prompt}"',
        cwd=cwd
    )
    # Split long responses
    for i in range(0, len(result), 4000):
        await update.message.reply_text(result[i:i+4000] or "No output")

async def cmd_logs(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not auth(update): return
    if not ctx.args:
        await update.message.reply_text("Usage: /logs <issue_number>")
        return
    issue = ctx.args[0]

    # Find all logs for this issue
    log_files = sorted(glob.glob(f"{LOGS}/issue-{issue}-*.log"))
    if not log_files:
        await update.message.reply_text(f"No logs found for issue #{issue}")
        return

    # Send latest log as file
    latest = log_files[-1]
    await update.message.reply_document(
        document=open(latest, "rb"),
        caption=f"Latest log for issue #{issue}: {os.path.basename(latest)}"
    )

async def cmd_cancel(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not auth(update): return
    if not ctx.args:
        await update.message.reply_text("Usage: /cancel <issue_number>")
        return
    issue = ctx.args[0]

    # Remove in-progress tasks from bus
    for f in glob.glob(f"{BUS}/in-progress/issue-{issue}-*.json"):
        os.rename(f, f.replace("/in-progress/", "/queue/"))

    run(f'gh issue edit {issue} --repo {REPO} --remove-label "in-progress"')

    # Remove workspace if requested
    await update.message.reply_text(
        f"✅ Issue #{issue} unlocked and tasks returned to queue."
    )

async def cmd_queue(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not auth(update): return
    tasks = []
    for f in sorted(glob.glob(f"{BUS}/queue/*.json")):
        try:
            data = json.load(open(f))
            tasks.append(f"  [{data['role']}] {data['description'][:60]}...")
        except Exception:
            pass
    msg = f"📬 *Pending Tasks ({len(tasks)}):*\n" + \
          ("\n".join(tasks) or "  Queue is empty")
    await update.message.reply_text(msg, parse_mode="Markdown")

async def cmd_agents(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not auth(update): return
    output = run("docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.RunningFor}}' | grep agent")
    await update.message.reply_text(f"```\n{output}\n```", parse_mode="Markdown")

async def cmd_pause(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not auth(update): return
    run("docker pause $(docker ps -q --filter name=agent-developer) "
        "$(docker ps -q --filter name=agent-architect) "
        "$(docker ps -q --filter name=agent-qa) "
        "$(docker ps -q --filter name=agent-devops) 2>/dev/null || true")
    await update.message.reply_text("⏸ All workers paused.")

async def cmd_resume(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not auth(update): return
    run("docker unpause $(docker ps -q --filter name=agent) 2>/dev/null || true")
    await update.message.reply_text("▶️ All workers resumed.")

async def cmd_review(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not auth(update): return
    if not ctx.args:
        await update.message.reply_text("Usage: /review <issue_number>")
        return
    issue = ctx.args[0]
    review_path = f"{WORKSPACES}/issue-{issue}/REVIEW.md"
    qa_path     = f"{WORKSPACES}/issue-{issue}/QA.md"

    for path, label in [(review_path, "Architect Review"), (qa_path, "QA Report")]:
        if os.path.exists(path):
            content = open(path).read()[:4000]
            await update.message.reply_text(
                f"*{label} — Issue #{issue}:*\n```\n{content}\n```",
                parse_mode="Markdown"
            )

# ── Register handlers ─────────────────────────────────────────
def main():
    app = Application.builder().token(TOKEN).build()
    app.add_handler(CommandHandler("start",   cmd_start))
    app.add_handler(CommandHandler("status",  cmd_status))
    app.add_handler(CommandHandler("issues",  cmd_issues))
    app.add_handler(CommandHandler("build",   cmd_build))
    app.add_handler(CommandHandler("ask",     cmd_ask))
    app.add_handler(CommandHandler("logs",    cmd_logs))
    app.add_handler(CommandHandler("cancel",  cmd_cancel))
    app.add_handler(CommandHandler("queue",   cmd_queue))
    app.add_handler(CommandHandler("agents",  cmd_agents))
    app.add_handler(CommandHandler("pause",   cmd_pause))
    app.add_handler(CommandHandler("resume",  cmd_resume))
    app.add_handler(CommandHandler("auth",    cmd_auth))
    app.add_handler(CommandHandler("review",  cmd_review))
    print("🤖 Bot running...")
    app.run_polling()

if __name__ == "__main__":
    main()
