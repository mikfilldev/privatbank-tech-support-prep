# Ansible Migration Plan — ansible_local

Поступовий перехід з shell скриптів на **`ansible_local`** для керування `web1`, `db1`, `dns`.

**Чому `ansible_local`:**
- Не потребує Ansible на хості (Windows)
- Не потребує окремої control VM
- Не потребує SSH ключів або inventory.yml
- Vagrant сам встановлює Ansible всередині кожної VM
- Playbook запускається з `connection: local` — кожна VM провізіонує себе сама

**Правило:** Кожна фаза незалежна. На будь-якому кроці можна повернутись до shell скриптів.

---

## Фаза 0 — Підготовка

### Створити структуру

```
Vagrant Lab/
├── ansible/
│   ├── ansible.cfg
│   └── roles/
│       ├── dns_server/
│       │   ├── tasks/main.yml
│       │   ├── templates/
│       │   │   ├── named.conf.j2
│       │   │   ├── lab.vbox.zone.j2
│       │   │   └── 56.168.192.zone.j2
│       │   └── files/
│       │       └── metrics-dns.service
│       ├── nginx/
│       │   ├── tasks/main.yml
│       │   ├── templates/
│       │   │   └── default.conf.j2
│       │   └── files/
│       │       └── metrics-web.service
│       └── postgres/
│           ├── tasks/main.yml
│           ├── templates/
│           │   ├── postgresql.conf.j2
│           │   └── pg_hba.conf.j2
│           └── files/
│               ├── health-server.service
│               └── metrics-server.service
├── Vagrantfile
├── scripts/        # залишаються до Фази 5
└── web/
```

**Inventory — НЕ ПОТРІБЕН.** Vagrant передає IP та vars через `extra_vars`.

### ansible.cfg (`ansible/ansible.cfg`)

```ini
[defaults]
host_key_checking = False
retry_files_enabled = False
stdout_callback = yaml
gathering = explicit
```

---

## Фаза 1 — DNS Client (resolvectl)

**Мета:** Замінити `scripts/setup-dns.sh` на ansible playbook.

*Скрипт запускається окремо для кожної VM через `ansible_local` в Vagrantfile.*

### Playbook: `ansible/playbooks/setup-dns-client.yml`

```yaml
- name: Configure DNS client
  hosts: all
  connection: local
  gather_facts: no
  tasks:
    - name: Set DNS server for eth1
      command: resolvectl dns eth1 {{ dns_ip }}
      changed_when: false

    - name: Set DNS domain for eth1
      command: resolvectl domain eth1 {{ domain }}
      changed_when: false
  vars:
    dns_ip: 192.168.56.5
    domain: lab.vbox
```

### Vagrantfile (фрагмент)

```ruby
config.vm.provision "ansible_local" do |ansible|
  ansible.playbook = "ansible/playbooks/setup-dns-client.yml"
  ansible.provisioning_path = "/vagrant/ansible"
end
```

Vagrant сам:
1. Встановлює Ansible всередині VM (`apt install ansible`)
2. Синхронізує папку `/vagrant`
3. Запускає `ansible-playbook` з `-c local`

### Тест

```bash
vagrant provision web1    # або db1, dns
```

---

## Фаза 2 — PostgreSQL

**Мета:** Замінити `scripts/setup-postgres.sh` на `role/postgres`.

*Запускається тільки на `db1` через окремий `ansible_local` блок в Vagrantfile.*

### Структура ролі

```
ansible/roles/postgres/
├── tasks/
│   └── main.yml
├── templates/
│   ├── postgresql.conf.j2
│   └── pg_hba.conf.j2
├── files/
│   ├── health-server.service
│   └── metrics-server.service
└── vars/
    └── main.yml
```

### `tasks/main.yml`

