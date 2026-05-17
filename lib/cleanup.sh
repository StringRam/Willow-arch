#!/usr/bin/env bash

installer_cleanup() {
    local exit_code="${1:-$?}"

    trap - EXIT INT TERM ERR

    if [[ "${RUN_TUI:-1}" -eq 1 ]] && declare -F tui_cleanup >/dev/null; then
        tui_cleanup || true
    fi

    exit "$exit_code"
}

installer_signal_trap() {
    local signal="$1"

    case "$signal" in
        INT)  installer_cleanup 130 ;;
        TERM) installer_cleanup 143 ;;
        *)    installer_cleanup 1 ;;
    esac
}

installer_error_trap() {
    local exit_code=$?
    local line_no="${1:-unknown}"
    local command="${2:-unknown}"

    if [[ "${RUN_TUI:-1}" -eq 1 ]] && declare -F tui_error_pause >/dev/null; then
        tui_error_pause "$exit_code" "$line_no" "$command" || true
    else
        printf '\n[ERR] line %s: %s\nstatus=%s\n' "$line_no" "$command" "$exit_code" >&2
    fi

    return "$exit_code"
}

register_cleanup_trap() {
    set -o errtrace

    trap 'installer_cleanup "$?"' EXIT
    trap 'installer_signal_trap INT' INT
    trap 'installer_signal_trap TERM' TERM
    trap 'installer_error_trap "$LINENO" "$BASH_COMMAND"' ERR
}