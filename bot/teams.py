#!/usr/bin/env python3
"""
bot/teams.py — Multi-team state management
Each team has its own GitHub repo, agent config, bus, and workspace.
"""

import json, glob, os, subprocess, time, shutil
from datetime import datetime

TEAMS_CONFIG = "/agent/config/teams.json"
BUS_ROOT     = "/agent/bus"
WS_ROOT      = "/agent/workspaces"
LOG_ROOT     = "/agent/logs"
TOKENS_ROOT  = "/agent/logs"

DEFAULT_TEAMS_CONFIG = {
    "teams": [
        {
            "id": "default",
            "name": "My Android App",
            "repo": os.environ.get("GITHUB_REPO", ""),
            "label": os.environ.get("CLAUDE_ISSUE_LABEL", "claude"),
            "color": "#f0a500",
            "agents": {
                "developers": int(os.environ.get("DEVELOPER_COUNT", 2)),
                "has_architect": True,
                "has_qa": True,
                "has_devops": True,
            },
        }
    ]
}

# ── Team config I/O ───────────────────────────────────────────

def load_teams():
    os.makedirs(os.path.dirname(TEAMS_CONFIG), exist_ok=True)
    if not os.path.exists(TEAMS_CONFIG):
        save_teams(DEFAULT_TEAMS_CONFIG["teams"])
    try:
        data = json.load(open(TEAMS_CONFIG))
        return data.get("teams", [])
    except Exception:
        return DEFAULT_TEAMS_CONFIG["teams"]

def save_teams(teams):
    os.makedirs(os.path.dirname(TEAMS_CONFIG), exist_ok=True)
    json.dump({"teams": teams}, open(TEAMS_CONFIG, "w"), indent=2)

def get_team(team_id):
    for t in load_teams():
        if t["id"] == team_id:
            return t
    return None

def add_team(name, repo, label="claude", developers=2, color="#39d0d8"):
    import re, uuid
    team_id = re.sub(r"[^a-z0-9-]", "-", name.lower())[:20] or str(uuid.uuid4())[:8]
    teams = load_teams()
    if any(t["id"] == team_id for t in teams):
        team_id = team_id + "-" + str(uuid.uuid4())[:4]
    team = {
        "id": team_id,
        "name": name,
        "repo": repo,
        "label": label,
        "color": color,
        "agents": {
            "developers": developers,
            "has_architect": True,
            "has_qa": True,
            "has_devops": True,
        },
    }
    teams.append(team)
    save_teams(teams)
    _ensure_team_dirs(team_id)
    return team

def update_team(team_id, **kwargs):
    teams = load_teams()
    for t in teams:
        if t["id"] == team_id:
            t.update(kwargs)
    save_teams(teams)

def delete_team(team_id):
    teams = [t for t in load_teams() if t["id"] != team_id]
    save_teams(teams)

def _ensure_team_dirs(team_id):
    for sub in ["queue", "in-progress", "done", "messages"]:
        os.makedirs(f"{BUS_ROOT}/{team_id}/{sub}", exist_ok=True)
    os.makedirs(f"{WS_ROOT}/{team_id}", exist_ok=True)
    os.makedirs(f"{LOG_ROOT}/{team_id}", exist_ok=True)

# ── Per-team state collection ─────────────────────────────────

def get_team_containers(team_id):
    """Get Docker containers for this team (prefixed by team_id)."""
    try:
        prefix = f"agent-{team_id}-" if team_id != "default" else "agent-"
        out = subprocess.check_output(
            ["docker", "ps", "-a", "--filter", f"name={prefix}",
             "--format", "{{.Names}}|{{.Status}}|{{.State}}"],
            text=True, timeout=5
        ).strip()
        rows = []
        for line in out.split("\n"):
            if not line.strip(): continue
            p = line.split("|")
            if len(p) < 3: continue
            # strip prefix to get role name
            name = p[0].replace(prefix, "").replace("agent-", "")
            rows.append({
                "name": name,
                "full_name": p[0],
                "status": p[1],
                "running": p[2] == "running",
            })
        return rows
    except Exception as e:
        return [{"name": "error", "full_name": "error",
                 "status": str(e), "running": False}]

