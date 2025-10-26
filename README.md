**Project Lead:** Pedro W. L. Soares de Souza (a.k.a. Mr.Blue)  
**Implementation Support:** Codex AI assistant

# Faraday for Kali Linux — Upload-Ready Edition

A reproducible Docker Compose bundle for **Faraday Community Edition** with the fixes we needed in production:
- `pbkdf2_sha512` login policy with a working admin password reset.
- Celery worker enabled out of the box (no more stuck uploads).
- Persistent `uploaded_reports` volume so the UI stops looping.
- Automatic downgrade of `bcrypt` to `<4` to avoid Passlib crashes.

All files are sanitised — replace the placeholder secrets in `server.ini` before going online.

---

## Tested Environment
- Kali Linux Rolling 2024.x
- Docker Engine ≥ 24.x
- Docker Compose Plugin ≥ 2.x
- Faraday image: `faradaysec/faraday:latest` (Community)

Should also run on any recent Debian/Ubuntu base with Docker installed.

---

## Repository Layout
| File | Purpose |
| --- | --- |
| `docker-compose.yaml` | Runs PostgreSQL, Redis, Faraday web, and the Celery worker. Exposes the security env vars and mounts config files plus the uploads volume. |
| `server.ini` | Minimal Faraday configuration. Contains placeholder secrets — change them! |
| `app.py` | Patched Faraday server module (mirrors the image but keeps the login fixes that accept username or email). |
| `install.sh` | One-click installer: verifies prerequisites, brings up the stack, waits for containers, downgrades `bcrypt`, resets the admin password. |
| `LICENSE` | MIT license for this repo. |

---

## Quick Start
```bash
git clone https://github.com/oupsz/faraday-for-kali-easy-install.git
cd faraday-for-kali-easy-install

chmod +x install.sh
./install.sh
```

When the script finishes:
- Web UI: `http://127.0.0.1:5985/_ui/`
- Credentials: `admin` / `NovaSenha123!`

> **Remember:** edit `server.ini` afterwards and replace every `CHANGE_ME_*` value with unique secrets.

---

## Manual Deployment
1. Install dependencies (example for Kali/Debian):
   ```bash
   sudo apt update
   sudo apt install docker.io docker-compose-plugin python3-psycopg2 -y
   sudo systemctl enable --now docker
   ```
2. Clone and start:
   ```bash
   git clone https://github.com/oupsz/faraday-for-kali-easy-install.git
   cd faraday-for-kali-easy-install
   docker compose up -d
   ```
3. Wait for containers:
   ```bash
   docker ps --format '{{.Names}} {{.Status}}'
   # faraday-db (healthy), faraday-redis (healthy), faraday-web (Up), faraday-worker (Up)
   ```
4. Pin the bcrypt version inside both Faraday containers:
   ```bash
   docker compose exec faraday pip install 'bcrypt<4'
   docker compose exec worker  pip install 'bcrypt<4'
   ```
5. Reset the admin password to a known `pbkdf2_sha512` hash:
   ```bash
   docker compose exec faraday python - <<'PY'
   import os, psycopg2
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
   cur.execute("UPDATE faraday_user SET password=%s, active=true WHERE username=%s",
               (new_hash, "admin"))
   conn.commit()
   cur.close()
   conn.close()
   print("Admin password reset with pbkdf2_sha512.")
   PY
   ```
6. Log in at `http://127.0.0.1:5985/_ui/` with the credentials above.

---

## After the First Login
1. Change all placeholder secrets inside `server.ini`.
2. Use the UI to change the `admin` password.
3. Test uploads:
   ```bash
   curl -s -c cookies.txt 'http://127.0.0.1:5985/_api/login' >/dev/null
   curl -s -b cookies.txt -X POST \
     -F 'csrf_token=<from /_api/session>' \
     -F 'file=@example_report.xml' \
     http://127.0.0.1:5985/_api/v3/ws/<workspace>/upload_report
   ```
4. Confirm `faraday-worker` logs show the Celery task processing.

---

## Data & Backups
- Database volume: `faradaybackup_dbdata`
- File storage: `faradaybackup_faraday-storage`
- Upload cache: `faradaybackup_faraday-uploads`

Create a tarball backup (example for the DB volume):
```bash
docker run --rm -v faradaybackup_dbdata:/volume -v "$(pwd)":/backup alpine \
  tar czf /backup/dbdata.tgz -C /volume .
```
Repeat for the other two volumes.

Restore by stopping the stack, removing the target volume, and extracting the archive into a new volume or bind mount.

---

## Troubleshooting
| Symptom | Explanation | Fix |
| --- | --- | --- |
| `passlib.exc.UnknownHashError` during login | Faraday fell back to the broken bcrypt backend | Re-run `pip install 'bcrypt<4'` inside both `faraday` and `worker`; then reset the admin password. |
| Upload hangs in UI | Celery worker missing or uploads dir lost | Ensure `worker` service is running and the `faraday-uploads` volume is mounted. |
| Upload succeeds but nothing appears | The report contained no vulnerabilities | Check `docker compose exec faraday ... global_commands` for `command` entries; examine worker logs for plugin output. |
| Login rejects email | Confirm `SECURITY_USER_IDENTITY_ATTRIBUTES=email,username` is still set and `app.py` is mounted. |

Logs live in:
- Web: `docker compose logs faraday`
- Worker: `docker compose logs worker`
- DB / Redis: `docker compose logs db|redis`

---

## Security Notes
- Only binds to `127.0.0.1:5985`. Use a reverse proxy + HTTPS for remote access.
- Rotate secrets (`server.ini`) and the default password before sharing the instance.
- PostgreSQL/Redis are internal by default; expose them only if you know the risks.

---

Enjoy, and contributions are welcome! (Pull requests, issues, docs improvements — all help the community version grow.)

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