```yaml
- name: Install PostgreSQL
  apt:
    name: postgresql
    update_cache: yes

- name: Enable and start PostgreSQL
  systemd_service:
    name: postgresql
    enabled: yes
    state: started

- name: Create user and database
  community.postgresql.postgresql_db:
    name: "{{ pg_db }}"
    owner: "{{ pg_user }}"
  become: yes
  become_user: postgres

- name: Configure listen_addresses
  template:
    src: postgresql.conf.j2
    dest: /etc/postgresql/*/main/postgresql.conf
  notify: restart postgresql

- name: Configure pg_hba.conf
  template:
    src: pg_hba.conf.j2
    dest: /etc/postgresql/*/main/pg_hba.conf
  notify: restart postgresql

- name: Deploy health-server service
  copy:
    src: health-server.service
    dest: /etc/systemd/system/
  notify: reload systemd

- name: Deploy metrics-server service
  copy:
    src: metrics-server.service
    dest: /etc/systemd/system/
  notify: reload systemd

- name: Start health & metrics services
  systemd_service:
    name: "{{ item }}"
    enabled: yes
    state: started
  loop:
    - health-server
    - metrics-server
```

### Systemd unit: `health-server.service`

```ini
[Unit]
Description=PostgreSQL health check server
After=network.target postgresql.service

[Service]
ExecStart=/usr/local/bin/health-server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Перевага

- Systemd автоматично перезапускає health/metrics при падінні
- Немає `pkill + nohup + sleep`
- Сервери запускаються при boot автоматично

---

## Фаза 3 — BIND (DNS Server)

**Мета:** Замінити `scripts/setup-bind.sh` на `role/dns_server`.

*Запускається тільки на `dns`.*

### Структура ролі

```
ansible/roles/dns_server/
├── tasks/
│   └── main.yml
├── templates/
│   ├── named.conf.j2
│   ├── lab.vbox.zone.j2
│   └── 56.168.192.zone.j2
├── files/
│   └── metrics-dns.service
└── vars/
    └── main.yml
```

### `tasks/main.yml`

```yaml
- name: Install BIND
  dnf:
    name:
      - bind
      - bind-utils
    state: present

- name: Deploy named.conf
  template:
    src: named.conf.j2
    dest: /etc/named.conf
  notify: restart named

- name: Deploy forward zone
  template:
    src: lab.vbox.zone.j2
    dest: /var/named/lab.vbox.zone
  notify: restart named

- name: Deploy reverse zone
  template:
    src: 56.168.192.zone.j2
    dest: /var/named/56.168.192.zone
  notify: restart named

- name: Set zone file permissions
  file:
    path: "{{ item }}"
    owner: named
    group: named
    mode: '0640'
  loop:
    - /var/named/lab.vbox.zone
    - /var/named/56.168.192.zone

- name: Open firewall for DNS
  firewalld:
    service: dns
    permanent: yes
    state: enabled
    immediate: yes

- name: Enable and start named
  systemd_service:
    name: named
    enabled: yes
    state: started
```

### Template: `named.conf.j2`

```nginx
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

zone "{{ domain }}" IN {
    type master;
    file "lab.vbox.zone";
};

zone "56.168.192.in-addr.arpa" IN {
    type master;
    file "56.168.192.zone";
};
```

---

## Фаза 4 — Nginx

**Мета:** Замінити `scripts/setup-nginx.sh` на `role/nginx`.

*Запускається тільки на `web1`.*

### Структура ролі

```
ansible/roles/nginx/
├── tasks/
│   └── main.yml
├── templates/
│   └── default.conf.j2
├── files/
│   └── metrics-web.service
└── vars/
    └── main.yml
```

### `tasks/main.yml`

```yaml
- name: Install nginx and openssl
  apt:
    name:
      - nginx
      - openssl
    update_cache: yes

- name: Generate self-signed certificate
  openssl_certificate:
    path: /etc/nginx/ssl/lab.crt
    privatekey_path: /etc/nginx/ssl/lab.key
    csr_path: /etc/nginx/ssl/lab.csr
    provider: selfsigned
    subject_alt_name:
      - "DNS:{{ domain }}"
      - "DNS:web1.{{ domain }}"
      - "DNS:db1.{{ domain }}"
      - "DNS:dns.{{ domain }}"

- name: Deploy nginx config
  template:
    src: default.conf.j2
    dest: /etc/nginx/sites-available/default
  notify: reload nginx

- name: Copy web dashboard files
  synchronize:
    src: ../../web/
    dest: /var/www/html/
    delete: yes

- name: Deploy metrics-web service
  copy:
    src: metrics-web.service
    dest: /etc/systemd/system/
  notify: reload systemd

