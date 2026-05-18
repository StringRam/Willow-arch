#┌──────────────────────────────  ──────────────────────────────┐
#                           CMD output stuff
#└──────────────────────────────  ──────────────────────────────┘

: "${RUN_TUI:=1}"

_log_add() { # fallback si no hay TUI
  if declare -F log_add >/dev/null; then log_add "$@"
  else printf '[%s] %s\n' "$1" "${*:2}" >&2
  fi
}
_info() { declare -F info_print >/dev/null && info_print "$@" || printf '%s\n' "$*" >&2; }
_err()  { declare -F error_print >/dev/null && error_print "$@" || printf '%s\n' "$*" >&2; }
_refresh(){ declare -F tui_refresh_throttled >/dev/null && tui_refresh_throttled || true; }
_render(){ declare -F render_content >/dev/null && render_content || true; }

sanitize_stream() {
  tr '\r' '\n' | sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'
}

run_cmd() { # run_cmd LEVEL -- cmd args...
  local level="${1:-RAW}"
  shift || true
  [[ "${1:-}" == "--" ]] && shift || true

  _refresh

  declare -F log_command_start >/dev/null && log_command_start "$level" -- "$@"

  local -a runner=()
  if command -v stdbuf >/dev/null 2>&1; then
    runner=(stdbuf -oL -eL)
  fi

  set +e
  "${runner[@]}" "$@" 2>&1 | sanitize_stream | while IFS= read -r line || [[ -n "$line" ]]; do
    _log_add "$level" "$line"
    _refresh
  done
  local rc=${PIPESTATUS[0]}
  set -e

  declare -F log_command_end >/dev/null && log_command_end "$level" "$rc"

  _render
  return "$rc"
}

run_quiet() { # run_quiet LEVEL -- cmd args...
  local level="${1:-CMD}"
  shift || true
  [[ "${1:-}" == "--" ]] && shift || true

  declare -F log_command_start >/dev/null && log_command_start "$level" -- "$@"

  local -a runner=()
  if command -v stdbuf >/dev/null 2>&1; then
    runner=(stdbuf -oL -eL)
  fi

  set +e
  "${runner[@]}" "$@" 2>&1 | sanitize_stream | while IFS= read -r line || [[ -n "$line" ]]; do
    if declare -F log_write >/dev/null; then
      log_write "$level" "$line"
    fi
  done
  local rc=${PIPESTATUS[0]}
  set -e

  declare -F log_command_end >/dev/null && log_command_end "$level" "$rc"

  if (( rc != 0 )); then
    _err "Command failed with status $rc: $(_shell_quote_command "$@")"
  fi

  return "$rc"
}


