#!/bin/bash

dnf install -y bind bind-utils

cat > /etc/named.conf << 'EOF'
options {
    listen-on port 53 { any; };
    listen-on-v6 port 53 { none; };
    directory       "/var/named";
    dump-file       "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    allow-query     { any; };
    recursion yes;
    forwarders { 8.8.8.8; 1.1.1.1; };
};

zone "privatbank.local" IN {
    type master;
    file "privatbank.local.zone";
};

zone "200.168.192.in-addr.arpa" IN {
    type master;
    file "200.168.192.zone";
};
EOF

cat > /var/named/privatbank.local.zone << 'EOF'
$TTL 86400
@   IN  SOA dns.privatbank.local. admin.privatbank.local. (
        2025051701
        3600
        900
        604800
        86400 )
    IN  NS  dns.privatbank.local.

dns     IN  A   192.168.200.5
web1    IN  A   192.168.200.11
db1     IN  A   192.168.200.12
srv3    IN  A   192.168.200.13
elk     IN  A   192.168.200.14
grafana IN  A   192.168.200.15
zabbix  IN  A   192.168.200.16
EOF

cat > /var/named/200.168.192.zone << 'EOF'
$TTL 86400
@   IN  SOA dns.privatbank.local. admin.privatbank.local. (
        2025051701
        3600
        900
        604800
        86400 )
    IN  NS  dns.privatbank.local.

5   IN  PTR dns.privatbank.local.
11  IN  PTR web1.privatbank.local.
12  IN  PTR db1.privatbank.local.
13  IN  PTR srv3.privatbank.local.
14  IN  PTR elk.privatbank.local.
15  IN  PTR grafana.privatbank.local.
16  IN  PTR zabbix.privatbank.local.
EOF

chown -R named:named /var/named
chmod 640 /var/named/privatbank.local.zone /var/named/200.168.192.zone

firewall-cmd --add-service=dns --permanent
firewall-cmd --reload

cat > /usr/local/bin/metrics-dns.py << 'PYEOF'
#!/usr/bin/env python3
import http.server, json, shutil, subprocess

class DnsMetricsHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/":
            self.send_error(404)
            return
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

        named_procs = "?"
        try:
            r = subprocess.run(["pgrep", "-c", "named"], capture_output=True, text=True, timeout=3)
            named_procs = int(r.stdout.strip())
        except: pass

        queries = "?"
        try:
            r = subprocess.run(["cat", "/proc/net/netstat"], capture_output=True, text=True, timeout=3)
            lines = r.stdout.strip().split("\n")
            for i, line in enumerate(lines):
                if "TcpExt:" in line and i + 1 < len(lines):
                    cols = line.split()[1:]
                    vals = lines[i + 1].split()[1:]
                    if "ListenOverflows" in cols:
                        idx = cols.index("ListenOverflows")
                        queries = sum(int(v) for v in vals[idx:])
                        break
        except: pass

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({
            "status": "online",
            "service": "bind",
            "host": "dns.privatbank.local",
            "mem_total_mb": mem_total, "mem_avail_mb": mem_avail,
            "mem_used_pct": mem_pct,
            "disk_total_gb": disk_total, "disk_free_gb": disk_free,
            "disk_used_pct": disk_pct,
            "load_1m": float(load[0]), "load_5m": float(load[1]),
            "load_15m": float(load[2]),
            "uptime_seconds": uptime_seconds,
            "named_procs": named_procs, "queries": queries,
        }).encode())
    def log_message(self, *a): pass

http.server.HTTPServer(("0.0.0.0", 8083), DnsMetricsHandler).serve_forever()
PYEOF

chmod +x /usr/local/bin/metrics-dns.py
pkill -f metrics-dns.py 2>/dev/null; sleep 1
nohup python3 /usr/local/bin/metrics-dns.py > /var/log/metrics-dns.log 2>&1 &

systemctl enable --now named

echo "BIND DNS server ready"
