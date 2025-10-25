Faraday for Kali Linux — pbkdf2 Setup
=====================================

This backup contains the exact configuration that fixed the Faraday authentication
issues on Kali by switching Flask-Security to `pbkdf2_sha512` and bypassing the
buggy `bcrypt` combo shipped in the upstream container.

Included Files
--------------
- `docker-compose.yaml` — Spins up PostgreSQL, Redis, and the Faraday server with
  the required environment variables and volume mounts. It also reuses the original
  Docker volumes (`config_dbdata`, `config_faraday-storage`) so existing data persists.
- `server.ini` — Custom Faraday configuration mounted into the container. The
  `[security]` block documents the pbkdf2 policy and keeps bcrypt only as a deprecated
  fallback.
- `app.py` — Patched Faraday server module. It forces Flask-Security to default to
  `pbkdf2_sha512`, accepts login via username or email, and leaves bcrypt as a
  secondary (deprecated) scheme to satisfy the Passlib context requirements.

Deployment Steps (New Machine or Fresh Kali Install)
----------------------------------------------------
1. Install Docker Engine and the Docker Compose plugin (the stock packages on
   Kali Linux work fine).
2. Copy this directory to the target host, e.g. `~/FaradayBackup`.
3. From inside the directory run:

   ```bash
   docker compose up -d
   ```

4. Wait until all three containers report healthy / running:

   ```bash
   docker ps --format '{{.Names}} {{.Status}}'
   ```

   You should see `faraday-web`, `faraday-db (healthy)`, and `faraday-redis (healthy)`.

Resetting the Admin Password (optional but recommended)
-------------------------------------------------------
The stack keeps the admin password hashed with pbkdf2. To ensure the desired
password (`NovaSenha123!`) is in place or to rotate it whenever needed:

```bash
docker compose exec faraday python - <<'PY'
import os
import psycopg2
from passlib.hash import pbkdf2_sha512

password = "NovaSenha123!"
new_hash = pbkdf2_sha512.hash(password)
conn = psycopg2.connect(
    host=os.environ.get("PGSQL_HOST", "faraday-db"),
    user=os.environ.get("PGSQL_USER", "faraday"),
    password=os.environ.get("PGSQL_PASSWD", "faraday"),
    dbname=os.environ.get("PGSQL_DBNAME", "faraday"),
)
cur = conn.cursor()
cur.execute(
    "UPDATE faraday_user SET password=%s, active=true WHERE username=%s",
    (new_hash, "admin"),
)
conn.commit()
cur.close()
conn.close()
print("Admin password reset with pbkdf2_sha512.")
PY
```

Verifying the Login API
-----------------------
Once the containers are up, validate the credentials via the REST endpoint:

```bash
curl -s -H 'Content-Type: application/json' \
  -d '{"email":"admin","password":"NovaSenha123!"}' \
  http://127.0.0.1:5985/_api/login
```

A healthy setup returns HTTP 200 along with a JSON payload that contains the CSRF
token and the `authentication_token`. The browser UI (`http://localhost:5985/_ui/`)
will accept either `admin` or `admin@example.com` with the same password.

Tweaks & Maintenance Notes
--------------------------
- **Volumes:** If you want a brand-new database/storage, remove or rename the
  `config_dbdata` and `config_faraday-storage` entries under `volumes:` before
  running `docker compose up`. Docker will then create fresh volumes.
- **Patched app.py:** The compose file bind-mounts `app.py` into the container to
  override the upstream defaults. Keep this mount in place; otherwise the container
  will revert to bcrypt and the original login bug.
- **Password rotation:** Re-run the Python snippet above with a new password whenever
  you need to change it. The hash is always generated with pbkdf2, so future logins
  keep working without touching bcrypt.
- **Backup cadence:** If you modify these files later, copy the updated versions back
  into this folder so the GitHub backup stays in sync.
