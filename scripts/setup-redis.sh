#!/bin/bash
set -e

apt-get update
apt-get install -y redis-server python3

# Configure Redis for private network
cat > /etc/redis/redis.conf << 'REDIS'
bind 127.0.0.1 192.168.56.13
port 6379
daemonize no
supervised systemd
loglevel notice
save 900 1
save 300 10
save 60 10000
REDIS

systemctl enable redis-server
systemctl restart redis-server

# Seed Redis with sample data for NoSQL demo
cat > /tmp/seed-redis.py << 'PYEOF'
import redis, json, random, time

r = redis.Redis(host='127.0.0.1', port=6379, db=0)
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
    r.setex(f'rate_limit:192.168.56.{random.randint(1,254)}', 60, 1)

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
r.hset('user:1', mapping={'name': 'Alice Smith', 'email': 'alice@lab.vbox', 'dept': 'Engineering', 'projects': '3'})
r.hset('user:2', mapping={'name': 'Bob Johnson', 'email': 'bob@lab.vbox', 'dept': 'Engineering', 'projects': '2'})
r.hset('user:3', mapping={'name': 'Carol White', 'email': 'carol@lab.vbox', 'dept': 'Marketing', 'projects': '5'})

print(f"Redis seeded: keys={r.dbsize()}")
PYEOF

python3 /tmp/seed-redis.py

# Python health/metrics server for Redis
cat > /usr/local/bin/redis-server.py << 'PYEOF'
#!/usr/bin/env python3
import http.server, json, subprocess, shutil, redis, os

class RedisHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/":
            r = redis.Redis(host='127.0.0.1', port=6379, db=0, socket_timeout=3)
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
            with open("/proc/loadavg") as f:
                load = f.read().split()[:3]
            uptime_seconds = float(open("/proc/uptime").read().split()[0])
            self.send_json({
                "mem_total_mb": mem_total, "mem_avail_mb": mem_avail, "mem_used_pct": mem_pct,
                "disk_total_gb": disk_total, "disk_free_gb": disk_free, "disk_used_pct": disk_pct,
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
pkill -f redis-server.py 2>/dev/null; sleep 1
nohup python3 /usr/local/bin/redis-server.py > /var/log/redis-api.log 2>&1 &

echo "Redis ready: 192.168.56.13:6379, API on :8080"
