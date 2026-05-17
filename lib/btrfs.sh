#!/usr/bin/env bash

# Btrfs formatting, subvolumes, mounts, and swapfile setup.

format_partitions() {
    info_print "Formatting partitions..."
    mkfs.fat -F 32 "$efi_part" &>/dev/null

    echo -n "$encryption_passwd" | cryptsetup luksFormat "$root_part" -d - &>/dev/null
    echo -n "$encryption_passwd" | cryptsetup open "$root_part" cryptroot -d -
    BTRFS="/dev/mapper/cryptroot"
    mkfs.btrfs "$BTRFS" &>/dev/null
    mount "$BTRFS" /mnt

    info_print "Creating Btrfs subvolumes..."
    subvols=(snapshots var_log home root srv)
    for subvol in '' "${subvols[@]}"; do
        btrfs su cr /mnt/@"$subvol" &>/dev/null
    done
    tui_readline swap_size "Please set a swap size[k/m/g/e/p suffix, 0=no swap]: "
    state_set "Swap Size" "$swap_size"
    [ "$swap_size" != "0" ] && btrfs su cr /mnt/@swap &>/dev/null
    umount /mnt
    info_print "Subvolumes created successfully"
}

mount_partitions() {
    info_print "Mounting subvolumes..."
    mountopts="${BTRFS_MOUNT_OPTS:-ssd,noatime,compress-force=zstd:3,discard=async}"
    mount -o "$mountopts",subvol=@ "$BTRFS" /mnt
    mkdir -p /mnt/{home,root,srv,.snapshots,var/log,boot}
    for subvol in "${subvols[@]:1}"; do
        mount -o "$mountopts",subvol=@"$subvol" "$BTRFS" /mnt/"${subvol//_//}"
    done
    chmod 750 /mnt/root
    mount -o "$mountopts",subvol=@snapshots "$BTRFS" /mnt/.snapshots
    chattr +C /mnt/var/log
    mount "$efi_part" /mnt/boot

    if [[ "$swap_size" != "0" ]]; then
        info_print "Creating swap file..."
        mkdir -p /mnt/.swap
        mount -o compress=zstd,subvol=@swap "$BTRFS" /mnt/.swap
        btrfs filesystem mkswapfile --size "$swap_size" --uuid clear /mnt/.swap/swapfile &>/dev/null
        swapon /mnt/.swap/swapfile
    else
        info_print "No swap file will be created."
    fi
}
