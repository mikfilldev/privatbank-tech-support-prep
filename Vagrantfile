Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"

  pg_password = File.read("secrets/pg_password.txt").strip rescue "changeme"

  config.vm.define "dns" do |dns|
      dns.vm.box = "oraclelinux/10"
      dns.vm.box_url = "https://oracle.github.io/vagrant-projects/boxes/oraclelinux/10.json"
      dns.vm.hostname = "dns"
      dns.vm.network "private_network", ip: "192.168.200.5"
      dns.vm.provider "virtualbox" do |vb|
        vb.memory = 512
        vb.cpus = 1
      end
      dns.vm.provision "shell", path: "scripts/setup-bind.sh"
    dns.vm.provision "shell", path: "scripts/setup-filebeat.sh"
  end

  config.vm.define "web1" do |web|
    web.vm.hostname = "web1"
    web.vm.network "private_network", ip: "192.168.200.11"
    web.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1
    end
    web.vm.provision "shell", path: "scripts/setup-dns.sh"
    web.vm.provision "shell", path: "scripts/setup-nginx.sh"
    web.vm.provision "shell", path: "scripts/setup-filebeat.sh"
  end

  config.vm.define "srv3" do |srv|
    srv.vm.hostname = "srv3"
    srv.vm.network "private_network", ip: "192.168.200.13"
    srv.vm.provider "virtualbox" do |vb|
      vb.memory = 512
      vb.cpus = 1
    end
    srv.vm.provision "shell", path: "scripts/setup-dns.sh"
    srv.vm.provision "shell", path: "scripts/setup-redis.sh"
    srv.vm.provision "shell", path: "scripts/setup-filebeat.sh"
  end

  config.vm.define "elk" do |elk|
    elk.vm.hostname = "elk"
    elk.vm.network "private_network", ip: "192.168.200.14"
    elk.vm.provider "virtualbox" do |vb|
      vb.memory = 4096
      vb.cpus = 2
    end
    elk.vm.provision "shell", path: "scripts/setup-dns.sh"
    elk.vm.provision "shell", path: "scripts/setup-elk.sh"
  end

  config.vm.define "grafana" do |g|
    g.vm.hostname = "grafana"
    g.vm.network "private_network", ip: "192.168.200.15"
    g.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1
    end
    g.vm.provision "shell", path: "scripts/setup-dns.sh"
    g.vm.provision "shell", path: "scripts/setup-grafana.sh"
    g.vm.provision "shell", path: "scripts/setup-filebeat.sh"
  end

  config.vm.define "zabbix" do |z|
    z.vm.hostname = "zabbix"
    z.vm.network "private_network", ip: "192.168.200.16"
    z.vm.provider "virtualbox" do |vb|
      vb.memory = 2048
      vb.cpus = 2
    end
    z.vm.provision "shell", path: "scripts/setup-dns.sh"
    z.vm.provision "shell", path: "scripts/setup-zabbix.sh"
    z.vm.provision "shell", path: "scripts/setup-filebeat.sh"
  end

  config.vm.define "db1" do |db|
    db.vm.hostname = "db1"
    db.vm.network "private_network", ip: "192.168.200.12"
    db.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1
    end
    db.vm.provision "shell", path: "scripts/setup-dns.sh"
    db.vm.provision "shell", path: "scripts/setup-postgres.sh",
      args: [pg_password]
    db.vm.provision "shell", path: "scripts/setup-sql-practice.sh"
    db.vm.provision "shell", path: "scripts/setup-filebeat.sh"
  end
end
