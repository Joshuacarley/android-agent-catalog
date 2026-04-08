#!/usr/bin/env python3
"""
bot/dashboard.py — Visual multi-team dashboard server (port 7842)
Serves the SPA from web/index.html with SSE real-time updates.
"""
import json, os, queue, subprocess, threading, time
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
from urllib.parse import urlparse, parse_qs

# Add parent to path so we can import teams.py
import sys
sys.path.insert(0, os.path.dirname(__file__))
from teams import (
    collect_all_state, load_teams, add_team, delete_team,
    get_team_log_files, LOGS, LOG_ROOT, BUS_ROOT, WS_ROOT
)
import config as agent_config

PORT = 7842
HTML_PATH  = os.path.join(os.path.dirname(__file__), '..', 'web', 'index.html')
SETUP_PATH = os.path.join(os.path.dirname(__file__), '..', 'web', 'setup.html')

SECRET_KEYS = {"github_token", "telegram_token", "anthropic_api_key"}

def _restart_workers():
    """Restart all agent containers except the dashboard itself."""
    try:
        out = subprocess.check_output(
            ["docker", "ps", "-a", "--filter", "name=agent-",
             "--format", "{{.Names}}"],
            text=True, timeout=5,
        ).strip()
        names = [n for n in out.split("\n") if n and n != "agent-dashboard"]
        if names:
            subprocess.Popen(["docker", "restart", *names],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        print(f"Worker restart failed: {e}")

# ── SSE hub ───────────────────────────────────────────────────
_subs = []; _lock = threading.Lock()

def broadcast(data):
    msg = f"data: {json.dumps(data)}\n\n".encode()
    with _lock:
        dead = []
        for q in _subs:
            try:   q.put_nowait(msg)
            except: dead.append(q)
        for q in dead: _subs.remove(q)

def subscribe():
    q = queue.Queue(maxsize=50)
    with _lock: _subs.append(q)
    return q

def unsubscribe(q):
    with _lock:
        try: _subs.remove(q)
        except ValueError: pass

def broadcaster():
    while True:
        try:    broadcast(collect_all_state())
        except Exception as e: print(f"Broadcast error: {e}")
        time.sleep(3)

# ── Commands ──────────────────────────────────────────────────
def run_command(cmd, team_id=None):
    from teams import get_team_tasks, load_teams, BUS_ROOT, WS_ROOT, LOGS
    import glob
    cmd = cmd.strip()
    if not cmd: return "No command"
    parts = cmd.split(); verb = parts[0].lower()
    repo = ""
    if team_id:
        teams = load_teams()
        team = next((t for t in teams if t["id"] == team_id), None)
        if team: repo = team.get("repo","")

    bus = f"{BUS_ROOT}/{team_id}" if team_id and team_id != "default" else BUS_ROOT
    log_dir = f"{LOGS}/{team_id}" if team_id and team_id != "default" else LOGS

    if verb == "/status":
        prefix = f"agent-{team_id}-" if team_id and team_id != "default" else "agent-"
        try:
            out = subprocess.check_output(
                ["docker","ps","-a","--filter",f"name={prefix}",
                 "--format","{{.Names}}|{{.Status}}"],
                text=True, timeout=5
            ).strip()
            return out or "No containers found"
        except Exception as e: return str(e)

    elif verb == "/cancel" and len(parts) > 1:
        issue = parts[1]
        for f in glob.glob(f"{bus}/in-progress/issue-{issue}-*.json"):
            os.rename(f, f.replace("/in-progress/", "/queue/"))
        if repo:
            subprocess.run(["gh","issue","edit",issue,"--repo",repo,
                            "--remove-label","in-progress"],timeout=10,capture_output=True)
        return f"Issue #{issue} unlocked."

    elif verb == "/pause":
        subprocess.Popen(["bash","-c","docker pause $(docker ps -q --filter name=agent-) 2>/dev/null||true"])
        return "Workers paused."

    elif verb == "/resume":
        subprocess.Popen(["bash","-c","docker unpause $(docker ps -q --filter name=agent-) 2>/dev/null||true"])
        return "Workers resumed."

    elif verb == "/build" and len(parts) > 1:
        issue = parts[1]
        env = {**os.environ}
        if repo: env["GITHUB_REPO"] = repo
        subprocess.Popen(["/agent/scripts/coordinator-single.sh", issue],
            env=env,
            stdout=open(f"{log_dir}/manual-{issue}.log","w"),
            stderr=subprocess.STDOUT)
        return f"Triggered issue #{issue}."

    elif verb == "/logs" and len(parts) > 1:
        path = os.path.join(log_dir, f"issue-{parts[1]}-developer.log")
        if not os.path.exists(path): return f"Log not found: {path}"
        try: return subprocess.check_output(["tail","-60",path],text=True,timeout=3)
        except: return open(path).read()[-4000:]

    elif verb == "/ask":
        prompt = " ".join(parts[1:])
        if not prompt: return "Usage: /ask <prompt>"
        import glob as g2
        ws = f"{WS_ROOT}/{team_id}" if team_id and team_id != "default" else WS_ROOT
        workspaces = sorted(g2.glob(f"{ws}/issue-*"), reverse=True)
        cwd = workspaces[0] if workspaces else ("/agent" if os.path.isdir("/agent") else os.getcwd())
        try:
            r = subprocess.run(["claude","--print",prompt],capture_output=True,text=True,timeout=120,cwd=cwd)
            if r.returncode != 0:
                return f"claude exit {r.returncode}\nstderr:\n{r.stderr.strip()}\nstdout:\n{r.stdout.strip()}"
            return r.stdout
        except subprocess.TimeoutExpired: return "Timed out after 120s"
        except Exception as e: return f"Error: {e}"

    elif verb == "/clear_tokens":
        tlog = os.path.join(log_dir, "tokens.jsonl")
        if os.path.exists(tlog): os.rename(tlog, tlog+".bak")
        return "Token log cleared."

    else:
        return ("/status · /build <n> · /cancel <n>\n"
                "/ask <prompt> · /logs <n>\n"
                "/pause · /resume · /clear_tokens")

# ── HTTP handler ──────────────────────────────────────────────
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def do_GET(self):
        parsed = urlparse(self.path)
        p = parsed.path

        if p in ('/', '/index.html'):
            if not agent_config.is_configured():
                self.send_response(302)
                self.send_header('Location', '/setup')
                self.end_headers()
                return
            try:    body = open(HTML_PATH, 'rb').read()
            except: body = b"<h1>Dashboard HTML not found</h1>"
            self._send(200, 'text/html', body)

        elif p == '/setup':
            try:    body = open(SETUP_PATH, 'rb').read()
            except: body = b"<h1>Setup page not found</h1>"
            self._send(200, 'text/html', body)

        elif p == '/api/setup':
            # Return current config with secrets redacted (for prefill)
            cfg = agent_config.get_config()
            redacted = {k: ("" if k in SECRET_KEYS else v) for k, v in cfg.items()}
            self._json(redacted)

        elif p == '/events':
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.send_header('Cache-Control', 'no-cache')
            self.send_header('Connection', 'keep-alive')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            q = subscribe()
            try:
                init = json.dumps(collect_all_state())
                self.wfile.write(f"data: {init}\n\n".encode()); self.wfile.flush()
                while True:
                    try:    self.wfile.write(q.get(timeout=30)); self.wfile.flush()
                    except queue.Empty: self.wfile.write(b": keepalive\n\n"); self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError): pass
            finally: unsubscribe(q)

        elif p == '/api/teams':
            self._json({"teams": load_teams()})

        elif p == '/api/status':
            self._json(collect_all_state())

        elif p == '/api/log':
            qs = parse_qs(parsed.query)
            fname = qs.get('f',[''])[0]
            team_id = qs.get('team',[''])[0] or None
            log_dir = f"{LOG_ROOT}/{team_id}" if team_id and team_id != "default" else LOGS
            path = os.path.join(log_dir, os.path.basename(fname))
            if not os.path.exists(path):
                self._send(404, 'text/plain', b'Not found')
                return
            try:    text = subprocess.check_output(["tail","-100",path],text=True,timeout=3)
            except: text = open(path).read()[-8000:]
            self._send(200, 'text/plain', text.encode())

        elif p == '/health':
            self._send(200, 'text/plain', b'ok')
        else:
            self._send(404, 'text/plain', b'Not found')

    def do_POST(self):
        parsed = urlparse(self.path)
        body = self.rfile.read(int(self.headers.get('Content-Length',0)))

        if parsed.path == '/api/setup':
            try:
                data = json.loads(body or b'{}')
                # Don't overwrite secrets with empty strings on re-submission
                existing = agent_config.get_config()
                for k in SECRET_KEYS:
                    if k in data and not str(data[k]).strip() and existing.get(k):
                        data[k] = existing[k]
                missing = [
                    k for k in agent_config.REQUIRED_KEYS
                    if not str(data.get(k, existing.get(k, ""))).strip()
                ]
                if missing:
                    self._json({'ok': False, 'error': f'Missing required fields: {", ".join(missing)}'})
                    return
                agent_config.save_config(data)
                _restart_workers()
                self._json({'ok': True})
            except Exception as e:
                self._json({'ok': False, 'error': str(e)})

        elif parsed.path == '/api/command':
            try:
                data = json.loads(body)
                result = run_command(data.get('cmd',''), data.get('team_id'))
                self._json({'result': result})
            except Exception as e:
                self._json({'result': f'Error: {e}'})

        elif parsed.path == '/api/teams':
            try:
                data = json.loads(body)
                team = add_team(
                    name       = data['name'],
                    repo       = data['repo'],
                    label      = data.get('label','claude'),
                    developers = data.get('developers',2),
                    color      = data.get('color','#e8a000'),
                )
                self._json({'team': team})
            except Exception as e:
                self._json({'error': str(e)})

        elif parsed.path.startswith('/api/teams/') and parsed.path.endswith('/delete'):
            team_id = parsed.path.split('/')[3]
            try:
                delete_team(team_id)
                self._json({'ok': True})
            except Exception as e:
                self._json({'error': str(e)})
        else:
            self._send(404, 'text/plain', b'Not found')

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin','*')
        self.send_header('Access-Control-Allow-Methods','GET,POST,OPTIONS')
        self.send_header('Access-Control-Allow-Headers','Content-Type')
        self.end_headers()

    def _send(self, code, ct, body):
        self.send_response(code)
        self.send_header('Content-Type', ct)
        self.send_header('Content-Length', len(body))
        self.send_header('Access-Control-Allow-Origin','*')
        self.end_headers()
        self.wfile.write(body)

    def _json(self, data):
        self._send(200, 'application/json', json.dumps(data).encode())

# ── Main ──────────────────────────────────────────────────────
if __name__ == '__main__':
    class Server(ThreadingMixIn, HTTPServer):
        daemon_threads = True

    threading.Thread(target=broadcaster, daemon=True).start()
    print(f'Dashboard: http://0.0.0.0:{PORT}')
    try:    Server(('0.0.0.0', PORT), Handler).serve_forever()
    except KeyboardInterrupt: pass
