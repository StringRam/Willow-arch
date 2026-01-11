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
  local level="${1:-RAW}"; shift || true
  [[ "${1:-}" == "--" ]] && shift || true

  _refresh

  # Si stdbuf no existe, ejecuta directo
  local -a runner=()
  if command -v stdbuf >/dev/null 2>&1; then
    runner=(stdbuf -oL -eL)
  fi

  "${runner[@]}" "$@" 2>&1 | sanitize_stream | while IFS= read -r line || [[ -n "$line" ]]; do
    # NO saltear líneas vacías: son parte del output
    _log_add "$level" "$line"
    _refresh
  done

  local rc=${PIPESTATUS[0]}
  _render
  return "$rc"
}