- name: Enable nginx
  systemd_service:
    name: nginx
    enabled: yes
    state: started
```

---

## Фаза 5 — Vagrantfile з ansible_local

**Мета:** Повністю замінити shell provisioner на `ansible_local`.

### Фінальний Vagrantfile

```ruby
pg_password = File.read("secrets/pg_password.txt").strip rescue "changeme"

Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"

  # --- dns: BIND ---
  config.vm.define "dns" do |dns|
    dns.vm.box = "oraclelinux/10"
    dns.vm.box_url = "https://oracle.github.io/vagrant-projects/boxes/oraclelinux/10.json"
    dns.vm.hostname = "dns"
    dns.vm.network "private_network", ip: "192.168.56.5"
    dns.vm.provider "virtualbox" do |vb|
      vb.memory = 512
      vb.cpus = 1
    end

    dns.vm.provision "ansible_local" do |ansible|
      ansible.playbook = "ansible/roles/dns_server/tasks/main.yml"
      ansible.provisioning_path = "/vagrant/ansible"
    end
  end

  # --- web1: Nginx ---
  config.vm.define "web1" do |web|
    web.vm.hostname = "web1"
    web.vm.network "private_network", ip: "192.168.56.11"
    web.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1
    end

    web.vm.provision "ansible_local" do |ansible|
      ansible.playbook = "ansible/roles/nginx/tasks/main.yml"
      ansible.provisioning_path = "/vagrant/ansible"
      ansible.extra_vars = {
        domain: "lab.vbox",
        dns_ip: "192.168.56.5",
      }
    end
  end

  # --- db1: PostgreSQL ---
  config.vm.define "db1" do |db|
    db.vm.hostname = "db1"
    db.vm.network "private_network", ip: "192.168.56.12"
    db.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1
    end

    db.vm.provision "ansible_local" do |ansible|
      ansible.playbook = "ansible/roles/postgres/tasks/main.yml"
      ansible.provisioning_path = "/vagrant/ansible"
      ansible.extra_vars = {
        pg_user: "labuser",
        pg_db: "labdb",
        pg_password: pg_password,
      }
    end
  end
end
```

**Важливо:** Кожна VM має свій `ansible_local` блок. Це замінює потребу в inventory — Vagrant сам знає яку роль запускати.

---

## Фаза 6 — Очищення

1. **Видалити shell скрипти** після успішного тестування:
   - `setup-nginx.sh`
   - `setup-bind.sh`
   - `setup-postgres.sh`
   - `setup-dns.sh`

2. **Видалити web/ та scripts/ з `.gitignore`** (якщо там є)

3. **Оновити `README.md`:**
   - Замінити shell → ansible в секціях
   - Зазначити що Ansible встановлюється автоматично (нічого на хості не треба)

---

## Команди для тесту

```bash
# Фаза 1-4: тестувати через Vagrant
vagrant provision dns     # BIND + DNS client
vagrant provision web1    # Nginx + web files
vagrant provision db1     # PostgreSQL + health/metrics

# Фаза 5: всі разом
vagrant up                # або vagrant provision

# Перевірити що ansible_local працює
vagrant ssh web1
ansible --version         # Ansible встановлений всередині VM
```

---

## Шпаргалка: shell → ansible модулі

| Shell команда | Ansible модуль |
|--------------|----------------|
| `apt-get install -y nginx` | `apt: name: nginx` |
| `dnf install -y bind` | `dnf: name: bind` |
| `sed -i "s/.../.../"` | `lineinfile:` або `template:` |
| `cat > file << EOF` | `template:` або `copy:` |
| `systemctl enable --now` | `systemd_service: enabled:yes state:started` |
| `firewall-cmd ...` | `firewalld:` |
| `chown user:group` | `file: owner: group:` |
| `nohup python3 ... &` | `systemd_service:` + unit file |
| `mkdir -p` | `file: state: directory` |
| `cp -r` | `synchronize:` або `copy:` |
| `openssl req ...` | `openssl_certificate:` |
| `resolvectl dns ...` | `command:` або `nmcli:` |
| `psql -U postgres -c "..."` | `community.postgresql.*` модулі |
