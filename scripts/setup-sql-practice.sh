#!/bin/bash
set -e

SQL_REF="/usr/local/share/sql-practice"

# ─── Create practice database ───
sudo -u postgres psql <<SQL
CREATE DATABASE practice_db;
\c practice_db

-- Departments
CREATE TABLE departments (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    location VARCHAR(100),
    budget NUMERIC(12,2)
);

INSERT INTO departments (name, location, budget) VALUES
('Engineering',   'Floor 3', 500000),
('Marketing',     'Floor 2', 200000),
('Sales',         'Floor 1', 300000),
('HR',            'Floor 2', 100000),
('IT Support',    'Floor 3', 150000);

-- Employees
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(150) UNIQUE,
    department_id INT REFERENCES departments(id),
    salary NUMERIC(10,2),
    hired_at DATE DEFAULT CURRENT_DATE
);

INSERT INTO employees (name, email, department_id, salary, hired_at) VALUES
('Alice Smith',     'alice@lab.vbox',   1, 85000,  '2022-03-15'),
('Bob Johnson',     'bob@lab.vbox',     1, 72000,  '2023-01-10'),
('Carol White',     'carol@lab.vbox',   2, 65000,  '2021-06-01'),
('David Brown',     'david@lab.vbox',   2, 58000,  '2024-02-20'),
('Eve Davis',       'eve@lab.vbox',     3, 91000,  '2020-11-05'),
('Frank Miller',    'frank@lab.vbox',   3, 47000,  '2024-07-01'),
('Grace Wilson',    'grace@lab.vbox',   4, 52000,  '2023-09-12'),
('Henry Moore',     'henry@lab.vbox',   5, 48000,  '2022-12-01'),
('Ivy Taylor',      'ivy@lab.vbox',     1, 95000,  '2021-04-18'),
('Jack Anderson',   'jack@lab.vbox',    4, 44000,  '2024-05-30');

-- Products
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    category VARCHAR(50),
    price NUMERIC(10,2),
    stock INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO products (name, category, price, stock) VALUES
('Laptop Pro 15',   'Electronics', 1499.99,  25),
('Wireless Mouse',  'Electronics',   29.99, 200),
('USB-C Hub',       'Electronics',   49.99, 150),
('Desk Lamp',       'Furniture',     89.99,  40),
('Ergonomic Chair', 'Furniture',    399.99,  15),
('Notebook Set',    'Stationery',    12.99, 500),
('Whiteboard',      'Stationery',    45.00,  30),
('Monitor 27"',     'Electronics',  299.99,  18),
('Keyboard Mech',   'Electronics',   89.99,  60),
('Standing Desk',   'Furniture',    799.99,   8);

-- Orders
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    employee_id INT REFERENCES employees(id),
    order_date TIMESTAMP DEFAULT NOW(),
    status VARCHAR(20) DEFAULT 'pending'
);

INSERT INTO orders (employee_id, order_date, status) VALUES
(1, '2025-01-10', 'delivered'),
(2, '2025-01-12', 'delivered'),
(1, '2025-02-05', 'shipped'),
(3, '2025-02-10', 'delivered'),
(5, '2025-03-01', 'cancelled'),
(6, '2025-03-15', 'pending'),
(4, '2025-04-01', 'shipped'),
(7, '2025-04-10', 'pending'),
(9, '2025-04-15', 'shipped'),
(10, '2025-05-01', 'pending'),
(2, '2025-05-10', 'pending'),
(8, '2025-05-15', 'shipped');

-- Order items
CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INT REFERENCES orders(id),
    product_id INT REFERENCES products(id),
    quantity INT NOT NULL,
    unit_price NUMERIC(10,2)
);

INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
(1,  1,  1, 1499.99),
(1,  2,  2,   29.99),
(2,  5,  1,  399.99),
(2,  4,  1,   89.99),
(3,  8,  2,  299.99),
(3,  9,  1,   89.99),
(4,  6, 10,   12.99),
(5,  7,  1,   45.00),
(6,  3,  3,   49.99),
(7, 10,  1,  799.99),
(8,  2,  5,   29.99),
(9,  1,  1, 1499.99),
(9,  8,  1,  299.99),
(10, 6, 20,   12.99),
(11, 9,  2,   89.99),
(12, 5,  2,  399.99);
SQL

echo "practice_db created with tables: departments, employees, products, orders, order_items"

# ─── Indexes ───
sudo -u postgres psql -d practice_db <<SQL
CREATE INDEX idx_employees_dept ON employees(department_id);
CREATE INDEX idx_orders_employee ON orders(employee_id);
CREATE INDEX idx_order_items_order ON order_items(order_id);
CREATE INDEX idx_order_items_product ON order_items(product_id);
CREATE INDEX idx_products_category ON products(category);
CREATE INDEX idx_orders_status ON orders(status);
ANALYZE;
SQL

echo "Indexes created and analyzed"

# ─── Reference SQL queries file ───
mkdir -p "$SQL_REF"

cat > "$SQL_REF/queries.sql" << 'QUERIES'
-- ==========================================
-- SQL Practice Reference — practice_db
-- ==========================================

-- 1. Basic SELECT with JOIN
SELECT e.name, d.name AS department, e.salary
FROM employees e
JOIN departments d ON e.department_id = d.id;

-- 2. Aggregation with GROUP BY
SELECT d.name, COUNT(e.id) AS emp_count, ROUND(AVG(e.salary), 2) AS avg_salary
FROM departments d
LEFT JOIN employees e ON e.department_id = d.id
GROUP BY d.id, d.name
ORDER BY avg_salary DESC;

-- 3. Subquery: employees above department average
SELECT e.name, e.salary, d.name AS dept
FROM employees e
JOIN departments d ON e.department_id = d.id
WHERE e.salary > (
    SELECT AVG(salary) FROM employees WHERE department_id = e.department_id
);

-- 4. CTE: top spenders
WITH dept_spend AS (
    SELECT d.name, SUM(oi.quantity * oi.unit_price) AS total_spent
    FROM departments d
    JOIN employees e ON e.department_id = d.id
    JOIN orders o ON o.employee_id = e.id
    JOIN order_items oi ON oi.order_id = o.id
    WHERE o.status = 'delivered'
    GROUP BY d.name
)
SELECT * FROM dept_spend ORDER BY total_spent DESC;

-- 5. Window function: rank departments by budget
SELECT name, budget,
       RANK() OVER (ORDER BY budget DESC) AS rank,
       DENSE_RANK() OVER (ORDER BY budget DESC) AS dense_rank,
       NTILE(4) OVER (ORDER BY budget DESC) AS quartile
FROM departments;

-- 6. Running total by order date
SELECT o.id, o.order_date, oi.unit_price, oi.quantity,
       SUM(oi.unit_price * oi.quantity) OVER (
           PARTITION BY o.id ORDER BY oi.id
       ) AS running_total
FROM orders o
JOIN order_items oi ON oi.order_id = o.id
ORDER BY o.id, oi.id;

-- 7. EXPLAIN examples
EXPLAIN SELECT * FROM employees WHERE department_id = 1;
EXPLAIN SELECT * FROM employees WHERE email = 'alice@lab.vbox';

-- 8. Find products never ordered
SELECT p.name, p.category
FROM products p
LEFT JOIN order_items oi ON oi.product_id = p.id
WHERE oi.id IS NULL;

-- 9. Employees with most orders
SELECT e.name, COUNT(o.id) AS order_count, SUM(oi.quantity * oi.unit_price) AS total_value
FROM employees e
JOIN orders o ON o.employee_id = e.id
JOIN order_items oi ON oi.order_id = o.id
GROUP BY e.id, e.name
ORDER BY total_value DESC;

