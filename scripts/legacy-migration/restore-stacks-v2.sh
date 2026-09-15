#!/usr/bin/env bash
#
# restore-stacks-v2.sh — Automated restore of stacks archived by
# backup-stacks-v2.sh, including services.conf "builtin" restores.
#
# For each archive:
#   - Extracts it into STACKS_DIR
#   - Looks up the stack in services.conf (copied alongside the archives
#     by backup-stacks-v2.sh)
#   - If method=builtin: brings up the full stack, waits for the target
#     container, copies the app-backup/ artifact back in, and runs the
#     recorded restore_cmd
#   - Otherwise (generic / not listed): brings up just the DB service
#     first, waits, restores the auto-detected postgres/mysql/redis dump,
#     then brings up the full stack — same as v1
#
# Usage:
#   ./restore-stacks-v2.sh
#
# Configure the variables below before running.

set -uo pipefail

INCOMING_DIR="/opt/stacks-incoming"      # where the .tar.gz archives (and services.conf) were copied to
STACKS_DIR="/opt/stacks"                  # where stacks should live on the new host
MANIFEST_CONF="${INCOMING_DIR}/services.conf"   # backup-stacks-v2.sh copies this alongside the archives
LOG_FILE="${INCOMING_DIR}/restore.log"

mkdir -p "$STACKS_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Same lookup as backup-stacks-v2.sh — reads the same file format.
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

wait_for_container_healthy() {
  local cname="$1" retries="${2:-30}"
  for _ in $(seq 1 "$retries"); do
    status=$(docker inspect --format '{{.State.Status}}' "$cname" 2>/dev/null)
    if [ "$status" = "running" ]; then
      sleep 3   # give the process inside a moment after the container reports running
      return 0
    fi
    sleep 2
  done
  return 1
}

# --- generic (auto-detected DB) restore, same as v1 ---
restore_database_generic() {
  local cname="$1" engine="$2" dump_dir="$3"
  case "$engine" in
    postgres)
      [ -f "${dump_dir}/dump.sql" ] || return 1
      docker exec -i "$cname" psql -U "${POSTGRES_USER:-postgres}" < "${dump_dir}/dump.sql" >>"$LOG_FILE" 2>&1
      ;;
    mysql)
      [ -f "${dump_dir}/dump.sql" ] || return 1
      docker exec -i "$cname" sh -c 'exec mysql -u root -p"${MYSQL_ROOT_PASSWORD}"' < "${dump_dir}/dump.sql" >>"$LOG_FILE" 2>&1
      ;;
    redis)
      [ -f "${dump_dir}/dump.rdb" ] || return 1
      docker cp "${dump_dir}/dump.rdb" "${cname}:/data/dump.rdb" >>"$LOG_FILE" 2>&1
      docker restart "$cname" >>"$LOG_FILE" 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

detect_db_service_name() {
  local compose_file="$1"
  grep -E '^\s*image:\s*.*(postgres|mysql|mariadb|redis)' -B 20 "$compose_file" \
    | grep -E '^\s{2}[a-zA-Z0-9_-]+:\s*$' | tail -1 | sed 's/[: ]//g'
}

# --- builtin (manifest-driven) restore ---
run_builtin_restore() {
  local cname="$1" artifact_path="$2" restore_cmd="$3" app_backup_dir="$4"

  if [ ! -e "$app_backup_dir" ] || [ -z "$(ls -A "$app_backup_dir" 2>/dev/null)" ]; then
    log "WARNING: no app-backup artifact found at ${app_backup_dir} — nothing to restore"
    return 1
  fi

  log "Copying artifact from ${app_backup_dir} into ${cname}:${artifact_path}"
  if ! docker cp "${app_backup_dir}/." "${cname}:${artifact_path}" >>"$LOG_FILE" 2>&1; then
    log "WARNING: docker cp into ${cname} failed"
    return 1
  fi

  if [ -z "$restore_cmd" ]; then
    log "WARNING: no restore_cmd recorded in services.conf for this stack — artifact copied in, but you must run the restore command manually"
    return 1
  fi

  log "Running restore command in ${cname}: ${restore_cmd}"
  docker exec "$cname" sh -c "$restore_cmd" >>"$LOG_FILE" 2>&1
}

