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
  tr -d '\r' | sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'
}

run_cmd() { # run_cmd LEVEL "Label" -- cmd args...
  local level="$1"; shift
  local label="$1"; shift
  [[ "${1:-}" == "--" ]] && shift || true

  tui_refresh_throttled

  # stdbuf hace line-buffering para ver output en vivo
  # si no existiera, podés quitar "stdbuf -oL -eL"
  stdbuf -oL -eL "$@" 2>&1 | sanitize_stream | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    log_add "$level" "$line"
    tui_refresh_throttled
  done

  local rc=${PIPESTATUS[0]}
  if (( rc == 0 )); then
    info_print "✓ $label"
  else
    error_print "✗ $label (exit $rc)"
  fi
  render_content
  return "$rc"
}

