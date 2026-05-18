#!/usr/bin/env bash

# Locale, keyboard, hostname, users, fstab, zram, and system files.

fstab_file() {
    info_print "Generating fstab file..."
    run_quiet SYS -- bash -c 'genfstab -U /mnt >> /mnt/etc/fstab'
}

locale_selector() {
    tui_readline locale "Please insert a locale (Empty to use en_US, \"/\" to search locales): "
    case "$locale" in
        '') locale="${DEFAULT_LOCALE:-en_US.UTF-8}"
            info_print "$locale will be the default locale."
            state_set "Locale" "$locale"
            return 0;;
        '/') tui_pager_cmd -- sed -E '/^# +|^#$/d;s/^#| *$//g;s/ .*/ (Charset:&)/' /etc/locale.gen
            return 1;;
        *)  if ! grep -q "^#\?$(sed 's/[].*[]/\\&/g' <<< "$locale") " /etc/locale.gen; then
                error_print "The specified locale doesn't exist or isn't supported."
                return 1
            fi
            state_set "Locale" "$locale"
            return 0
    esac
}

keyboard_selector() {
    tui_readline kblayout "Please enter a keyboard layout (empty = US, \"/\" to look up for keyboard layouts): "
    case "$kblayout" in
        '') kblayout="${DEFAULT_KEYMAP:-us}"
            info_print "The standard US keyboard layout will be used."
            state_set "Keyboard Layout" "$kblayout"
            return 0;;
        '/') tui_pager_cmd -- localectl list-keymaps
             return 1;;
        *) if ! localectl list-keymaps | grep -Fxq "$kblayout"; then
               error_print "The specified keymap doesn't exist."
               return 1
           fi
        info_print "Changing console layout to $kblayout."
        run_quiet SYS -- loadkeys "$kblayout"
        state_set "Keyboard Layout" "$kblayout"
        return 0
    esac
}

hostname_selector() {
    tui_readline hostname "Please enter a hostname (1 to 63 characters, lowercase, 0 to 9): "
    if [[ -z "$hostname" ]]; then
        echo
        error_print "You need to enter a hostname in order to continue."
        return 1
    fi
    state_set "Hostname" "$hostname"
    return 0
}

set_usernpasswd() {
    tui_readline username "Please enter name for a user account: "
    if [[ -z "$username" ]]; then
        return 1
    fi
    state_set "Username" "$username"
    tui_readsecret userpasswd "Please enter a password for $username (you're not going to see the password): "
    echo
    if [[ -z "$userpasswd" ]]; then
        error_print "You need to enter a password for $username, please try again."
        return 1
    fi
    tui_readsecret userpasswd2 "Please enter the password again (you're not going to see it): " 
    echo
    if [[ "$userpasswd" != "$userpasswd2" ]]; then
        error_print "Passwords don't match, please try again."
        return 1
    fi
    return 0
}

set_rootpasswd() {
    tui_readsecret rootpasswd "Please enter a password for the root user (you're not going to see it): "
    echo
    if [[ -z "$rootpasswd" ]]; then
        error_print "You need to enter a password for the root user, please try again."
        return 1
    fi
    tui_readsecret rootpasswd2 "Please enter the password again (you're not going to see it): " 
    echo
    if [[ "$rootpasswd" != "$rootpasswd2" ]]; then
        error_print "Passwords don't match, please try again."
        return 1
    fi
    return 0
}

setup_zram() {
  # zram-generator: no hay que "enablear" un service; systemd genera el .swap al boot
  run_quiet SYS -- install -d /mnt/etc/systemd

  cat > /mnt/etc/systemd/zram-generator.conf <<'EOF'
[zram0]
# Solo activar en sistemas con menos de 8G de RAM
host-memory-limit = 8192

# Swap en zram
zram-size = ram * 1.0
compression-algorithm = lzo-rle
swap-priority = 100
EOF
}
