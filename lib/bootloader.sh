#!/usr/bin/env bash

# GRUB and initramfs configuration.

grub_installation() {
    info_print "Setting up grub config."
    UUID=$(blkid -s UUID -o value "$root_part")
    run_quiet BOOT -- perl -0777 -i -pe '
        if (/^GRUB_CMDLINE_LINUX_DEFAULT="([^"]*)"/m) {
            $v=$1;
            @add=qw(splash quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3 vt.global_cursor_default=0);
            for $f (@add) { $v .= " $f" unless $v =~ /(?:^|\s)\Q$f\E(?:\s|$)/; }
            $v =~ s/\s+/ /g; $v =~ s/^\s+|\s+$//g;
            s/^GRUB_CMDLINE_LINUX_DEFAULT="[^"]*"/GRUB_CMDLINE_LINUX_DEFAULT="$v"/m;
        }
    ' /mnt/etc/default/grub
    run_quiet BOOT -- sed -i "\,^GRUB_CMDLINE_LINUX=\"\",s,\",&rd.luks.name=$UUID=cryptroot root=$BTRFS," /mnt/etc/default/grub

    info_print "Configuring the system (timezone, system clock, initramfs, Snapper, GRUB)."
    run_cmd RAW -- arch-chroot /mnt /bin/bash -e <<'EOF_CHROOT'

    ln -sf /usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone) /etc/localtime

    hwclock --systohc

    locale-gen

    # Generating a new initramfs.
    mkinitcpio -P

    # Snapper configuration.
    umount /.snapshots
    rm -r /.snapshots
    snapper --no-dbus -c root create-config /
    btrfs subvolume delete /.snapshots
    mkdir /.snapshots
    mount -a
    chmod 750 /.snapshots

    # Installing GRUB.
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

    # Creating grub config file.
    grub-mkconfig -o /boot/grub/grub.cfg

EOF_CHROOT
}
