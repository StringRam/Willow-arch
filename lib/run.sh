#┌──────────────────────────────  ──────────────────────────────┐
#                           CMD output stuff
#└──────────────────────────────  ──────────────────────────────┘

sanitize_stream() {
  # - tr: quita carriage-return (progreso tipo “spinner”)
  # - sed: quita secuencias ANSI (colores/progreso)
  tr -d '\r' | sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'
}

run_cmd() { # run_cmd LEVEL "Label" -- cmd args...
  local level="$1"; shift
  local label="$1"; shift
  [[ "${1:-}" == "--" ]] && shift || true

  info_print "⏳ $label"
  state_set "stage" "$label"
  tui_refresh_throttled

  # stdbuf hace line-buffering para ver output en vivo
  # si no existiera, podés quitar "stdbuf -oL -eL"
  stdbuf -oL -eL "$@" 2>&1 | sanitize_stream | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    log_add INFO "$line"
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