#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE="docker compose"
ADMIN_PASSWORD="NovaSenha123!"
CONTAINERS=(faraday-db faraday-redis faraday-web)
HEALTH_TIMEOUT=120

# --- helper functions -------------------------------------------------------
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

print_step() {
  echo "[+] $1"
}

print_warn() {
  echo "[!] $1" >&2
}

wait_for_health() {
  local name=$1
  local elapsed=0
  local status
  while true; do
    status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name" 2>/dev/null || echo "unknown")
    case "$status" in
      healthy|running)
        echo "  - $name is $status"
        return 0
        ;;
      restarting)
        print_warn "$name is restarting..."
        ;;
      unknown)
        print_warn "waiting for $name to appear..."
        ;;
      *)
        echo "  - $name status: $status"
        ;;
    esac
    sleep 3
    elapsed=$(( elapsed + 3 ))
    if (( elapsed >= HEALTH_TIMEOUT )); then
      print_warn "$name did not become healthy within ${HEALTH_TIMEOUT}s"
      return 1
    fi
  done
}

reset_admin_password() {
  $COMPOSE -f "$PROJECT_DIR/docker-compose.yaml" exec -T faraday python - <<PY
import os
import psycopg2
from passlib.hash import pbkdf2_sha512

password = "${ADMIN_PASSWORD}"
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
}

# --- checks -----------------------------------------------------------------
print_step "Checking prerequisites"
if ! command_exists docker; then
  print_warn "Docker is not installed. See README for installation steps."
  exit 1
fi
if ! $COMPOSE version >/dev/null 2>&1; then
  print_warn "Docker Compose plugin not available. Install 'docker-compose-plugin'."
  exit 1
fi

print_step "Ensuring Docker volumes exist"
for volume in config_dbdata config_faraday-storage; do
  if ! docker volume inspect "$volume" >/dev/null 2>&1; then
    docker volume create "$volume" >/dev/null
    echo "  - created volume $volume"
  else
    echo "  - found volume $volume"
  fi
done

print_step "Starting Faraday stack"
(cd "$PROJECT_DIR" && $COMPOSE up -d)

print_step "Waiting for containers"
for container in "${CONTAINERS[@]}"; do
  wait_for_health "$container" || true
done

print_step "Resetting admin password"
reset_admin_password || print_warn "Could not reset admin password automatically"

print_step "All done"
echo "  URL: http://127.0.0.1:5985/_ui/"
echo "  Credentials: admin / ${ADMIN_PASSWORD}"
