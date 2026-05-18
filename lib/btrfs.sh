#!/usr/bin/env bash

# Btrfs formatting, subvolumes, mounts, and swapfile setup.

format_partitions() {
    info_print "Formatting partitions..."
    run_quiet FS -- mkfs.fat -F 32 "$efi_part"

    run_with_input CRYPT "$encryption_passwd" -- cryptsetup luksFormat "$root_part" -d -
    run_with_input CRYPT "$encryption_passwd" -- cryptsetup open "$root_part" cryptroot -d -
    BTRFS="/dev/mapper/cryptroot"
    run_quiet FS -- mkfs.btrfs "$BTRFS"
    run_quiet FS -- mount "$BTRFS" /mnt

    info_print "Creating Btrfs subvolumes..."
    subvols=(snapshots var_log home root srv)
    for subvol in '' "${subvols[@]}"; do
        run_quiet FS -- btrfs subvolume create /mnt/@"$subvol"
    done
    tui_readline swap_size "Please set a swap size[k/m/g/e/p suffix, 0=no swap]: "
    state_set "Swap Size" "$swap_size"
    [[ "$swap_size" != "0" ]] && run_quiet FS -- btrfs subvolume create /mnt/@swap
    run_quiet FS -- umount /mnt
    info_print "Subvolumes created successfully"
}

mount_partitions() {
    info_print "Mounting subvolumes..."
    mountopts="${BTRFS_MOUNT_OPTS:-ssd,noatime,compress-force=zstd:3,discard=async}"
    run_quiet FS -- mount -o "$mountopts",subvol=@ "$BTRFS" /mnt
    run_quiet FS -- mkdir -p /mnt/{home,root,srv,.snapshots,var/log,boot}
    for subvol in "${subvols[@]:1}"; do
        run_quiet FS -- mount -o "$mountopts",subvol=@"$subvol" "$BTRFS" /mnt/"${subvol//_//}"
    done
    run_quiet FS -- chmod 750 /mnt/root
    run_quiet FS -- mount -o "$mountopts",subvol=@snapshots "$BTRFS" /mnt/.snapshots
    run_quiet FS -- chattr +C /mnt/var/log
    run_quiet FS -- mount "$efi_part" /mnt/boot

    if [[ "$swap_size" != "0" ]]; then
        info_print "Creating swap file..."
        run_quiet FS -- mkdir -p /mnt/.swap
        run_quiet FS -- mount -o compress=zstd,subvol=@swap "$BTRFS" /mnt/.swap
        run_quiet FS -- btrfs filesystem mkswapfile --size "$swap_size" --uuid clear /mnt/.swap/swapfile
        run_quiet FS -- swapon /mnt/.swap/swapfile
    else
        info_print "No swap file will be created."
    fi
}
