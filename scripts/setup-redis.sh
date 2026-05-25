#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

apt-get update
apt-get install -y redis-server python3

REDIS_PASSWORD=$(cat /vagrant/secrets/redis_password.txt 2>/dev/null || echo "")

# Configure Redis for private network with password
cat > /etc/redis/redis.conf << REDIS
bind 127.0.0.1 192.168.200.13
port 6379
daemonize no
supervised systemd
loglevel notice
save 900 1
save 300 10
save 60 10000
requirepass ${REDIS_PASSWORD}
REDIS

systemctl enable redis-server
systemctl restart redis-server

# Create uv project for redis
mkdir -p /opt/redis-venv
cat > /opt/redis-venv/pyproject.toml << TOML
[project]
name = "redis-scripts"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = ["redis"]
TOML

uv sync --project /opt/redis-venv -q

# Seed Redis with sample data for NoSQL demo
cat > /tmp/seed-redis.py << PYEOF
import redis, json, random, time

r = redis.Redis(host='127.0.0.1', port=6379, db=0, password='${REDIS_PASSWORD}')
r.flushdb()

# Session-like data (key-value)
r.set('session:user:alice', json.dumps({'name': 'Alice', 'role': 'admin', 'login': '2025-05-21T10:00:00'}))
r.set('session:user:bob', json.dumps({'name': 'Bob', 'role': 'editor', 'login': '2025-05-21T11:30:00'}))
r.set('session:user:carol', json.dumps({'name': 'Carol', 'role': 'viewer', 'login': '2025-05-20T09:15:00'}))

# Counters (atomic increments)
r.set('counter:page_views', 15420)
r.set('counter:api_calls', 3891)
r.set('counter:errors_404', 42)

# Rate limiting example
for i in range(100):
    r.setex(f'rate_limit:192.168.200.{random.randint(1,254)}', 60, 1)

# Cached query results (like a materialized view)
r.setex('cache:dept_budgets', 300, json.dumps([
    {'dept': 'Engineering', 'budget': 500000},
    {'dept': 'Marketing', 'budget': 200000},
    {'dept': 'Sales', 'budget': 300000},
    {'dept': 'HR', 'budget': 100000},
    {'dept': 'IT Support', 'budget': 150000},
]))

# List: recent activity log
recent = []
for i in range(100):
    recent.append(f"event:{int(time.time()) - i*60}:user_login")
r.lpush('recent:events', *recent)
r.ltrim('recent:events', 0, 99)

# Set: online users
r.sadd('online:users', 'alice', 'bob', 'carol', 'david', 'eve')
r.sadd('online:roles:admin', 'alice')
r.sadd('online:roles:editor', 'bob')
r.sadd('online:roles:viewer', 'carol')

# Sorted set: leaderboard
for name, score in [('Alice', 95), ('Bob', 87), ('Carol', 92), ('David', 78), ('Eve', 99)]:
    r.zadd('leaderboard:scores', {name: score})

# Hash: user profiles
r.hset('user:1', mapping={'name': 'Alice Smith', 'email': 'alice@privatbank.local', 'dept': 'Engineering', 'projects': '3'})
r.hset('user:2', mapping={'name': 'Bob Johnson', 'email': 'bob@privatbank.local', 'dept': 'Engineering', 'projects': '2'})
r.hset('user:3', mapping={'name': 'Carol White', 'email': 'carol@privatbank.local', 'dept': 'Marketing', 'projects': '5'})

print(f"Redis seeded: keys={r.dbsize()}")
PYEOF

uv run --project /opt/redis-venv /tmp/seed-redis.py

# Python health/metrics server for Redis
cat > /usr/local/bin/redis-server.py << PYEOF
#!/usr/bin/env python3
import http.server, json, subprocess, shutil, redis, os

REDIS_PASSWORD = '${REDIS_PASSWORD}'

class RedisHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/":
            r = redis.Redis(host='127.0.0.1', port=6379, db=0, socket_timeout=3, password=REDIS_PASSWORD)
            try:
                info = r.info()
                keys = r.dbsize()
                memory = info.get('used_memory_human', '?')
                uptime = info.get('uptime_in_seconds', 0)
                hits = info.get('keyspace_hits', 0)
                misses = info.get('keyspace_misses', 0)
                hit_rate = round(hits / (hits + misses) * 100, 1) if (hits + misses) > 0 else 0
                clients = info.get('connected_clients', 0)
                self.send_json({
                    "status": "online",
                    "version": info.get('redis_version', '?'),
                    "keys": keys,
                    "memory": memory,
                    "uptime_seconds": uptime,
                    "hit_rate_pct": hit_rate,
                    "hits": hits,
                    "misses": misses,
                    "connected_clients": clients,
                    "role": info.get('role', '?'),
                })
            except Exception as e:
                self.send_json({"status": "degraded", "error": str(e)})

        elif self.path == "/metrics":
            with open("/proc/meminfo") as f:
                mem = dict(line.split(":") for line in f if ":" in line)
            mem_total = int(mem["MemTotal"].strip().split()[0]) // 1024
            mem_avail = int(mem["MemAvailable"].strip().split()[0]) // 1024
            mem_pct = round((mem_total - mem_avail) / mem_total * 100, 1)
            du = shutil.disk_usage("/")
            disk_total = du.total // (1024**3)
            disk_free = du.free // (1024**3)
            disk_pct = round((du.total - du.free) / du.total * 100, 1)
            st = os.statvfs("/")
            inode_total = st.f_files
            inode_free = st.f_ffree
            inode_pct = round((inode_total - inode_free) / inode_total * 100, 1)
            with open("/proc/loadavg") as f:
                load = f.read().split()[:3]
            uptime_seconds = float(open("/proc/uptime").read().split()[0])
            self.send_json({
                "mem_total_mb": mem_total, "mem_avail_mb": mem_avail, "mem_used_pct": mem_pct,
                "disk_total_gb": disk_total, "disk_free_gb": disk_free, "disk_used_pct": disk_pct,
                "inode_pct": inode_pct, "inode_total": inode_total, "inode_free": inode_free,
                "load_1m": float(load[0]), "load_5m": float(load[1]), "load_15m": float(load[2]),
                "uptime_seconds": uptime_seconds,
            })

        else:
            self.send_error(404, "Not found")

    def send_json(self, data):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def send_error(self, code, msg):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"error": msg}).encode())

    def log_message(self, *a): pass

http.server.HTTPServer(("0.0.0.0", 8080), RedisHandler).serve_forever()
PYEOF

chmod +x /usr/local/bin/redis-server.py
cat > /etc/systemd/system/redis-api.service << UNIT
[Unit]
Description=Redis API Server
After=network.target redis-server.service

[Service]
Type=simple
ExecStart=/usr/local/bin/uv run --project /opt/redis-venv /usr/local/bin/redis-server.py
Restart=always
RestartSec=5
Environment=UV_PROJECT=/opt/redis-venv

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now redis-api

# ─── Redis Practice API Server (port 8085) ───
REDIS_REF="/usr/local/share/redis-practice"
mkdir -p "$REDIS_REF"

cat > "$REDIS_REF/commands.txt" << 'CMDS'
-- 1. GET / SET — basic key-value
GET session:user:alice
SET test:hello "world"
GET test:hello
DEL test:hello

-- 2. HSET / HGET / HGETALL — hashes
HGETALL user:1
HGET user:1 name
HSET user:1 phone "+380501234567"
HGETALL user:1

-- 3. LPUSH / LRANGE / LLEN — lists
LRANGE recent:events 0 4
LLEN recent:events

-- 4. SADD / SMEMBERS / SISMEMBER — sets
SMEMBERS online:users
SISMEMBER online:users alice
SISMEMBER online:users frank

-- 5. ZADD / ZRANGE / ZREVRANGE — sorted sets
ZRANGE leaderboard:scores 0 -1 WITHSCORES
ZREVRANGE leaderboard:scores 0 2 WITHSCORES

-- 6. KEYS / TYPE / EXISTS — introspection
KEYS session:*
TYPE session:user:alice
TYPE leaderboard:scores
EXISTS cache:dept_budgets

-- 7. TTL / EXPIRE — expiry
TTL cache:dept_budgets
SET test:temp "will be deleted"
EXPIRE test:temp 5
TTL test:temp

-- 8. INCR / DECR — atomic counters
GET counter:page_views
INCR counter:page_views
INCRBY counter:page_views 10
GET counter:page_views

-- 9. INFO — server statistics (read-only)
INFO server
INFO memory
INFO keyspace

-- 10. RANDOMKEY / DBSIZE / CLIENT LIST
RANDOMKEY
DBSIZE
CLIENT LIST
CMDS

cat > /usr/local/bin/redis-practice-server.py << PYEOF
#!/usr/bin/env python3
import http.server, json, redis, os, re

REDIS_PASSWORD = '${REDIS_PASSWORD}'
CMDS_FILE = "/usr/local/share/redis-practice/commands.txt"
DANGEROUS = re.compile(r"^(FLUSHALL|FLUSHDB|CONFIG|SAVE|BGSAVE|BGREWRITEAOF|SHUTDOWN|SLAVEOF|REPLICAOF|DEBUG|CLUSTER|MONITOR|MIGRATE|RESTORE|REPLACE|SCRIPT\s+KILL)\b", re.I)

