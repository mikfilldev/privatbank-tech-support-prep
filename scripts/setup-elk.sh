#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
ES_VERSION="8.17.3"

# Install Java
apt-get update
apt-get install -y openjdk-17-jre-headless wget curl gnupg

# Elasticsearch needs higher mmap count
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >> /etc/sysctl.conf

# ─── Elasticsearch ───
cd /tmp
if [ ! -f "elasticsearch-${ES_VERSION}-linux-x86_64.tar.gz" ]; then
  wget -q "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${ES_VERSION}-linux-x86_64.tar.gz"
fi
tar -xzf "elasticsearch-${ES_VERSION}-linux-x86_64.tar.gz"
# Handle possible extract directory name
rm -rf /usr/share/elasticsearch
if [ -d "elasticsearch-${ES_VERSION}-linux-x86_64" ]; then
  mv "elasticsearch-${ES_VERSION}-linux-x86_64" /usr/share/elasticsearch
elif [ -d "elasticsearch-${ES_VERSION}" ]; then
  mv "elasticsearch-${ES_VERSION}" /usr/share/elasticsearch
fi

# Create elasticsearch user
id -u elasticsearch &>/dev/null || useradd -m -s /bin/bash elasticsearch
chown -R elasticsearch:elasticsearch /usr/share/elasticsearch

# Configure ES — write to ES home config (ES reads from $ES_HOME/config/ by default)
cat > /usr/share/elasticsearch/config/elasticsearch.yml << 'ESYML'
cluster.name: lab-cluster
node.name: elk
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node
xpack.security.enabled: false
xpack.security.http.ssl.enabled: false
ESYML

mkdir -p /var/lib/elasticsearch /var/log/elasticsearch
chown -R elasticsearch:elasticsearch /var/lib/elasticsearch /var/log/elasticsearch /usr/share/elasticsearch

# systemd unit for ES
cat > /etc/systemd/system/elasticsearch.service << 'ESUNIT'
[Unit]
Description=Elasticsearch
After=network.target

[Service]
Type=simple
User=elasticsearch
Group=elasticsearch
Environment=JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ExecStart=/usr/share/elasticsearch/bin/elasticsearch
Restart=always
RestartSec=10
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
ESUNIT

systemctl daemon-reload
systemctl enable elasticsearch
systemctl start elasticsearch

# Wait for ES to be ready
echo "Waiting for Elasticsearch to start..."
for i in $(seq 1 30); do
  if curl -s http://127.0.0.1:9200 >/dev/null 2>&1; then
    echo "Elasticsearch is ready"
    break
  fi
  sleep 2
done

# ─── Kibana ───
KIBANA_VERSION="8.17.3"
cd /tmp
if [ ! -f "kibana-${KIBANA_VERSION}-linux-x86_64.tar.gz" ]; then
  wget -q "https://artifacts.elastic.co/downloads/kibana/kibana-${KIBANA_VERSION}-linux-x86_64.tar.gz"
fi
tar -xzf "kibana-${KIBANA_VERSION}-linux-x86_64.tar.gz"
# Handle possible extract directory name (with or without -linux-x86_64)
rm -rf /usr/share/kibana
if [ -d "kibana-${KIBANA_VERSION}-linux-x86_64" ]; then
  mv "kibana-${KIBANA_VERSION}-linux-x86_64" /usr/share/kibana
elif [ -d "kibana-${KIBANA_VERSION}" ]; then
  mv "kibana-${KIBANA_VERSION}" /usr/share/kibana
fi

id -u kibana &>/dev/null || useradd -m -s /bin/bash kibana
chown -R kibana:kibana /usr/share/kibana

mkdir -p /etc/kibana
cat > /etc/kibana/kibana.yml << 'KIBYML'
server.host: "0.0.0.0"
server.port: 5601
server.publicBaseUrl: "https://web1.privatbank.local/api/kibana"
server.basePath: "/api/kibana"
server.rewriteBasePath: true
elasticsearch.hosts: ["http://127.0.0.1:9200"]
KIBYML

cat > /etc/systemd/system/kibana.service << 'KIBUNIT'
[Unit]
Description=Kibana
After=elasticsearch.service
Requires=elasticsearch.service

[Service]
Type=simple
User=kibana
Group=kibana
Environment=KBN_PATH_CONF=/etc/kibana
ExecStart=/usr/share/kibana/bin/kibana
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
KIBUNIT

systemctl daemon-reload
systemctl enable kibana
systemctl start kibana

# ─── Metrics server ───
cat > /usr/local/bin/metrics-elk.py << 'PYEOF'
#!/usr/bin/env python3
import http.server, json, shutil, os

class ElkMetricsHandler(http.server.BaseHTTPRequestHandler):
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

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({
            "mem_total_mb": mem_total, "mem_avail_mb": mem_avail, "mem_used_pct": mem_pct,
            "disk_total_gb": disk_total, "disk_free_gb": disk_free, "disk_used_pct": disk_pct,
            "inode_pct": inode_pct, "inode_total": inode_total, "inode_free": inode_free,
            "load_1m": float(load[0]), "load_5m": float(load[1]), "load_15m": float(load[2]),
            "uptime_seconds": uptime_seconds,
        }).encode())
    def log_message(self, *a): pass

http.server.HTTPServer(("0.0.0.0", 8083), ElkMetricsHandler).serve_forever()
PYEOF

chmod +x /usr/local/bin/metrics-elk.py
cat > /etc/systemd/system/metrics-elk.service << UNIT
[Unit]
Description=ELK Metrics Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/metrics-elk.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now metrics-elk

echo "ELK ready: ES=9200, Kibana=5601"
echo "Wait 30s for ES to start, then configure Filebeat on other VMs"
