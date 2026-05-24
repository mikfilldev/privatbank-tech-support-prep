#!/usr/bin/env python3
import sys
from faker import Faker
from random import randint, choice, gauss, random as rnd, seed as pyseed
from datetime import datetime, timedelta

fake = Faker()
Faker.seed(42)
pyseed(42)


def esc(val):
    return str(val).replace("'", "''")


dept_defs = [
    ("Engineering",         600000),
    ("Marketing",           200000),
    ("Sales",               300000),
    ("HR",                  100000),
    ("IT Support",          150000),
    ("R&D",                 700000),
    ("Finance",             280000),
    ("Customer Support",    130000),
]
floors = ["Floor 1", "Floor 2", "Floor 3", "Floor 4", "Floor 5"]

print("TRUNCATE departments, employees, products, orders, order_items RESTART IDENTITY CASCADE;")
print()

print("INSERT INTO departments (name, location, budget) VALUES")
dept_rows = []
for name, base_budget in dept_defs:
    loc = choice(floors)
    budget = int(base_budget * (0.85 + rnd() * 0.30))
    dept_rows.append(f"('{name}', '{loc}', {budget})")
print(",\n".join(dept_rows) + ";")
print()


dept_ids = list(range(1, len(dept_defs) + 1))
dept_weights = [0.18, 0.12, 0.12, 0.06, 0.14, 0.14, 0.12, 0.12]

dept_salary = {
    1: (75000, 20000),
    2: (55000, 15000),
    3: (60000, 18000),
    4: (45000, 10000),
    5: (50000, 14000),
    6: (70000, 18000),
    7: (65000, 16000),
    8: (42000, 10000),
}

print("INSERT INTO employees (name, email, department_id, salary, hired_at) VALUES")
emp_rows = []
used_emails = set()
for _ in range(120):
    while True:
        first = fake.first_name()
        last = fake.last_name()
        name = f"{first} {last}"
        email = f"{first.lower()}.{last.lower()}@privatbank.local"
        email = email.replace("'", "").encode("ascii", "ignore").decode("ascii")
        if email not in used_emails:
            used_emails.add(email)
            break

    dept_id = choice(dept_ids)
    mu, sigma = dept_salary[dept_id]
    salary = max(25000, min(180000, int(gauss(mu, sigma))))

    days_ago = randint(30, 1800)
    hired_at = (datetime.now() - timedelta(days=days_ago)).strftime("%Y-%m-%d")

    emp_rows.append(f"('{esc(name)}', '{esc(email)}', {dept_id}, {salary}, '{hired_at}')")

print(",\n".join(emp_rows) + ";")
print()


categories = ["Electronics", "Furniture", "Stationery", "OfficeSupplies", "Software"]
cat_price_range = {
    "Electronics":     (10, 3000),
    "Furniture":       (50, 1500),
    "Stationery":      (1, 100),
    "OfficeSupplies":  (3, 200),
    "Software":        (50, 2000),
}
cat_prefixes = {
    "Electronics":     ["Monitor", "Keyboard", "Mouse", "Cable", "Hub", "Speaker", "Webcam", "Headset", "Charger", "Drive", "Tablet", "Scanner"],
    "Furniture":       ["Desk", "Chair", "Cabinet", "Shelf", "Table", "Stool", "Rack", "Drawer", "Bench", "Stand", "Screen", "Divider"],
    "Stationery":      ["Notebook", "Pen", "Pencil", "Eraser", "Marker", "Tape", "Glue", "Scissors", "Ruler", "Clip", "Stapler", "Highlighter"],
    "OfficeSupplies":  ["PaperReam", "Folder", "Binder", "Envelope", "Stapler", "Label", "Toner", "Shredder", "Laminator", "Cutter", "Stamp", "Clipboard"],
    "Software":        ["Antivirus", "OfficeSuite", "IDE", "BackupTool", "VPN", "PassManager", "Analytics", "CAD", "CRM", "ERP", "Monitoring", "Collab"],
}

products = []

print("INSERT INTO products (name, category, price, stock) VALUES")
prod_rows = []
for _ in range(100):
    cat = choice(categories)
    prefix = choice(cat_prefixes[cat])
    model = fake.bothify(text="??###").upper()
    name = f"{prefix} {model}"
    lo, hi = cat_price_range[cat]
    price = round(gauss((lo + hi) / 2, (hi - lo) / 4), 2)
    price = max(lo, min(hi, price))
    stock = max(0, int(gauss(60, 80)))
    products.append({"price": price})
    prod_rows.append(f"('{name}', '{cat}', {price}, {stock})")

print(",\n".join(prod_rows) + ";")
print()


status_pool = (["delivered"] * 40 + ["shipped"] * 25 + ["pending"] * 25 + ["cancelled"] * 10)

print("INSERT INTO orders (employee_id, order_date, status) VALUES")
order_rows = []
for _ in range(200):
    emp_id = randint(1, 120)
    days_ago = randint(0, 900)
    dt = datetime.now() - timedelta(days=days_ago, hours=randint(0, 23), minutes=randint(0, 59))
    order_date = dt.strftime("%Y-%m-%d %H:%M:%S")
    status = choice(status_pool)
    order_rows.append(f"({emp_id}, '{order_date}', '{status}')")

print(",\n".join(order_rows) + ";")
print()


print("INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES")
oi_rows = []
for order_id in range(1, 201):
    num_items = max(1, int(gauss(2.5, 1.2)))
    num_items = min(num_items, 8)
    used = set()
    for _ in range(num_items):
        prod_id = randint(1, 100)
        while prod_id in used:
            prod_id = randint(1, 100)
        used.add(prod_id)
        qty = max(1, int(gauss(3, 2)))
        unit_price = products[prod_id - 1]["price"]
        oi_rows.append(f"({order_id}, {prod_id}, {qty}, {unit_price})")

print(",\n".join(oi_rows) + ";")
print()

print("ANALYZE;")
