#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

ZABBIX_VERSION="7.0"
ZABBIX_PASSWORD=$(cat /vagrant/secrets/zabbix_password.txt 2>/dev/null || echo "zabbix")

# Install Zabbix repository
wget -q "https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu24.04_all.deb"
dpkg -i zabbix-release_latest_7.0+ubuntu24.04_all.deb
apt-get update

# Install Zabbix server, frontend, agent, Apache
apt-get install -y zabbix-server-pgsql zabbix-frontend-php php8.3-pgsql zabbix-apache-conf zabbix-sql-scripts zabbix-agent2 postgresql apache2 libapache2-mod-php

# Create Zabbix database (idempotent)
sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='zabbix'" | grep -q 1 2>/dev/null || sudo -u postgres createuser zabbix
sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='zabbix'" | grep -q 1 2>/dev/null || sudo -u postgres createdb zabbix --owner zabbix
sudo -u postgres psql -c "ALTER USER zabbix WITH PASSWORD '${ZABBIX_PASSWORD}'" 2>/dev/null || true

# Import Zabbix schema (idempotent)
sudo -u zabbix psql zabbix -c "SELECT 1 FROM users LIMIT 1" 2>/dev/null || {
  zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | sudo -u zabbix psql zabbix
}

# Configure Zabbix server
cat > /etc/zabbix/zabbix_server.conf << ZBXSRV
DBHost=127.0.0.1
DBName=zabbix
DBUser=zabbix
DBPassword=${ZABBIX_PASSWORD}
ListenIP=0.0.0.0
ListenPort=10051
LogFile=/var/log/zabbix/zabbix_server.log
LogFileSize=10
DebugLevel=3
ZBXSRV

# Configure PHP for frontend
PHP_INI=$(find /etc/php -name php.ini -path "*/apache2/*" 2>/dev/null | head -1)
if [ -n "$PHP_INI" ]; then
  sed -i 's/^post_max_size.*/post_max_size = 16M/' "$PHP_INI"
  sed -i 's/^max_execution_time.*/max_execution_time = 300/' "$PHP_INI"
  sed -i 's/^max_input_time.*/max_input_time = 300/' "$PHP_INI"
  sed -i 's/^;date.timezone.*/date.timezone = Europe\/Kyiv/' "$PHP_INI"
fi

# Enable Zabbix Apache config (provided by zabbix-apache-conf)
a2enconf zabbix
a2enmod rewrite
PHP_MOD="php$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo 8.3)"
a2enmod "$PHP_MOD"

# Zabbix frontend config
mkdir -p /etc/zabbix/web
cat > /etc/zabbix/web/zabbix.conf.php << ZBXWEB
<?php
\$DB['TYPE']     = 'POSTGRESQL';
\$DB['SERVER']   = '127.0.0.1';
\$DB['PORT']     = '5432';
\$DB['DATABASE'] = 'zabbix';
\$DB['USER']     = 'zabbix';
\$DB['PASSWORD'] = '${ZABBIX_PASSWORD}';
\$ZBX_SERVER     = '127.0.0.1';
\$ZBX_SERVER_PORT = '10051';
\$ZBX_SERVER_NAME = 'Privatbank Lab';
\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
ZBXWEB

# Configure Zabbix agent for self-monitoring
cat > /etc/zabbix/zabbix_agent2.conf << ZBXAGT
Server=127.0.0.1
ServerActive=127.0.0.1
Hostname=zabbix
HostMetadata=system.uname
ListenPort=10050
LogFile=/var/log/zabbix/zabbix_agent2.log
LogFileSize=10
ZBXAGT

# Prepare log directory (agent2 fails if missing)
mkdir -p /var/log/zabbix
chown zabbix:zabbix /var/log/zabbix

# Start services
systemctl enable zabbix-server zabbix-agent2 apache2 postgresql
systemctl restart postgresql
systemctl restart zabbix-agent2 || true
systemctl restart apache2
# Set admin password directly in DB (server not needed)
sudo -u zabbix psql zabbix -c "ALTER TABLE users ALTER COLUMN passwd TYPE varchar(64);" 2>/dev/null || true
ADMIN_HASH=$(php -r 'echo password_hash("'"${ZABBIX_PASSWORD}"'", PASSWORD_BCRYPT);')
sudo -u zabbix psql zabbix -c "UPDATE users SET passwd='$ADMIN_HASH', attempt_failed=0, attempt_clock=0 WHERE userid=1"

# Zabbix server may take minutes on first start (cache init from schema)
# Run with timeout so provisioning doesn't hang indefinitely
systemctl stop zabbix-server 2>/dev/null || true
timeout 300 systemctl start zabbix-server || true

echo "Zabbix ready: http://192.168.200.16/zabbix (Admin / ${ZABBIX_PASSWORD})"
