#!/usr/bin/env bash

# Kernel, hardware detection, packages, and AUR helper installation.

kernel_selector() {
    info_print "List of kernels:"
    raw_print "1) Stable: Vanilla Linux kernel with a few specific Arch Linux patches applied"
    raw_print "2) Hardened: A security-focused Linux kernel"
    raw_print "3) Longterm: Long-term support (LTS) Linux kernel"
    raw_print "4) Zen Kernel: A Linux kernel optimized for desktop usage"
    tui_readline kernel_choice "Please select the number of the corresponding kernel (e.g. 1): " 
    case "$kernel_choice" in
        1 ) kernel="linux"
            state_set "Kernel" "Stable"
            return 0;;
        2 ) kernel="linux-hardened"
            state_set "Kernel" "Hardened"
            return 0;;
        3 ) kernel="linux-lts"
            state_set "Kernel" "Longterm"
            return 0;;
        4 ) kernel="linux-zen"
            state_set "Kernel" "Zen"
            return 0;;
        * ) error_print "You did not enter a valid selection, please try again."
            return 1
    esac
}

microcode_detector() {
    CPU=$(grep vendor_id /proc/cpuinfo)
    if [[ "$CPU" == *"AuthenticAMD"* ]]; then
        info_print "An AMD CPU has been detected, the AMD microcode will be installed."
        microcode="amd-ucode"
    else
        info_print "An Intel CPU has been detected, the Intel microcode will be installed."
        microcode="intel-ucode"
    fi
}

detect_gpu_vendor() {
  local v
  v="$(lspci -nn | grep -Ei 'VGA|3D|Display' || true)"
  if   grep -qi 'Intel'  <<<"$v"; then gpuvendor=intel
  elif grep -Eqi 'AMD|ATI' <<<"$v"; then gpuvendor=amd
  elif grep -qi 'NVIDIA' <<<"$v"; then gpuvendor=nvidia
  else gpuvendor=unknown
  fi
}

aur_helper_selector() {
    info_print "AUR helpers are used to install packages from the Arch User Repository (AUR)."
    tui_readline aur_helper "Choose an AUR helper to install (yay/paru, leave empty to skip): "
    case "$aur_helper" in
        yay|paru)
            info_print "AUR helper $aur_helper will be installed for user $username."
            state_set "AUR Helper" "$aur_helper"
            ;;
        '')
            info_print "No AUR helper will be installed."
            ;;
        *)
            error_print "Invalid choice. Supported: yay, paru."
            return 1
            ;;
    esac
    return 0
}

install_aur_helper() {
  [[ -z "${aur_helper:-}" || -z "${username:-}" ]] && return 0

  run_cmd RAW -- arch-chroot /mnt /usr/bin/runuser -u "$username" -- bash -lc "
    set -euo pipefail
    cd ~
    rm -rf '$aur_helper' || true
    git clone 'https://aur.archlinux.org/$aur_helper.git'
    cd '$aur_helper'
    makepkg -c --noconfirm --needed
  "

  run_cmd RAW -- arch-chroot /mnt bash -lc "
    set -euo pipefail
    cd '/home/$username/$aur_helper'
    pacman -U --noconfirm --needed ./*.pkg.tar.*
  "
}

read_pkglist() {
    local pkgfile="$SCRIPT_DIR/config/packages/base.txt"
    packages=()

    if [[ ! -r "$pkgfile" ]]; then
        error_print "Package list file not found: $pkgfile"
        exit 1
    fi

    while IFS= read -r line || [[ -n $line ]]; do
        # Skip empty lines and comment lines starting with #
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        packages+=("$line")
    done < "$pkgfile"
}

package_install() {
    read_pkglist
    packages+=("$kernel" "$kernel"-headers "$microcode" mkinitcpio iptables-nft)
    if [[ $gpuvendor == "intel" ]]; then packages+=(intel-media-driver)
    fi
    info_print "Installing packages..."
    run_cmd RAW -- pacstrap -K /mnt "${packages[@]}"
}
