#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Create uv project for faker
mkdir -p /opt/sql-seed
cat > /opt/sql-seed/pyproject.toml << TOML
[project]
name = "sql-seed"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = ["faker"]
TOML

uv sync --project /opt/sql-seed -q

# Generate and execute seed SQL
cp /vagrant/scripts/seed-sql-data.py /tmp/seed-sql-data.py
uv run --project /opt/sql-seed /tmp/seed-sql-data.py | sudo -u postgres psql -d practice_db
