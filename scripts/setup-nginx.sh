#!/bin/bash
apt-get update
apt-get install -y nginx openssl

# Self-signed cert for *.privatbank.local
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/lab.key \
  -out /etc/nginx/ssl/lab.crt \
  -subj "/CN=*.privatbank.local/O=Vagrant Lab/C=UA" \
  -addext "subjectAltName=DNS:*.privatbank.local,DNS:web1.privatbank.local,DNS:db1.privatbank.local,DNS:dns.privatbank.local"

cat > /etc/nginx/sites-available/default << 'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 127.0.0.1:8080;
    location /nginx_status { stub_status; allow 127.0.0.1; deny all; }
}

server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;

    ssl_certificate     /etc/nginx/ssl/lab.crt;
    ssl_certificate_key /etc/nginx/ssl/lab.key;

    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    location /api/health/db {
        proxy_pass http://192.168.200.12:8080/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /api/health/dns {
        proxy_pass http://192.168.200.5:8083/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /api/health/db-metrics {
        proxy_pass http://192.168.200.12:8081/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /api/health/web-metrics {
        proxy_pass http://127.0.0.1:8082/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /api/health/dns-metrics {
        resolver 192.168.200.5 valid=10s;
        set $dns_metrics_target http://192.168.200.5:8083/;
        proxy_pass $dns_metrics_target;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /api/sql-practice/ {
        proxy_pass http://192.168.200.12:8082/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /api/grafana/ {
        proxy_pass http://192.168.200.15:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /api/redis/ {
        proxy_pass http://192.168.200.13:8080/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /api/redis-practice/ {
        proxy_pass http://192.168.200.13:8085/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /api/kibana/ {
        proxy_pass http://192.168.200.14:5601;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 300;
        proxy_connect_timeout 30;
    }

    location /api/health/elk-metrics {
        proxy_pass http://192.168.200.14:8083/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /api/zabbix/ {
        proxy_pass http://192.168.200.16/zabbix/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_cookie_path /zabbix /api/zabbix;
    }
}
NGINX

cp -r /vagrant/web/* /var/www/html/

systemctl enable nginx
nginx -t && systemctl reload nginx || systemctl start nginx
