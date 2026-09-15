#!/usr/bin/env bash
#
# backup-stacks.sh (v2) — Automated backup of docker-compose stacks under STACKS_DIR.
#
# For each stack:
#   - If listed in services.conf with method=builtin: runs the app's own
#     backup command inside the container and copies the resulting
#     artifact out (e.g. gitea dump, paperless document_exporter, HA
#     snapshot, etc.)
#   - Otherwise (generic / not listed): auto-detects a DB container by
#     image name and runs the appropriate dump (postgres/mysql/redis)
# Then, regardless of method:
#   - Stops the stack
#   - Archives the whole stack directory (compose file, .env, bind
#     mounts, backup artifact / db dump)
#   - Restarts the stack
# At the end, rsyncs the full backup set to a remote host.
#
# Usage:
#   ./backup-stacks.sh
#
# Configure the variables below before running.

set -uo pipefail  # not using -e — one stack failing shouldn't kill the whole run

STACKS_DIR="/opt/stacks"
BACKUP_DIR="/mnt/backup-target/vmc01-migration"
MANIFEST_CONF="$(dirname "$0")/services.conf"   # expects services.conf next to this script
LOG_FILE="${BACKUP_DIR}/backup.log"
SUMMARY_FILE="${BACKUP_DIR}/manifest.csv"

REMOTE_HOST="user@your-backup-host"                 # <-- only used if DO_REMOTE_SYNC=true
REMOTE_PATH="/mnt/backup-storage/vmc01-migration"   # <-- only used if DO_REMOTE_SYNC=true
DO_REMOTE_SYNC=false   # off by default — backups stay local; copy to NAS/USB manually (see note at end of run)

mkdir -p "$BACKUP_DIR"
: > "$SUMMARY_FILE"
echo "stack,method,detail,backup_status,archive_status" >> "$SUMMARY_FILE"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Look up a stack's override line in services.conf, if any.
# Prints: container|method|backup_cmd|artifact_path|restore_cmd
lookup_manifest() {
  local stack_name="$1"
  [ -f "$MANIFEST_CONF" ] || { echo "|generic|||"; return; }

  local line
  line=$(grep -v '^\s*#' "$MANIFEST_CONF" | grep -v '^\s*$' | awk -F'|' -v s="$stack_name" '$1 == s {print; exit}')

  if [ -z "$line" ]; then
    echo "|generic|||"
    return
  fi

  local container method backup_cmd artifact_path restore_cmd
  IFS='|' read -r _ container method backup_cmd artifact_path restore_cmd <<< "$line"
  echo "${container}|${method:-generic}|${backup_cmd}|${artifact_path}|${restore_cmd}"
}

first_running_container() {
  local stack_dir="$1"
  docker compose -f "${stack_dir}docker-compose.yml" ps -q 2>/dev/null | head -n1 \
    | xargs -r docker inspect --format '{{.Name}}' 2>/dev/null | sed 's#^/##'
}

# --- generic (fallback) DB detection, same as v1 ---
detect_db_container() {
  local stack_dir="$1"
  local containers
  containers=$(docker compose -f "${stack_dir}docker-compose.yml" ps -q 2>/dev/null)

  for cid in $containers; do
    local image cname
    image=$(docker inspect --format '{{.Config.Image}}' "$cid" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    cname=$(docker inspect --format '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##')
    case "$image" in
      *postgres*)        echo "${cname}|postgres"; return 0 ;;
      *mysql*|*mariadb*) echo "${cname}|mysql";    return 0 ;;
      *redis*)           echo "${cname}|redis";    return 0 ;;
    esac
  done
  echo "|"
  return 1
}

dump_database_generic() {
  local cname="$1" engine="$2" out_dir="$3"
  mkdir -p "$out_dir"
  case "$engine" in
    postgres) docker exec "$cname" sh -c 'pg_dumpall -U "${POSTGRES_USER:-postgres}"' > "${out_dir}/dump.sql" 2>>"$LOG_FILE" ;;
    mysql)    docker exec "$cname" sh -c 'exec mysqldump -u root -p"${MYSQL_ROOT_PASSWORD}" --all-databases' > "${out_dir}/dump.sql" 2>>"$LOG_FILE" ;;
    redis)    docker exec "$cname" redis-cli SAVE >>"$LOG_FILE" 2>&1
              docker cp "${cname}:/data/dump.rdb" "${out_dir}/dump.rdb" >>"$LOG_FILE" 2>&1 ;;
    *)        return 1 ;;
  esac
}

# --- builtin (manifest-driven) backup ---
run_builtin_backup() {
  local cname="$1" backup_cmd="$2" artifact_path="$3" out_dir="$4"
  mkdir -p "$out_dir"

  log "Running builtin backup command in ${cname}: ${backup_cmd}"
  if ! docker exec "$cname" sh -c "$backup_cmd" >>"$LOG_FILE" 2>&1; then
    return 1
  fi

  log "Copying artifact ${artifact_path} out of ${cname}..."
  docker cp "${cname}:${artifact_path}" "${out_dir}/" >>"$LOG_FILE" 2>&1
}

total=0
ok=0

