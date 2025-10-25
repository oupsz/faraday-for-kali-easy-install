**Project Lead:** Pedro W. L. Soares de Souza (a.k.a. Mr.Blue)  
**Implementation Support:** Codex AI assistant

# Faraday for Kali Linux — pbkdf2 Easy Install

A ready-to-run Docker Compose bundle that installs **Faraday (Community Edition)** on Kali Linux with a stable `pbkdf2_sha512` password policy. This setup replaces the upstream `bcrypt` defaults that caused `UnknownHashError`, truncated passwords, and other incompatibilities between Flask-Security, Passlib, and `bcrypt` inside the official container.

> **Maintainer:** Pedro W. L. Soares de Souza (a.k.a. Mr.Blue) — with implementation support from the Codex AI assistant.

---

## Tested Environment
- Kali Linux Rolling (2024.x)
- Docker Engine ≥ 24.x
- Docker Compose Plugin ≥ 2.x (included with Docker Desktop/Engine on recent Kali builds)
- Faraday container image: `faradaysec/faraday:latest` (Community Edition)

The project should also work on any Debian-based distro with Docker installed, but all testing was done on Kali.

---

## Why this repo exists
1. **bcrypt / passlib bug:** The official image ships a combination of `bcrypt` and `passlib` that throws `UnknownHashError`, refuses long passwords (`password cannot be longer than 72 bytes`), or crashes with `bcrypt has no attribute __about__`.
2. **Config not honored:** Faraday ignores runtime tweaks (`SERVER.INI`, env vars) unless they are injected during boot *and* its Python defaults are overridden.
3. **Manual fixes are painful:** Repeating the same tweaks on every new install wastes time. This repo makes the process reproducible.

The solution here forces Flask-Security to default to `pbkdf2_sha512`, keeps `bcrypt` only as a deprecated fallback, adds a login form that accepts username **and** email, and provides scripts to reset the admin password with the correct hash.

---

## Contents
| File | Purpose |
| --- | --- |
| `docker-compose.yaml` | Orchestrates PostgreSQL, Redis, and the Faraday web container. Exports the necessary `SECURITY_*` variables and mounts the patched files. |
| `server.ini` | Custom Faraday configuration (database connection, storage path, `pbkdf2` security policy). |
| `app.py` | Patched Faraday module that overrides the upstream Flask-Security defaults and allows login via username or email. |
| `install.sh` | Automation script: validates prerequisites, launches the stack, waits for the containers, resets the `admin` password, and prints the access URL. |
| `LICENSE` | MIT license for this repository. |

---

## Quick Start (scripted)
```bash
# clone the repo
git clone https://github.com/oupsz/faraday-for-kali-easy-install.git
cd faraday-for-kali-easy-install

# run the installer
chmod +x install.sh
./install.sh
```

When the script finishes you should see the Faraday login page at `http://127.0.0.1:5985/_ui/`.

**Default credentials**
- Username / Email: `admin` or `admin@example.com`
- Password: `NovaSenha123!`

---

## Manual Deployment (if you prefer)
1. Install prerequisites:
   ```bash
   sudo apt update
   sudo apt install docker.io docker-compose-plugin curl python3-psycopg2 -y
   sudo systemctl enable --now docker
   ```

2. Clone this repo and move into it:
   ```bash
   git clone https://github.com/oupsz/faraday-for-kali-easy-install.git
   cd faraday-for-kali-easy-install
   ```

3. Start the stack:
   ```bash
   docker compose up -d
   ```

4. Check container status:
   ```bash
   docker ps --format '{{.Names}} {{.Status}}'
   # expect: faraday-web (Up), faraday-db (healthy), faraday-redis (healthy)
   ```

5. Reset or set the admin password (pbkdf2 hash) any time:
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

6. Test the API login:
   ```bash
   curl -s -H 'Content-Type: application/json' \
     -d '{"email":"admin","password":"NovaSenha123!"}' \
     http://127.0.0.1:5985/_api/login
   ```
   A successful response returns HTTP 200 and the authentication token.

---

## Data Persistence & Backups
- **Database volume:** `config_dbdata`
- **Storage volume:** `config_faraday-storage`

To back up:
```bash
docker run --rm -v config_dbdata:/volume -v "$(pwd)":/backup alpine \
  tar czf /backup/config_dbdata.tgz -C /volume .
```
(Repeat for `config_faraday-storage`.)

To restore, stop the stack, remove the volume, and untar the archive back into a fresh volume or bind-mount.

If you prefer a clean install, edit `docker-compose.yaml` and remove the `external: true` entries so Docker creates new volumes automatically.

---

## Logs & Troubleshooting
- Web container logs: `docker logs faraday-web`
- PostgreSQL logs: `docker logs faraday-db`
- Redis logs: `docker logs faraday-redis`
- Installer logs: `faraday-launch.log` (generated when using the desktop launcher or script).

### Known Issues
| Symptom | Cause | Fix |
| --- | --- | --- |
| `passlib.exc.UnknownHashError` on `/api/login` | Faraday fell back to bcrypt hash context | Ensure `app.py` override is mounted (see compose) and rerun `docker compose up -d`. |
| `ValueError: password cannot be longer than 72 bytes` | Native bcrypt limitation in the base image | Use the bundled pbkdf2 policy; reset password with the Python snippet above. |
| Container reboot loops with `Error: No such option: --config` | Passing unsupported CLI args | Use the provided compose file which exports the config via env vars instead. |
| Login form rejects `admin@example.com` | Upstream login form only checked username | The patched `app.py` fixes this. If you overwrite it, reapply the patch. |

---

## Security Notes
- This setup exposes Faraday on `127.0.0.1:5985` only. For multi-user or remote access, place it behind a reverse proxy (Nginx/Apache), enable HTTPS, and configure proper secrets (`secret_key`, `agent_registration_secret`, `SECURITY_PASSWORD_SALT`, etc.).
- Rotate the `admin` password frequently and disable default credentials if the instance will be shared.
- The stack is intended for lab / internal networks. Harden PostgreSQL and Redis if you bind them to non-localhost interfaces.

---

## Updating Faraday
1. Pull the latest repo changes.
2. Update the Docker image: `docker pull faradaysec/faraday:latest`
3. Restart the stack: `docker compose down && docker compose up -d`
4. Re-run the password reset snippet if needed (new images sometimes include schema changes).

Keep an eye on [Faraday release notes](https://docs.faradaysec.com/) for upstream migrations.

---

## Contributing & Support
- Report bugs or open discussions via GitHub Issues on this repository.
- Pull requests are welcome—please describe the environment and steps used for testing.
- Feel free to fork and adapt for other distributions; share improvements back with the community.

**Contact:** Pedro W. L. Soares de Souza (Mr.Blue)

---

## License
This repository, including the patches and scripts, is released under the [MIT License](LICENSE).
