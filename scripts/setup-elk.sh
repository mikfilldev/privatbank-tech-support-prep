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

# Configure ES
mkdir -p /etc/elasticsearch
cat > /etc/elasticsearch/elasticsearch.yml << 'ESYML'
cluster.name: lab-cluster
node.name: elk
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node
xpack.security.enabled: false
ESYML

mkdir -p /var/lib/elasticsearch /var/log/elasticsearch
chown -R elasticsearch:elasticsearch /var/lib/elasticsearch /var/log/elasticsearch

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

echo "ELK ready: ES=9200, Kibana=5601"
echo "Wait 30s for ES to start, then configure Filebeat on other VMs"
