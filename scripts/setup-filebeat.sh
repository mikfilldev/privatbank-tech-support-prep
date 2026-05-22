#!/bin/bash
set -e

ELK_IP="192.168.200.14"
VERSION="8.17.3"

# Install prerequisites (tar may be missing on minimal boxes like Oracle Linux)
if command -v dnf &>/dev/null; then
  dnf install -y tar wget
elif command -v apt &>/dev/null; then
  apt-get install -y tar wget
fi

# Install Filebeat
cd /tmp
if [ ! -f "filebeat-${VERSION}-linux-x86_64.tar.gz" ]; then
  wget -q "https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${VERSION}-linux-x86_64.tar.gz"
fi
tar -xzf "filebeat-${VERSION}-linux-x86_64.tar.gz"
mv "filebeat-${VERSION}" /usr/share/filebeat

# Create filebeat user
id -u filebeat &>/dev/null || useradd -m -s /bin/bash filebeat
chown -R filebeat:filebeat /usr/share/filebeat

mkdir -p /etc/filebeat /var/log/filebeat

HOSTNAME=$(hostname)

cat > /etc/filebeat/filebeat.yml << FBEOF
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /var/log/syslog
      - /var/log/*.log
    fields:
      host: ${HOSTNAME}
      service: system

  - type: log
    enabled: true
    paths:
      - /var/log/nginx/*.log
    fields:
      host: ${HOSTNAME}
      service: nginx
    multiline.pattern: '^\d{4}'
    multiline.negate: true
    multiline.match: after

  - type: log
    enabled: true
    paths:
      - /var/log/postgresql/*.log
    fields:
      host: ${HOSTNAME}
      service: postgresql
FBEOF

# Append service-specific inputs based on hostname
if [[ "$HOSTNAME" == "web1" ]]; then
  cat >> /etc/filebeat/filebeat.yml << 'WEB'
  - type: log
    enabled: true
    paths:
      - /var/log/metrics-web.log
      - /var/log/health-server.log
    fields:
      host: web1
      service: metrics
WEB
fi

if [[ "$HOSTNAME" == "db1" ]]; then
  cat >> /etc/filebeat/filebeat.yml << 'DB'
  - type: log
    enabled: true
    paths:
      - /var/log/metrics-server.log
      - /var/log/sql-practice.log
    fields:
      host: db1
      service: database
DB
fi

if [[ "$HOSTNAME" == "dns" ]]; then
  cat >> /etc/filebeat/filebeat.yml << 'DNS'
  - type: log
    enabled: true
    paths:
      - /var/log/metrics-dns.log
      - /var/named/data/named_stats.txt
    fields:
      host: dns
      service: dns
DNS
fi

if [[ "$HOSTNAME" == "srv3" ]]; then
  cat >> /etc/filebeat/filebeat.yml << 'SRV'
  - type: log
    enabled: true
    paths:
      - /var/log/redis-api.log
    fields:
      host: srv3
      service: redis
SRV
fi

# Output to Elasticsearch
cat >> /etc/filebeat/filebeat.yml << 'OUTPUT'
output.elasticsearch:
  hosts: ["192.168.200.14:9200"]
OUTPUT

# systemd unit
cat > /etc/systemd/system/filebeat.service << 'FBUNIT'
[Unit]
Description=Filebeat
After=network.target

[Service]
Type=simple
User=filebeat
Group=filebeat
ExecStart=/usr/share/filebeat/filebeat -c /etc/filebeat/filebeat.yml -path.home /usr/share/filebeat -path.data /var/lib/filebeat -path.logs /var/log/filebeat
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
FBUNIT

systemctl daemon-reload
systemctl enable filebeat
systemctl start filebeat

echo "Filebeat ready on $HOSTNAME → ${ELK_IP}:9200"
