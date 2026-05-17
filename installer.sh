#!/usr/bin/env -S bash -e

# Willow Archlinux installation script for personal use.
#
# Credits to classy-giraffe for his script.
# MIT License Copyright (c) 2025 Mateo Correa Franco

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Defaults may be overridden by environment variables or future CLI flags.
[[ -r "$SCRIPT_DIR/config/defaults.conf" ]] && source "$SCRIPT_DIR/config/defaults.conf"

source "$SCRIPT_DIR/lib/tui.sh"
source "$SCRIPT_DIR/lib/cleanup.sh"
source "$SCRIPT_DIR/lib/run.sh"
source "$SCRIPT_DIR/lib/checks.sh"
source "$SCRIPT_DIR/lib/disk.sh"
source "$SCRIPT_DIR/lib/luks.sh"
source "$SCRIPT_DIR/lib/btrfs.sh"
source "$SCRIPT_DIR/lib/packages.sh"
source "$SCRIPT_DIR/lib/system.sh"
source "$SCRIPT_DIR/lib/bootloader.sh"

register_cleanup_trap

main() {
clear

enter_alt
render_splash
render_frame

check_uefi
check_clock_sync
progress_set 1

until keyboard_selector; do : ; done

select_disk
until set_luks_passwd; do : ; done
until kernel_selector; do : ; done
until locale_selector; do : ; done
until hostname_selector; do : ; done
until set_usernpasswd; do : ; done
until set_rootpasswd; do : ; done
progress_set 2

info_print "Wiping $disk."
wipefs -af "$disk" &>/dev/null
sgdisk -Zo "$disk" &>/dev/null

partition_disk
format_partitions
mount_partitions

info_print "Device: $disk properly partitioned, formated and mounted."
progress_set 3

microcode_detector
detect_gpu_vendor
package_install
progress_set 4

echo "$hostname" > /mnt/etc/hostname

fstab_file

sed -i "/^#$locale/s/^#//" /mnt/etc/locale.gen
echo "LANG=$locale" > /mnt/etc/locale.conf
echo "KEYMAP=$kblayout" > /mnt/etc/vconsole.conf

info_print "Setting hosts file."
cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain   $hostname
EOF
progress_set 5

#virt_check
setup_zram
progress_set 6

info_print "Configuring /etc/mkinitcpio.conf."
cat > /mnt/etc/mkinitcpio.conf <<EOF
HOOKS=(systemd autodetect microcode keyboard sd-vconsole modconf kms plymouth block sd-encrypt filesystems grub-btrfs-overlayfs)
EOF
grub_installation
progress_set 7

info_print "Setting root password."
echo "root:$rootpasswd" | arch-chroot /mnt chpasswd

if [[ -n "$username" ]]; then
    echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/wheel
    info_print "Adding the user $username to the system with root privilege."
    arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$username"
    info_print "Setting user password for $username."
    echo "$username:$userpasswd" | arch-chroot /mnt chpasswd
fi
progress_set 8

info_print "Configuring /boot backup when pacman transactions are made."
mkdir -p /mnt/etc/pacman.d/hooks
cat > /mnt/etc/pacman.d/hooks/50-bootbackup.hook <<EOF
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Path
Target = usr/lib/modules/*/vmlinuz

[Action]
Depends = rsync
Description = Backing up /boot...
When = PostTransaction
Exec = /usr/bin/rsync -a --delete /boot /.bootbackup
EOF

info_print "Enabling colours and parallel downloads for pacman."
sed -Ei 's/^#(Color)$/\1/;s/^#(ParallelDownloads).*/\1 = 10/' /mnt/etc/pacman.conf

info_print "Enabling multilib repository in pacman.conf."
sed -i "/^#\[multilib\]/,/^$/{s/^#//}" /mnt/etc/pacman.conf
arch-chroot /mnt pacman -Sy --noconfirm &>/dev/null

info_print "Enabling Reflector, automatic snapshots, BTRFS scrubbing, bluetooth and NetworkManager services."
services=(reflector.timer snapper-timeline.timer snapper-cleanup.timer btrfs-scrub@-.timer btrfs-scrub@home.timer btrfs-scrub@var-log.timer btrfs-scrub@\\x2esnapshots.timer grub-btrfsd.service bluetooth.service NetworkManager.service systemd-oomd.service)
for service in "${services[@]}"; do
    systemctl enable "$service" --root=/mnt &>/dev/null
done
progress_set 9

until aur_helper_selector; do : ; done
install_aur_helper
progress_set 10

info_print "Done, you may now wish to reboot (further changes can be done by chrooting into /mnt)."
info_print "Remember to unmount all partitions before rebooting."
}

main "$@"
