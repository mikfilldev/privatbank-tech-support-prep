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

# Install Zabbix server, frontend, agent
apt-get install -y zabbix-server-pgsql zabbix-frontend-php zabbix-agent2 zabbix-sql-scripts postgresql

# Create Zabbix database
sudo -u postgres psql <<SQL
CREATE USER zabbix WITH PASSWORD '${ZABBIX_PASSWORD}';
CREATE DATABASE zabbix OWNER zabbix;
GRANT ALL PRIVILEGES ON DATABASE zabbix TO zabbix;
SQL

# Import Zabbix schema
zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | sudo -u zabbix psql zabbix

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
sed -i 's/^post_max_size.*/post_max_size = 16M/' /etc/php/*/apache2/php.ini
sed -i 's/^max_execution_time.*/max_execution_time = 300/' /etc/php/*/apache2/php.ini
sed -i 's/^max_input_time.*/max_input_time = 300/' /etc/php/*/apache2/php.ini
sed -i 's/^;date.timezone.*/date.timezone = Europe\/Kyiv/' /etc/php/*/apache2/php.ini

# Configure Apache for Zabbix
cat > /etc/apache2/conf-available/zabbix.conf << APACHE
Alias /zabbix /usr/share/zabbix

<Directory "/usr/share/zabbix">
    Options FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

<Directory "/usr/share/zabbix/conf">
    Require all denied
</Directory>

<Directory "/usr/share/zabbix/app">
    Require all denied
</Directory>

<Directory "/usr/share/zabbix/include">
    Require all denied
</Directory>

<Directory "/usr/share/zabbix/vendor">
    Require all denied
</Directory>
APACHE

a2enconf zabbix
a2enmod rewrite
a2dissite 000-default

# Zabbix frontend config
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
EnableRemoteCommands=1
ZBXAGT

# Start services
systemctl enable zabbix-server zabbix-agent2 apache2 postgresql
systemctl restart postgresql
systemctl restart zabbix-server
systemctl restart zabbix-agent2
systemctl restart apache2

echo "Zabbix ready: http://192.168.200.16/zabbix (Admin / ${ZABBIX_PASSWORD})"
