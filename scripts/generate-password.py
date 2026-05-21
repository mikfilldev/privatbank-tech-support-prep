import secrets
import string

password = secrets.token_urlsafe(20)

with open("secrets/pg_password.txt", "w") as f:
    f.write(password)

print(f"Password: {password}")
print(f"Saved to secrets/pg_password.txt")