def get_redis():
    return redis.Redis(host='127.0.0.1', port=6379, db=0, socket_timeout=5, password=REDIS_PASSWORD)

def parse_commands():
    cmds = []
    with open(CMDS_FILE) as f:
        buf = []
        title = ""
        for line in f:
            if line.startswith("-- "):
                if buf:
                    cmds.append({"title": title, "command": "".join(buf).strip()})
                    buf = []
                title = line.lstrip("-- ").strip()
            else:
                buf.append(line)
        if buf:
            cmds.append({"title": title, "command": "".join(buf).strip()})
    return cmds

def parse_cmd(line):
    parts = [p.strip('"\'') for p in re.findall(r'''(?: [^\s"']+ | " [^"]* " | ' [^']* ' )''', line, re.VERBOSE)]
    if not parts:
        return None, []
    return parts[0].upper(), parts[1:]

def run_cmd(cmd_str):
    try:
        r = get_redis()
    except Exception as e:
        return {"type": "error", "content": f"Cannot connect to Redis: {e}"}
    if DANGEROUS.match(cmd_str.strip()):
        return {"type": "error", "content": "Command blocked for safety"}
    results = []
    for line in cmd_str.strip().split("\n"):
        line = line.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        cmd, args = parse_cmd(line)
        if cmd is None:
            continue
        try:
            result = r.execute_command(cmd, *args)
            if isinstance(result, bytes):
                result = result.decode()
            elif isinstance(result, list):
                result = [r.decode() if isinstance(r, bytes) else r for r in result]
            elif isinstance(result, set):
                result = [r.decode() if isinstance(r, bytes) else r for r in result]
            results.append({cmd: result})
        except Exception as e:
            results.append({cmd: str(e)})
    if not results:
        return {"type": "error", "content": "Empty command"}
    return {"type": "result", "content": results if len(results) > 1 else results[0]}

def format_result(result):
    if result["type"] == "error":
        return result["content"]
    v = result["content"]
    if isinstance(v, str):
        try:
            parsed = json.loads(v)
            return json.dumps(parsed, indent=2, ensure_ascii=False)
        except (json.JSONDecodeError, TypeError):
            return json.dumps(v, indent=2, ensure_ascii=False)
    return json.dumps(v, indent=2, default=str, ensure_ascii=False)

class RedisPracticeHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/":
            cmds = parse_commands()
            self.send_json({"status": "ok", "commands_count": len(cmds)})

        elif self.path.startswith("/command/"):
            n_str = self.path.split("/command/")[-1]
            if not n_str.isdigit():
                self.send_error(400, "Invalid command number")
                return
            n = int(n_str)
            cmds = parse_commands()
            if n < 0 or n >= len(cmds):
                self.send_error(404, "Command not found")
                return
            c = cmds[n]
            result = run_cmd(c["command"])
            self.send_json({
                "title": c["title"],
                "command": c["command"],
                "result": format_result(result),
                "result_type": result["type"],
            })

        elif self.path == "/run":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode() if length else "{}"
            try:
                params = json.loads(body)
                cmd_str = params.get("command", "").strip()
                if not cmd_str:
                    self.send_error(400, "Empty command")
                    return
                result = run_cmd(cmd_str)
                self.send_json({
                    "command": cmd_str,
                    "result": format_result(result),
                    "result_type": result["type"],
                })
            except Exception as e:
                self.send_error(400, str(e))

        else:
            self.send_error(404)

    def do_POST(self):
        if self.path == "/run":
            self.do_GET()

    def send_json(self, data):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data, default=str).encode())

    def send_error(self, code, msg):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"error": msg}).encode())

    def log_message(self, *a): pass

http.server.HTTPServer(("0.0.0.0", 8085), RedisPracticeHandler).serve_forever()
PYEOF

chmod +x /usr/local/bin/redis-practice-server.py
cat > /etc/systemd/system/redis-practice.service << UNIT
[Unit]
Description=Redis Practice API Server
After=network.target redis-server.service

[Service]
Type=simple
ExecStart=/usr/local/bin/uv run --project /opt/redis-venv /usr/local/bin/redis-practice-server.py
Restart=always
RestartSec=5
Environment=UV_PROJECT=/opt/redis-venv

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now redis-practice

echo "Redis ready: 192.168.200.13:6379 (password in secrets/redis_password.txt), API on :8080, Practice API on :8085"
