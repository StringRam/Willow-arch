#! /usr/bin/env bash

# Willow Archlinux installation script for personal use.
# This set up uses a GPT partition table: p1 EFI_System 512Mb
#                                         p2 Linux_root(x86-64)
#   *BTRFS root partition
#   *@root, @home, @var_log, @snapshots and @swap subvolumes(can opt out of snapshots)
#   *Manual swap file size
#   *Optional System encryption
#
# MIT License Copyright (c) 2025 Mateo Correa Franco

#┌──────────────────────────────  ──────────────────────────────┐
#                    Fancy text formating stuff
#└──────────────────────────────  ──────────────────────────────┘
BOLD='\033[1m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
MAGENTA='\033[35m'
CYAN='\033[36m'
## Reset color
RESET='\033[0m'

info_print () {
    echo -e "${BOLD}${GREEN}[ ${YELLOW}•${GREEN} ] ${RESET}"
}

input_print () {
    echo -ne "${BOLD}${YELLOW}[ ${GREEN}•${YELLOW} ] ${RESET}"
}

error_print () {
    echo -e "${BOLD}${RED}[ ${BLUE}•${RED} ] ${RESET}"
}


#┌──────────────────────────────  ──────────────────────────────┐
#                          Initial checks
#└──────────────────────────────  ──────────────────────────────┘
check_uefi() {
    if [[ -f /sys/firmware/efi/fw_platform_size ]]; then
        fw_size=$(cat /sys/firmware/efi/fw_platform_size)
        if [[ "$fw_size" == "64" || "$fw_size" == "32" ]]; then
            info_print "UEFI mode detected: $fw_size-bit"
        else
            error_print "Unknown firmware platform size: $fw_size"
            exit 1
        fi
    else
        error_print "BIOS mode detected — UEFI not supported or not enabled."
        exit 1
    fi
}

check_clock_sync() {
    info_print "Checking system clock synchronization..."
    sync_status=$(timedatectl show -p NTPSynchronized --value)

    if [[ "$sync_status" == "yes" ]]; then
        info_print "System clock is synchronized."
    else
        error_print "Warning: System clock is NOT synchronized."
        info_print "Trying to enable time synchronization..."

        timedatectl set-ntp true

        sleep 2
        sync_status=$(timedatectl show -p NTPSynchronized --value)
        if [[ "$sync_status" == "yes" ]]; then
            info_print "System clock is now synchronized."
        else
            error_print "Failed to synchronize system clock. Check your internet connection or NTP settings."
            exit 1
        fi
    fi
}


#┌──────────────────────────────  ──────────────────────────────┐
#                Disk partitioning, formatting, etc.
#└──────────────────────────────  ──────────────────────────────┘
partition_disk() {
    input_print "Do you wish to make a custom partition layout? [y/N]: "
    read -r custom
    custom=${custom,,}  # lowercase conversion

    info_print "Partitioning disk $disk..."

    if [[ "$custom" == "y" || "$custom" == "yes" ]]; then
        fdisk "$disk"
        info_print "Custom layout complete."
        lsblk "$disk"
        input_print "Enter EFI partition (e.g., /dev/nvme0n1p1): "
        read -r efi_part
        input_print "Enter root partition (e.g., /dev/nvme0n1p2): "
        read -r root_part

    else
        fdisk "$disk" <<EOF
g
n


+512M
t
1
n



t
23
w
EOF
        efi_part="${disk}p1"
        root_part="${disk}p2"
        info_print "Default partitioning complete: EFI=$efi_part, ROOT=$root_part"
    fi
}

format_partitions() {
    info_print "Formatting partitions..."
    mkfs.fat -F32 "$efi_part"
    mkfs.btrfs "$root_part"
}

create_btrfs_subvolumes() {
    info_print "Creating Btrfs subvolumes..."
    mount "$root_part" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    umount /mnt
}

mount_subvolumes() {
    info_print "Mounting subvolumes..."
    mount -o compress=zstd,subvol=@ "$root_part" /mnt
    mkdir -p /mnt/home
    mount -o compress=zstd,subvol=@home "$root_part" /mnt/home
    mkdir -p /mnt/efi
    mount "$efi_part" /mnt/efi
}


#┌──────────────────────────────  ──────────────────────────────┐
#                       Packages installation
#└──────────────────────────────  ──────────────────────────────┘
reflector_conf() {
    info_print 'Running reflector to generate mirrorlist'
    
}

kernel_selector() {
    
}

microcode_detector() {

}


#┌──────────────────────────────  ──────────────────────────────┐
#                          Fstab/Timezone
#└──────────────────────────────  ──────────────────────────────┘



#┌──────────────────────────────  ──────────────────────────────┐
#                  User/Hostname/Locale prompts
#└──────────────────────────────  ──────────────────────────────┘



#┌──────────────────────────────  ──────────────────────────────┐
#                       Network configuration
#└──────────────────────────────  ──────────────────────────────┘



# Clean the tty before starting
clear