total=0
ok=0
manual_followup=0

for archive in "$INCOMING_DIR"/*.tar.gz; do
  [ -f "$archive" ] || continue
  stack_name=$(basename "$archive" .tar.gz)
  total=$((total+1))
  log "=== Restoring ${stack_name} ==="

  tar -xzf "$archive" -C "$STACKS_DIR" 2>>"$LOG_FILE"
  stack_path="${STACKS_DIR}/${stack_name}/"
  compose_file="${stack_path}docker-compose.yml"

  if [ ! -f "$compose_file" ]; then
    log "WARNING: no compose file found for ${stack_name}, skipping"
    continue
  fi

  IFS='|' read -r m_container m_method m_backup_cmd m_artifact m_restore <<< "$(lookup_manifest "$stack_name")"

  if [ "$m_method" = "builtin" ]; then
    log "Bringing up full stack ${stack_name} (builtin restore needs it running)..."
    (cd "$stack_path" && docker compose up -d) >>"$LOG_FILE" 2>&1

    cname="$m_container"
    [ -z "$cname" ] && cname=$(first_running_container "$stack_path")

    if [ -z "$cname" ] || ! wait_for_container_healthy "$cname"; then
      log "WARNING: container for ${stack_name} never became ready — restore manually from ${stack_path}app-backup"
      manual_followup=$((manual_followup+1))
    elif run_builtin_restore "$cname" "$m_artifact" "$m_restore" "${stack_path}app-backup"; then
      log "Builtin restore succeeded for ${stack_name}"
      ok=$((ok+1))
    else
      log "WARNING: builtin restore incomplete for ${stack_name} — see log above, may need manual follow-up"
      manual_followup=$((manual_followup+1))
    fi

  else
    # generic path — same behavior as v1
    dump_dir="${stack_path}db-backup"
    if [ -d "$dump_dir" ]; then
      db_service=$(detect_db_service_name "$compose_file")
      if [ -n "$db_service" ]; then
        log "Bringing up DB service '${db_service}' for ${stack_name}..."
        (cd "$stack_path" && docker compose up -d "$db_service") >>"$LOG_FILE" 2>&1

        db_cname=$(cd "$stack_path" && docker compose ps -q "$db_service" | xargs -I{} docker inspect --format '{{.Name}}' {} 2>/dev/null | sed 's#^/##')

        if [ -n "$db_cname" ] && wait_for_container_healthy "$db_cname"; then
          engine="postgres"
          [ -f "${dump_dir}/dump.rdb" ] && engine="redis"
          grep -qi mysql "$compose_file" && engine="mysql"

          log "Restoring ${engine} dump into ${db_cname}..."
          if restore_database_generic "$db_cname" "$engine" "$dump_dir"; then
            log "DB restore succeeded for ${stack_name}"
          else
            log "WARNING: DB restore failed for ${stack_name} — restore manually from ${dump_dir}"
            manual_followup=$((manual_followup+1))
          fi
        else
          log "WARNING: DB container for ${stack_name} never became ready — restore manually"
          manual_followup=$((manual_followup+1))
        fi
      else
        log "WARNING: could not auto-detect DB service name for ${stack_name} — restore ${dump_dir} manually"
        manual_followup=$((manual_followup+1))
      fi
    fi

    log "Bringing up full stack ${stack_name}..."
    if (cd "$stack_path" && docker compose up -d) >>"$LOG_FILE" 2>&1; then
      ok=$((ok+1))
      log "${stack_name} is up."
    else
      log "WARNING: ${stack_name} failed to start — check ${LOG_FILE}"
      manual_followup=$((manual_followup+1))
    fi
  fi

  log "=== Done with ${stack_name} ==="
  echo "" >> "$LOG_FILE"
done

log "Restore complete: ${ok}/${total} stacks brought up successfully."
log "${manual_followup} stack(s) need manual follow-up — review WARNING lines in ${LOG_FILE}."