for stack_path in "$STACKS_DIR"/*/; do
  [ -f "${stack_path}docker-compose.yml" ] || continue
  stack_name=$(basename "$stack_path")
  total=$((total+1))
  log "=== Processing ${stack_name} ==="

  IFS='|' read -r m_container m_method m_backup_cmd m_artifact m_restore <<< "$(lookup_manifest "$stack_name")"

  backup_status="none"
  detail="$m_method"

  if [ "$m_method" = "builtin" ]; then
    cname="$m_container"
    [ -z "$cname" ] && cname=$(first_running_container "$stack_path")

    if [ -z "$cname" ]; then
      log "WARNING: no running container found for builtin backup of ${stack_name}"
      backup_status="FAILED"
    elif run_builtin_backup "$cname" "$m_backup_cmd" "$m_artifact" "${stack_path}app-backup"; then
      backup_status="ok"
      log "Builtin backup succeeded for ${stack_name}"
    else
      backup_status="FAILED"
      log "WARNING: builtin backup failed for ${stack_name} — check ${LOG_FILE}"
    fi
  else
    # generic path: auto-detect DB
    db_info=$(detect_db_container "$stack_path")
    db_cname="${db_info%%|*}"
    db_engine="${db_info##*|}"
    detail="generic:${db_engine:-no-db}"

    if [ -n "$db_cname" ] && [ -n "$db_engine" ]; then
      log "Detected ${db_engine} database in ${db_cname}, dumping..."
      if dump_database_generic "$db_cname" "$db_engine" "${stack_path}db-backup"; then
        backup_status="ok"
      else
        backup_status="FAILED"
        log "WARNING: generic DB dump failed for ${stack_name}"
      fi
    fi
  fi

  log "Stopping ${stack_name}..."
  (cd "$stack_path" && docker compose down) >>"$LOG_FILE" 2>&1

  archive_status="ok"
  log "Archiving ${stack_name}..."
  if ! tar -czf "${BACKUP_DIR}/${stack_name}.tar.gz" -C "$STACKS_DIR" "$stack_name" 2>>"$LOG_FILE"; then
    archive_status="FAILED"
    log "WARNING: archive failed for ${stack_name}"
  fi

  log "Restarting ${stack_name}..."
  (cd "$stack_path" && docker compose up -d) >>"$LOG_FILE" 2>&1

  echo "${stack_name},${m_method:-generic},${detail},${backup_status},${archive_status}" >> "$SUMMARY_FILE"
  [ "$archive_status" = "ok" ] && ok=$((ok+1))

  log "=== Done with ${stack_name} ==="
  echo "" >> "$LOG_FILE"
done

log "Backup complete: ${ok}/${total} stacks archived successfully."

# --- Fix ownership/permissions so a non-root copy (NAS/USB) actually works ---
# This script typically needs to run under sudo (docker compose down/up), which
# means everything it creates defaults to root:root. Rather than opening the
# permissions to "everyone can read" (these files can contain DB credentials
# in the dump.sql/app-backup files), hand ownership back to whoever invoked
# sudo, so only that user (the same one who'll plug in the USB/mount the NAS)
# can access them.
if [ -n "${SUDO_USER:-}" ]; then
  log "Fixing ownership: chown -R ${SUDO_USER} ${BACKUP_DIR} (so you can copy these without sudo)"
  chown -R "${SUDO_USER}:${SUDO_USER}" "$BACKUP_DIR" 2>>"$LOG_FILE" \
    || log "WARNING: chown to ${SUDO_USER} failed — you may need 'sudo chown -R \$(whoami) ${BACKUP_DIR}' manually"
  chmod -R u+rwX,go-rwx "$BACKUP_DIR" 2>>"$LOG_FILE"
else
  log "NOTE: SUDO_USER not set (script wasn't run via sudo, or was run directly as root)."
  log "If you can't copy ${BACKUP_DIR} as your normal user afterward, run:"
  log "    sudo chown -R \$(whoami):\$(whoami) ${BACKUP_DIR}"
fi
log "Summary: ${SUMMARY_FILE}  (check for method=generic:no-db AND backup_status=none — those are services you haven't audited yet)"

if [ "$DO_REMOTE_SYNC" = true ]; then
  log "Syncing backups to ${REMOTE_HOST}:${REMOTE_PATH} ..."
  ssh "$REMOTE_HOST" "mkdir -p ${REMOTE_PATH}"
  if rsync -avz --progress "$BACKUP_DIR"/ "${REMOTE_HOST}:${REMOTE_PATH}/" >>"$LOG_FILE" 2>&1; then
    log "Remote sync succeeded."
  else
    log "WARNING: remote sync failed — backups remain local at ${BACKUP_DIR}"
  fi
else
  log "Remote sync disabled (DO_REMOTE_SYNC=false)."
  log "All backups are sitting locally at: ${BACKUP_DIR}"
  log "Copy this directory to your NAS or a USB drive before wiping this host, e.g.:"
  log "    rsync -avz --progress ${BACKUP_DIR}/ /path/to/nas-or-usb-mount/vmc01-migration/"
  log "    (or) cp -a ${BACKUP_DIR} /path/to/nas-or-usb-mount/vmc01-migration"
fi

log "Also copying services.conf into the backup set for reference during restore."
cp "$MANIFEST_CONF" "${BACKUP_DIR}/services.conf" 2>/dev/null

log "All done. Review ${SUMMARY_FILE} before wiping this host."