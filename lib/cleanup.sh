#!/usr/bin/env bash

cleanup() {
    local exit_code=$?

    # Restore terminal UI state if TUI mode was enabled.
    if [[ "${RUN_TUI:-1}" -eq 1 ]]; then
        tui_cleanup || true
    fi

    exit "$exit_code"
}

register_cleanup_trap() {
    trap cleanup EXIT
}