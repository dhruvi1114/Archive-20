#!/usr/bin/env bash
#
# Nightly backup — Association Management Platform.
# Implements docs/backup-recovery.md §3 (Option A: pg_dump + uploads archive + checksums).
#
#   ./scripts/backup.sh              # real run
#   ./scripts/backup.sh --dry-run    # rehearse everything, write to a temp dir, keep nothing
#
# A silent backup failure is the classic way to discover you have no backups, so this
# script exits non-zero on ANY failure and prints a single machine-greppable line
# (`BACKUP_RESULT=...`) that a monitor can alert on (observability.md §6).
#
# Config (env or scripts/backup.env):
#   DATABASE_URL     required — read from backend/.env.<APP_ENV> when unset
#   BACKUP_DEST      where dumps land                 (default /var/backups/assoc)
#   UPLOADS_DIR      the storage root to archive      (default = STORAGE_PATH from backend env)
#   RETENTION_DAYS   how long to keep local copies    (default 7)
#   RCLONE_REMOTE    e.g. remote:assoc-backups        (unset = OFF-HOST COPY SKIPPED)
#   APP_ENV          which backend/.env.<APP_ENV> to read (default local)
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    -h|--help)
      sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

log()  { printf '[backup] %s\n' "$*"; }
warn() { printf '[backup] WARNING: %s\n' "$*" >&2; }
die()  { printf '[backup] ERROR: %s\n' "$*" >&2; echo "BACKUP_RESULT=FAIL"; exit 1; }

# ---------------------------------------------------------------- configuration

# Optional local overrides, never committed.
# shellcheck source=/dev/null
[[ -f "${SCRIPT_DIR}/backup.env" ]] && source "${SCRIPT_DIR}/backup.env"

APP_ENV="${APP_ENV:-local}"
BACKEND_ENV_FILE="${PROJECT_ROOT}/backend/.env.${APP_ENV}"

# Pull a KEY=value out of a backend env file without sourcing it (those files
# contain comments and values we must not evaluate).
read_backend_env() {
  local key="$1"
  [[ -f "$BACKEND_ENV_FILE" ]] || return 0
  sed -n "s/^${key}=\(.*\)$/\1/p" "$BACKEND_ENV_FILE" | tail -n 1 | sed 's/[[:space:]]*#.*$//' | tr -d '"'
}

DATABASE_URL="${DATABASE_URL:-$(read_backend_env DATABASE_URL)}"
UPLOADS_DIR="${UPLOADS_DIR:-$(read_backend_env STORAGE_PATH)}"
BACKUP_DEST="${BACKUP_DEST:-/var/backups/assoc}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
RCLONE_REMOTE="${RCLONE_REMOTE:-}"

[[ -n "${DATABASE_URL:-}" ]] || die "DATABASE_URL is not set and could not be read from ${BACKEND_ENV_FILE}"

TS="$(date +%F-%H%M)"

if [[ "$DRY_RUN" -eq 1 ]]; then
  DEST="$(mktemp -d "${TMPDIR:-/tmp}/assoc-backup-dryrun-XXXXXX")"
  log "DRY RUN — writing to ${DEST}, keeping nothing, no off-host copy, no retention delete."
  # shellcheck disable=SC2317
  cleanup() { rm -rf "$DEST"; }
  trap cleanup EXIT
else
  DEST="$BACKUP_DEST"
fi

DB_FILE="${DEST}/db-${TS}.dump"
UPLOADS_FILE="${DEST}/uploads-${TS}.tar.gz"
CHECKSUM_FILE="${DEST}/checksums-${TS}.txt"

# ------------------------------------------------------------------ preflight

command -v pg_dump >/dev/null 2>&1 || die "pg_dump not found on PATH"

# macOS ships shasum, Linux ships sha256sum. Use whichever exists.
if command -v sha256sum >/dev/null 2>&1; then
  SHA_CMD=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  SHA_CMD=(shasum -a 256)
else
  die "neither sha256sum nor shasum found — cannot checksum the backup"
fi

mkdir -p "$DEST" || die "cannot create backup destination ${DEST}"
[[ -w "$DEST" ]] || die "backup destination ${DEST} is not writable"

# One backup at a time. Two concurrent pg_dumps of the same DB is a bad night.
LOCK_DIR="${DEST}/.backup.lock"
if [[ "$DRY_RUN" -eq 0 ]]; then
  mkdir "$LOCK_DIR" 2>/dev/null || die "another backup is already running (${LOCK_DIR} exists)"
  # shellcheck disable=SC2317
  release_lock() { rmdir "$LOCK_DIR" 2>/dev/null || true; }
  trap release_lock EXIT