-- 10. Pending orders value
SELECT o.id, e.name, o.order_date, SUM(oi.quantity * oi.unit_price) AS order_total
FROM orders o
JOIN employees e ON e.id = o.employee_id
JOIN order_items oi ON oi.order_id = o.id
WHERE o.status = 'pending'
GROUP BY o.id, e.name, o.order_date
ORDER BY o.order_date;
QUERIES

# ─── Python query API server ───
cat > /usr/local/bin/sql-practice-server.py << 'PYEOF'
#!/usr/bin/env python3
import http.server, json, subprocess, os, shutil

DB = "practice_db"
QUERIES_FILE = "/usr/local/share/sql-practice/queries.sql"

class SQLPracticeHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/":
            queries = []
            with open(QUERIES_FILE) as f:
                buf = []
                for line in f:
                    if line.startswith("-- "):
                        if buf:
                            queries.append({"title": buf[0].lstrip("-- ").strip(), "sql": "".join(buf)})
                            buf = []
                        buf.append(line)
                    else:
                        buf.append(line)
                if buf:
                    queries.append({"sql": "".join(buf)})

            self.send_json({"queries_count": len(queries), "database": DB})

        elif self.path.startswith("/query/"):
            n = self.path.split("/query/")[-1]
            if not n.isdigit():
                self.send_error(400, "Invalid query number")
                return
            n = int(n)
            with open(QUERIES_FILE) as f:
                blocks = f.read().strip().split("-- ")
            if n >= len(blocks):
                self.send_error(404, "Query not found")
                return
            sql = "-- " + blocks[n]
            # run with EXPLAIN ANALYZE
            result = self.run_sql("EXPLAIN ANALYZE " + sql)
            data = self.run_sql(sql.replace("EXPLAIN ANALYZE ", "").replace("EXPLAIN ", ""))
            self.send_json({"query": sql.strip(), "result": data, "explain": result})

        elif self.path == "/tables":
            data = self.run_sql("""
                SELECT table_name, (SELECT COUNT(*) FROM information_schema.columns WHERE table_name=t.table_name) AS cols
                FROM information_schema.tables t
                WHERE table_schema='public' ORDER BY table_name
            """)
            self.send_json({"tables": data})

        elif self.path == "/run":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode() if length else "{}"
            try:
                params = json.loads(body)
                sql = params.get("sql", "")
                if not sql.lower().startswith("select") and not sql.lower().startswith("with") and not sql.lower().startswith("explain"):
                    self.send_error(403, "Only SELECT queries allowed")
                    return
                data = self.run_sql(sql)
                self.send_json({"result": data})
            except Exception as e:
                self.send_error(400, str(e))

        else:
            self.send_error(404)

    def do_POST(self):
        if self.path == "/run":
            self.do_GET()

    def run_sql(self, sql):
        r = subprocess.run(
            ["sudo", "-u", "postgres", "psql", "-d", DB, "-At", "-F", "|", "-c", sql],
            capture_output=True, text=True, timeout=10
        )
        if r.returncode != 0:
            return {"error": r.stderr.strip()}
        lines = [l for l in r.stdout.strip().split("\n") if l]
        rows = []
        for l in lines:
            rows.append(l.split("|"))
        return {"rows": len(rows), "data": rows[:50]}

    def send_json(self, data):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data, default=str).encode())

    def send_error(self, code, msg):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"error": msg}).encode())

    def log_message(self, *a): pass

http.server.HTTPServer(("127.0.0.1", 8082), SQLPracticeHandler).serve_forever()
PYEOF

chmod +x /usr/local/bin/sql-practice-server.py
pkill -f sql-practice-server.py 2>/dev/null; sleep 1
nohup python3 /usr/local/bin/sql-practice-server.py > /var/log/sql-practice.log 2>&1 &

echo "SQL practice ready: db=practice_db, api=127.0.0.1:8082"
