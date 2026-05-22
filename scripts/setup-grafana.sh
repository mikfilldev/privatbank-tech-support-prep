#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Install Grafana
apt-get update
apt-get install -y gnupg2 software-properties-common wget

wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list

apt-get update
apt-get install -y grafana

GRAFANA_PASSWORD=$(cat /vagrant/secrets/grafana_password.txt 2>/dev/null || echo "admin")

# Configure Grafana
cat > /etc/grafana/grafana.ini << GRAFANA_CFG
[server]
http_addr = 0.0.0.0
http_port = 3000
domain = grafana.privatbank.local
root_url = https://web1.privatbank.local/api/grafana/
serve_from_sub_path = true

[auth.anonymous]
enabled = true
org_role = Viewer

[security]
admin_user = admin
admin_password = $GRAFANA_PASSWORD

[databases]
; use embedded SQLite by default
GRAFANA_CFG

# Add PostgreSQL datasource via API
cat > /tmp/configure-grafana.sh << CONF
#!/bin/bash
sleep 5  # wait for grafana to start

AUTH="admin:${GRAFANA_PASSWORD}"

# Create PostgreSQL datasource
curl -s -X POST http://\${AUTH}@localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name":"PostgreSQL (labdb)",
    "type":"postgres",
    "url":"192.168.200.12:5432",
    "access":"proxy",
    "user":"labuser",
    "database":"labdb",
    "basicAuth":false,
    "isDefault":true,
    "jsonData":{
      "sslmode":"disable",
      "postgresVersion":1600
    },
    "secureJsonData":{"password":"changeme"}
  }'

# Create practice_db datasource
curl -s -X POST http://\${AUTH}@localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name":"PostgreSQL (practice_db)",
    "type":"postgres",
    "url":"192.168.200.12:5432",
    "access":"proxy",
    "user":"postgres",
    "database":"practice_db",
    "basicAuth":false,
    "jsonData":{
      "sslmode":"disable",
      "postgresVersion":1600
    },
    "secureJsonData":{"password":""}
  }'

# Create a dashboard showing system metrics
curl -s -X POST http://\${AUTH}@localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d '{
    "dashboard": {
      "title": "Lab Overview",
      "tags": ["lab"],
      "timezone": "browser",
      "panels": [
        {
          "title": "DB Connections",
          "type": "stat",
          "datasource": "PostgreSQL (labdb)",
          "gridPos": {"h": 8, "w": 6, "x": 0, "y": 0},
          "targets": [{
            "rawSql": "SELECT count(*) FROM pg_stat_activity;",
            "format": "table"
          }]
        },
        {
          "title": "Database Size",
          "type": "gauge",
          "datasource": "PostgreSQL (labdb)",
          "gridPos": {"h": 8, "w": 6, "x": 6, "y": 0},
          "targets": [{
            "rawSql": "SELECT pg_database_size('"'labdb"'")::bigint;",
            "format": "table"
          }],
          "fieldConfig": {
            "defaults": {
              "unit": "bytes",
              "thresholds": {"mode": "absolute", "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 104857600},
                {"color": "red", "value": 524288000}
              ]}
            }
          }
        },
        {
          "title": "Departments by Budget",
          "type": "barchart",
          "datasource": "PostgreSQL (practice_db)",
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
          "targets": [{
            "rawSql": "SELECT name, budget FROM departments ORDER BY budget DESC;",
            "format": "table"
          }]
        },
        {
          "title": "Employees per Department",
          "type": "piechart",
          "datasource": "PostgreSQL (practice_db)",
          "gridPos": {"h": 8, "w": 6, "x": 0, "y": 16},
          "targets": [{
            "rawSql": "SELECT d.name, COUNT(e.id) AS cnt FROM departments d LEFT JOIN employees e ON e.department_id = d.id GROUP BY d.name ORDER BY cnt DESC;",
            "format": "table"
          }]
        },
        {
          "title": "Salary Distribution",
          "type": "histogram",
          "datasource": "PostgreSQL (practice_db)",
          "gridPos": {"h": 8, "w": 6, "x": 6, "y": 16},
          "targets": [{
            "rawSql": "SELECT salary FROM employees;",
            "format": "table"
          }]
        },
        {
          "title": "Recent Orders",
          "type": "table",
          "datasource": "PostgreSQL (practice_db)",
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 24},
          "targets": [{
            "rawSql": "SELECT o.id, e.name AS employee, o.order_date::date, o.status, SUM(oi.quantity * oi.unit_price)::numeric(10,2) AS total FROM orders o JOIN employees e ON e.id = o.employee_id JOIN order_items oi ON oi.order_id = o.id GROUP BY o.id, e.name, o.order_date, o.status ORDER BY o.order_date DESC LIMIT 20;",
            "format": "table"
          }]
        }
      ],
      "schemaVersion": 30,
      "version": 0
    },
    "overwrite": true
  }'

echo "Grafana configured"
CONF

chmod +x /tmp/configure-grafana.sh

# Enable and start
systemctl daemon-reload
systemctl enable grafana-server
systemctl start grafana-server

# Run config in background (grafana needs to be running first)
/tmp/configure-grafana.sh &

echo "Grafana ready: http://192.168.200.15:3000 (admin / password from secrets/grafana_password.txt)"
