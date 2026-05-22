# Vagrant Lab — Practice Environment

Шість віртуальних машин для демонстрації навичок роботи з базами даних (SQL/NoSQL),
системами моніторингу (ELK, Grafana) та DevOps інструментами.

| VM | IP | Роль | Технології |
|----|----|------|------------|
| `dns` | 192.168.56.5 | DNS-сервер | BIND, Oracle Linux 10 |
| `web1` | 192.168.56.11 | Веб-сервер | nginx, Grafana, dashboard |
| `db1` | 192.168.56.12 | PostgreSQL | SQL (labdb + practice_db), health/metrics API |
| `srv3` | 192.168.56.13 | NoSQL | Redis (sessions, cache, rate-limiting, leaderboard) |
| `elk` | 192.168.56.14 | Логування | Elasticsearch + Kibana + Filebeat (лог-централізація) |
| `grafana` | 192.168.56.15 | Моніторинг | Grafana (дашборди з PostgreSQL) |

---

## Проєкт

Практичне завдання для демонстрації розуміння:

- **SQL** — `practice_db` з 5 таблицями, складними запитами (JOIN, CTE, window functions, EXPLAIN)
- **NoSQL** — Redis з різними типами даних (strings, hashes, lists, sets, sorted sets, rate-limiting)
- **Моніторинг** — Grafana з дашбордами, підключена до PostgreSQL; вбудована dashboard з метриками
- **Логування** — ELK stack (Elasticsearch + Kibana), Filebeat збирає логи з усіх VMs
- **DevOps** — Vagrant, VirtualBox, shell provisioning, DNS (BIND), HTTPS, reverse proxy

---

## Структура

```
vagrant-lab-practice/
├── Vagrantfile              # 6 VMs
├── web/                     # Dashboard (HTML/CSS/JS)
│   ├── index.html           # 6 карток + SQL query runner
│   ├── style.css            # Dark theme
│   └── script.js            # Polling health + metrics (10s)
├── scripts/
│   ├── setup-bind.sh        # BIND DNS + metrics-dns
│   ├── setup-dns.sh         # DNS client (resolvectl)
│   ├── setup-nginx.sh       # nginx + SSL + reverse proxy + metrics-web
│   ├── setup-postgres.sh    # PostgreSQL + health + metrics
│   ├── setup-sql-practice.sh # practice_db + indexes + reference queries
│   ├── setup-redis.sh       # Redis + seed data + API
│   ├── setup-elk.sh         # Elasticsearch + Kibana
│   ├── setup-filebeat.sh    # Filebeat (лог-збір на кожній VM)
│   ├── setup-grafana.sh     # Grafana + PostgreSQL datasource + дашборд
│   └── generate-password.py
├── secrets/
│   └── pg_password.txt
└── Ansible Migration Plan.md
```

---

## Що демонструє кожен компонент

### SQL (db1 / practice_db)

5 таблиць з `REFERENCES`, `SERIAL`, `DEFAULT`, `NUMERIC`:

- `departments` — відділи з бюджетом
- `employees` — співробітники з посиланням на відділ
- `products` — товари з категоріями та цінами
- `orders` — замовлення зі статусами
- `order_items` — елементи замовлень (M:N)

**Індекси:** на всі foreign keys, `category`, `status`. `ANALYZE` виконано.

**Reference queries** (`/usr/local/share/sql-practice/queries.sql`):
1. `JOIN` — співробітники + відділи
2. `GROUP BY + AVG` — середня зарплата по відділах
3. `Subquery` — вище середнього по відділу
4. `CTE` — топ відділів по витратах
5. `Window function` — RANK, DENSE_RANK, NTILE
6. `Running total` (OVER PARTITION BY)
7. `EXPLAIN` — аналіз планів запитів
8. `LEFT JOIN ... IS NULL` — товари без замовлень
9. Топ співробітників по сумі замовлень
10. Вартість pending замовлень

**Query API:** `https://web1.privatbank.local/api/sql-practice/query/0..9`

### NoSQL (srv3 / Redis)

Типи даних у Redis:
- **String** — сесії, лічильники (page_views, api_calls)
- **Hash** — профілі користувачів (hset)
- **List** — останні події (lpush, ltrim)
- **Set** — онлайн-користувачі, ролі (sadd, sunion)
- **Sorted Set** — лідерборд (zadd, zrange)
- **EXPIRE** — rate-limiting, кеш (setex)

**API:** `https://web1.privatbank.local/api/redis/`

### ELK (elk)

- Elasticsearch 8.17.3 — зберігання та пошук логів
- Kibana — візуалізація (https://web1.privatbank.local/api/kibana/)
- Filebeat на web1, db1, dns, srv3, grafana — збір системних логів + логів сервісів

### Grafana (grafana)

- PostgreSQL datasource (`labdb` + `practice_db`)
- Дашборд: DB connections, database size, departments budget, employees per dept, salary distribution, recent orders
- Anonymous access (Viewer role)
- `https://web1.privatbank.local/api/grafana/` (admin/admin)

---

## Quick Start

```bash
# Generate PostgreSQL password
python3 scripts/generate-password.py

# Start all VMs
vagrant up

# Open dashboard
# https://web1.privatbank.local
```

### Hosts file (C:\Windows\System32\drivers\etc\hosts)

```
192.168.56.5  dns.privatbank.local
192.168.56.11 web1.privatbank.local
192.168.56.12 db1.privatbank.local
192.168.56.13 srv3.privatbank.local
192.168.56.14 elk.privatbank.local
192.168.56.15 grafana.privatbank.local
```

---

## Reverse Proxy

| URL | Upstream |
|-----|----------|
| `/api/health/db` | `192.168.56.12:8080` |
| `/api/health/db-metrics` | `192.168.56.12:8081` |
| `/api/health/web-metrics` | `127.0.0.1:8082` |
| `/api/health/dns-metrics` | `192.168.56.5:8083` |
| `/api/sql-practice/` | `192.168.56.12:8082` |
| `/api/redis/` | `192.168.56.13:8080` |
| `/api/kibana/` | `192.168.56.14:5601` |
| `/api/grafana/` | `192.168.56.15:3000` |

---

## Vagrant Commands

| Command | Action |
|---------|--------|
| `vagrant up` | Start all VMs |
| `vagrant up db1` | Start specific VM |
| `vagrant ssh web1` | SSH to VM |
| `vagrant provision web1` | Re-run provisioning |
| `vagrant halt` | Stop all VMs |
| `vagrant destroy` | Remove all VMs |
