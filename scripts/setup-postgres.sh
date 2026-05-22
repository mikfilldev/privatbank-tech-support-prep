#!/bin/bash
PASSWORD=$1

apt-get update
apt-get install -y postgresql

systemctl enable --now postgresql

sudo -u postgres psql <<SQL
CREATE USER labuser WITH PASSWORD '${PASSWORD}';
CREATE DATABASE labdb OWNER labuser;
GRANT ALL PRIVILEGES ON DATABASE labdb TO labuser;
SQL

# Listen on localhost + private network
PG_CONF=$(find /etc/postgresql -name postgresql.conf | head -1)
sed -i "s/^#listen_addresses = 'localhost'/listen_addresses = 'localhost,192.168.56.12'/" "$PG_CONF"

# Allow connections from lab network
PG_HBA=$(find /etc/postgresql -name pg_hba.conf | head -1)
echo "host labdb labuser 192.168.56.0/24 md5" >> "$PG_HBA"

systemctl restart postgresql

cat > /usr/local/bin/health-server.py << 'PYEOF'
#!/usr/bin/env python3
import http.server, json, subprocess

class HealthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        pg_status = subprocess.run(
            ["pg_isready", "-q"], capture_output=True
        ).returncode == 0
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({
            "status": "online" if pg_status else "degraded",
            "service": "postgresql",
            "host": "db1.privatbank.local",
            "pg_ready": pg_status,
        }).encode())

    def log_message(self, *a): pass

http.server.HTTPServer(("0.0.0.0", 8080), HealthHandler).serve_forever()
PYEOF

chmod +x /usr/local/bin/health-server.py
pkill -f health-server.py 2>/dev/null; sleep 1
nohup python3 /usr/local/bin/health-server.py > /var/log/health-server.log 2>&1 &

cat > /usr/local/bin/metrics-server.py << 'PYEOF'
#!/usr/bin/env python3
import http.server, json, subprocess, shutil, os

class MetricsHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # Memory
        with open("/proc/meminfo") as f:
            mem = dict(line.split(":") for line in f if ":" in line)
        mem_total = int(mem["MemTotal"].strip().split()[0]) // 1024
        mem_avail = int(mem["MemAvailable"].strip().split()[0]) // 1024
        mem_pct = round((mem_total - mem_avail) / mem_total * 100, 1)

        # Disk
        du = shutil.disk_usage("/")
        disk_total = du.total // (1024**3)
        disk_free = du.free // (1024**3)
        disk_pct = round((du.total - du.free) / du.total * 100, 1)

        # Load
        with open("/proc/loadavg") as f:
            load = f.read().split()[:3]
        load_1m, load_5m, load_15m = load

        uptime_seconds = float(open("/proc/uptime").read().split()[0])

        # PostgreSQL connections
        pg_conn = "?"
        try:
            r = subprocess.run(
                ["sudo", "-u", "postgres", "psql", "-Atc",
                 "SELECT count(*) FROM pg_stat_activity"],
                capture_output=True, text=True, timeout=3
            )
            if r.returncode == 0:
                pg_conn = int(r.stdout.strip())
        except Exception:
            pass

        # Process count
        proc_count = "?"
        try:
            r = subprocess.run(
                ["ps", "aux", "--no-headers"],
                capture_output=True, text=True, timeout=3
            )
            proc_count = len(r.stdout.strip().split("\n"))
        except Exception:
            pass

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({
            "mem_total_mb": mem_total,
            "mem_avail_mb": mem_avail,
            "mem_used_pct": mem_pct,
            "disk_total_gb": disk_total,
            "disk_free_gb": disk_free,
            "disk_used_pct": disk_pct,
            "load_1m": float(load_1m),
            "load_5m": float(load_5m),
            "load_15m": float(load_15m),
            "uptime_seconds": uptime_seconds,
            "pg_connections": pg_conn,
            "process_count": proc_count,
        }).encode())

    def log_message(self, *a): pass

http.server.HTTPServer(("0.0.0.0", 8081), MetricsHandler).serve_forever()
PYEOF

chmod +x /usr/local/bin/metrics-server.py
pkill -f metrics-server.py 2>/dev/null; sleep 1
nohup python3 /usr/local/bin/metrics-server.py > /var/log/metrics-server.log 2>&1 &

echo "PostgreSQL ready: user=labuser, db=labdb"
