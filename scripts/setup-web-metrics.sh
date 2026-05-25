#!/bin/bash
set -e

cat > /usr/local/bin/metrics-web.py << 'PYEOF'
#!/usr/bin/env python3
import http.server, json, shutil, subprocess, urllib.request, os

class WebMetricsHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
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

        nginx_procs = "?"
        try:
            r = subprocess.run(["ps", "-C", "nginx", "--no-headers"],
                               capture_output=True, text=True, timeout=3)
            nginx_procs = len(r.stdout.strip().split("\n")) if r.stdout.strip() else 0
        except: pass

        nginx_conn = "?"
        try:
            r = urllib.request.urlopen("http://127.0.0.1:8080/nginx_status", timeout=3)
            for line in r.read().decode().split("\n"):
                if "Active connections" in line:
                    nginx_conn = int(line.split(":")[1].strip())
                    break
        except: pass

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({
            "mem_total_mb": mem_total, "mem_avail_mb": mem_avail,
            "mem_used_pct": mem_pct,
            "disk_total_gb": disk_total, "disk_free_gb": disk_free,
            "disk_used_pct": disk_pct,
            "inode_pct": inode_pct, "inode_total": inode_total,
            "inode_free": inode_free,
            "load_1m": float(load[0]), "load_5m": float(load[1]),
            "load_15m": float(load[2]),
            "uptime_seconds": uptime_seconds,
            "nginx_procs": nginx_procs, "nginx_conn": nginx_conn,
        }).encode())
    def log_message(self, *a): pass

http.server.HTTPServer(("127.0.0.1", 8082), WebMetricsHandler).serve_forever()
PYEOF

chmod +x /usr/local/bin/metrics-web.py
cat > /etc/systemd/system/metrics-web.service << UNIT
[Unit]
Description=Web Metrics Server
After=network.target nginx.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/metrics-web.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now metrics-web
