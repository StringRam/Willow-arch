#┌──────────────────────────────  ──────────────────────────────┐
#                         Persistent logging
#└──────────────────────────────  ──────────────────────────────┘

: "${LOG_ENABLED:=1}"
: "${LOG_DIR:=/tmp/willow-arch}"
: "${LOG_FILE:=}"
: "${LOG_TARGET_DIR:=/mnt/var/log/willow-arch}"

_log_timestamp() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

_shell_quote_command() {
  local quoted="" arg part

  for arg in "$@"; do
    printf -v part '%q' "$arg"
    quoted+="${quoted:+ }$part"
  done

  printf '%s' "$quoted"
}

log_init() {
  [[ "${LOG_ENABLED:-1}" -eq 1 ]] || return 0

  if [[ -z "${LOG_FILE:-}" ]]; then
    local ts
    ts="$(date '+%Y%m%d-%H%M%S')"
    LOG_FILE="${LOG_DIR%/}/willow-arch-${ts}.log"
  fi

  mkdir -p "$(dirname "$LOG_FILE")"
  : > "$LOG_FILE"
  chmod 600 "$LOG_FILE" 2>/dev/null || true

  log_write INFO "Willow-Arch installer log started."
  log_write INFO "Log file: $LOG_FILE"
  log_write INFO "Script directory: ${SCRIPT_DIR:-unknown}"
  log_write INFO "Bash: ${BASH_VERSION:-unknown}"
}

log_write() { # log_write LEVEL message...
  [[ "${LOG_ENABLED:-1}" -eq 1 ]] || return 0
  [[ -n "${LOG_FILE:-}" ]] || return 0

  local level="${1:-INFO}"
  shift || true

  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '[%s] [%-5s] %s\n' "$(_log_timestamp)" "$level" "$line" >> "$LOG_FILE"
  done <<< "$*"
}

log_command_start() { # log_command_start LEVEL -- cmd args...
  local level="${1:-CMD}"
  shift || true
  [[ "${1:-}" == "--" ]] && shift || true

  log_write "$level" "\$ $(_shell_quote_command "$@")"
}

log_command_end() { # log_command_end LEVEL STATUS
  local level="${1:-CMD}"
  local rc="${2:-unknown}"

  log_write "$level" "command exited with status $rc"
}

log_copy_to_target() {
  [[ "${LOG_ENABLED:-1}" -eq 1 ]] || return 0
  [[ -n "${LOG_FILE:-}" && -r "$LOG_FILE" ]] || return 0
  [[ -d /mnt/var/log ]] || return 0

  local target_dir="${LOG_TARGET_DIR:-/mnt/var/log/willow-arch}"
  local target_file="$target_dir/$(basename "$LOG_FILE")"

  mkdir -p "$target_dir" 2>/dev/null || return 0
  cp -f "$LOG_FILE" "$target_file" 2>/dev/null || return 0
  chmod 600 "$target_file" 2>/dev/null || true
  log_write INFO "Copied installer log to target system: $target_file"
}
