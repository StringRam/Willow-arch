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

_run_capture() { # _run_capture tui|quiet LEVEL -- cmd args...
  local mode="${1:-tui}"
  local level="${2:-CMD}"
  shift 2 || true
  [[ "${1:-}" == "--" ]] && shift || true

  local -a cmd=("$@")
  local -a runner=()
  if command -v stdbuf >/dev/null 2>&1; then
    runner=(stdbuf -oL -eL)
  fi

  [[ "$mode" == "tui" ]] && _refresh
  declare -F log_command_start >/dev/null && log_command_start "$level" -- "${cmd[@]}"

  set +e
  "${runner[@]}" "${cmd[@]}" 2>&1 | sanitize_stream | while IFS= read -r line || [[ -n "$line" ]]; do
    case "$mode" in
      tui)
        _log_add "$level" "$line"
        _refresh
        ;;
      quiet)
        declare -F log_write >/dev/null && log_write "$level" "$line"
        ;;
    esac
  done
  local rc=${PIPESTATUS[0]}
  set -e

  declare -F log_command_end >/dev/null && log_command_end "$level" "$rc"

  if [[ "$mode" == "tui" ]]; then
    _render
  elif (( rc != 0 )); then
    _err "Command failed with status $rc: $(_shell_quote_command "${cmd[@]}")"
  fi

  return "$rc"
}

run_cmd() { # run_cmd LEVEL -- cmd args...
  _run_capture tui "$@"
}

run_quiet() { # run_quiet LEVEL -- cmd args...
  _run_capture quiet "$@"
}

run_with_input() { # run_with_input LEVEL INPUT -- cmd args...
  local level="${1:-CMD}"
  local input="${2:-}"
  shift 2 || true
  [[ "${1:-}" == "--" ]] && shift || true

  local -a cmd=("$@")
  local -a runner=()
  if command -v stdbuf >/dev/null 2>&1; then
    runner=(stdbuf -oL -eL)
  fi

  declare -F log_command_start >/dev/null && log_command_start "$level" -- "${cmd[@]}"
  declare -F log_write >/dev/null && log_write "$level" "stdin supplied: <redacted>"

  set +e
  printf '%s' "$input" | "${runner[@]}" "${cmd[@]}" 2>&1 | sanitize_stream | while IFS= read -r line || [[ -n "$line" ]]; do
    declare -F log_write >/dev/null && log_write "$level" "$line"
  done
  local rc=${PIPESTATUS[1]}
  set -e

  declare -F log_command_end >/dev/null && log_command_end "$level" "$rc"

  if (( rc != 0 )); then
    _err "Command failed with status $rc: $(_shell_quote_command "${cmd[@]}")"
  fi

  return "$rc"
}
