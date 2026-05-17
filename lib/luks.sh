#!/usr/bin/env bash

# LUKS password handling and encryption setup.

set_luks_passwd() {
    tui_readsecret encryption_passwd "Enter a LUKS container password (for security purposes you won't see it): "
    echo
    if [[ -z "$encryption_passwd" ]]; then
        error_print "You must enter a password for the LUKS container. Try again"
        return 1
    fi
    tui_readsecret encryption_passwd2 "Enter your LUKS container password again (for security purposes you won't see it): "
    echo
    if [[ "$encryption_passwd" != "$encryption_passwd2" ]]; then
        error_print "Passwords don't match, try again"
        return 1
    fi

    return 0
}