def get_team_tasks(team_id, subdir):
    bus = f"{BUS_ROOT}/{team_id}" if team_id != "default" else BUS_ROOT
    tasks = []
    for f in sorted(glob.glob(f"{bus}/{subdir}/*.json")):
        try:
            d = json.load(open(f))
            bn = os.path.basename(f)
            issue = bn.split("-")[1] if "-" in bn else "?"
            age_s = int(time.time() - os.path.getmtime(f))
            age = f"{age_s//60}m {age_s%60}s" if age_s >= 60 else f"{age_s}s"
            tasks.append({
                "file": bn, "issue": issue,
                "role": d.get("role", "?"),
                "id": d.get("id", "?"),
                "desc": d.get("description", "")[:90],
                "since": age,
                "failed": d.get("failed", False),
            })
        except: pass
    return tasks

def get_team_issues(team_id):
    ws = f"{WS_ROOT}/{team_id}" if team_id != "default" else WS_ROOT
    bus = f"{BUS_ROOT}/{team_id}" if team_id != "default" else BUS_ROOT
    issues = []
    for d in sorted(glob.glob(f"{ws}/issue-*"), reverse=True):
        num = d.split("-")[-1]
        tf = f"{d}/TASKS.md"
        total = sum(1 for l in open(tf) if l.startswith("{")) if os.path.exists(tf) else 0
        done = len(glob.glob(f"{bus}/done/issue-{num}-*.json"))
        active = len(glob.glob(f"{bus}/in-progress/issue-{num}-*.json"))
        title = ""
        if os.path.exists(tf):
            for line in open(tf):
                if line.strip() and not line.startswith("{") and not line.startswith("#"):
                    title = line.strip()[:60]; break
        issues.append({
            "num": num, "title": title, "total": total,
            "done": done, "active": active,
            "pct": int(done / total * 100) if total else 0,
        })
    return issues[:8]

def get_team_tokens(team_id):
    log_dir = f"{LOG_ROOT}/{team_id}" if team_id != "default" else LOG_ROOT
    tlog = f"{log_dir}/tokens.jsonl"
    if not os.path.exists(tlog):
        return {"total_input": 0, "total_output": 0, "by_role": {}, "by_issue": {}}
    ti = to = 0
    by_role = {}; by_issue = {}
    try:
        for line in open(tlog):
            line = line.strip()
            if not line: continue
            try:
                r = json.loads(line)
                inp = int(r.get("input", 0)); out = int(r.get("output", 0))
                role = str(r.get("role", "?")); issue = str(r.get("issue", "?"))
                ti += inp; to += out
                by_role[role] = {"input": by_role.get(role, {}).get("input", 0) + inp,
                                 "output": by_role.get(role, {}).get("output", 0) + out}
                by_issue[issue] = {"input": by_issue.get(issue, {}).get("input", 0) + inp,
                                   "output": by_issue.get(issue, {}).get("output", 0) + out}
            except: pass
    except: pass
    return {"total_input": ti, "total_output": to,
            "by_role": by_role, "by_issue": by_issue}

def get_team_log_files(team_id):
    log_dir = f"{LOG_ROOT}/{team_id}" if team_id != "default" else LOG_ROOT
    files = sorted(glob.glob(f"{log_dir}/*.log"), key=os.path.getmtime, reverse=True)[:15]
    return [{"name": os.path.basename(f),
             "size": f"{os.path.getsize(f)//1024}KB",
             "mtime": datetime.fromtimestamp(os.path.getmtime(f)).strftime("%H:%M:%S")}
            for f in files]

def collect_team_state(team):
    tid = team["id"]
    containers = get_team_containers(tid)
    active = get_team_tasks(tid, "in-progress")
    queue = get_team_tasks(tid, "queue")
    bus = f"{BUS_ROOT}/{tid}" if tid != "default" else BUS_ROOT
    done_count = len(glob.glob(f"{bus}/done/*.json"))

    # Build pipeline node states from active tasks
    pipeline_active = {}
    for task in active:
        pipeline_active[task["role"]] = {
            "issue": task["issue"],
            "desc": task["desc"],
            "since": task["since"],
        }

    return {
        "id": tid,
        "name": team["name"],
        "repo": team["repo"],
        "color": team.get("color", "#f0a500"),
        "agents": team.get("agents", {}),
        "containers": containers,
        "active": active,
        "queue": queue,
        "done_count": done_count,
        "issues": get_team_issues(tid),
        "tokens": get_team_tokens(tid),
        "logs": get_team_log_files(tid),
        "pipeline_active": pipeline_active,
        "container_count": len(containers),
        "running_count": sum(1 for c in containers if c["running"]),
    }

def collect_all_state():
    teams = load_teams()
    return {
        "ts": datetime.now().strftime("%H:%M:%S"),
        "teams": [collect_team_state(t) for t in teams],
    }