fi

log "APP_ENV=${APP_ENV}"
log "destination: ${DEST}"
log "database:    $(printf '%s' "$DATABASE_URL" | sed -E 's#(://[^:]+:)[^@]+@#\1***@#')"
log "uploads:     ${UPLOADS_DIR:-<not configured>}"

# --------------------------------------------------------------- 1. database

log "1/5 pg_dump (custom format)…"
pg_dump -Fc --no-owner --no-privileges -d "$DATABASE_URL" -f "$DB_FILE" \
  || die "pg_dump failed — NO BACKUP WAS TAKEN"

[[ -s "$DB_FILE" ]] || die "pg_dump produced an empty file"

# A dump that pg_restore cannot list is not a backup.
if command -v pg_restore >/dev/null 2>&1; then
  pg_restore --list "$DB_FILE" >/dev/null 2>&1 \
    || die "pg_restore --list rejected the dump — it is not restorable"
  log "     dump verified with pg_restore --list"
fi

log "     $(du -h "$DB_FILE" | cut -f1) → $(basename "$DB_FILE")"

# ---------------------------------------------------------------- 2. uploads

log "2/5 uploads archive…"
if [[ -n "${UPLOADS_DIR:-}" && -d "$UPLOADS_DIR" ]]; then
  tar -czf "$UPLOADS_FILE" -C "$(dirname "$UPLOADS_DIR")" "$(basename "$UPLOADS_DIR")" \
    || die "tar of ${UPLOADS_DIR} failed"
  log "     $(du -h "$UPLOADS_FILE" | cut -f1) → $(basename "$UPLOADS_FILE")"
else
  # KYC documents live here. Their absence in production is an incident, not a shrug.
  warn "uploads directory '${UPLOADS_DIR:-<unset>}' does not exist — archiving an empty placeholder"
  tar -czf "$UPLOADS_FILE" -T /dev/null || die "could not write placeholder uploads archive"
fi

# -------------------------------------------------------------- 3. checksums

log "3/5 checksums…"
( cd "$DEST" && "${SHA_CMD[@]}" "$(basename "$DB_FILE")" "$(basename "$UPLOADS_FILE")" > "$(basename "$CHECKSUM_FILE")" ) \
  || die "checksum generation failed"
( cd "$DEST" && "${SHA_CMD[@]}" -c "$(basename "$CHECKSUM_FILE")" >/dev/null ) \
  || die "checksum verification failed immediately after writing — the disk is lying to you"
log "     verified: $(basename "$CHECKSUM_FILE")"

# ----------------------------------------------------------- 4. off-host copy

log "4/5 off-host copy…"
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "     skipped (dry run)"
elif [[ -z "$RCLONE_REMOTE" ]]; then
  # docs/backup-recovery.md §3: "a local-only copy is not a backup".
  warn "RCLONE_REMOTE is not set — backup is LOCAL ONLY. This is not yet a real backup."
elif ! command -v rclone >/dev/null 2>&1; then
  warn "rclone not installed — backup is LOCAL ONLY."
else
  rclone copy "$DB_FILE" "${RCLONE_REMOTE}/${TS}/" || die "rclone copy of the database dump failed"
  rclone copy "$UPLOADS_FILE" "${RCLONE_REMOTE}/${TS}/" || die "rclone copy of the uploads archive failed"
  rclone copy "$CHECKSUM_FILE" "${RCLONE_REMOTE}/${TS}/" || die "rclone copy of the checksums failed"
  log "     copied to ${RCLONE_REMOTE}/${TS}/"
fi

# ------------------------------------------------------------- 5. retention

log "5/5 retention (${RETENTION_DAYS} days)…"
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "     skipped (dry run)"
else
  # Deliberately narrow -name patterns: a bare `find "$DEST" -mtime +7 -delete`
  # would happily delete anything else that shares the directory.
  deleted=0
  while IFS= read -r old; do
    rm -f "$old" && deleted=$((deleted + 1))
  done < <(find "$DEST" -maxdepth 1 -type f \
      \( -name 'db-*.dump' -o -name 'uploads-*.tar.gz' -o -name 'checksums-*.txt' \) \
      -mtime "+${RETENTION_DAYS}")
  log "     removed ${deleted} expired file(s)"
fi

log "done in ${SECONDS}s"
echo "BACKUP_RESULT=OK ts=${TS} db=$(basename "$DB_FILE") uploads=$(basename "$UPLOADS_FILE")"
