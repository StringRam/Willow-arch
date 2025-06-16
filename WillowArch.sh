#! /usr/bin/env bash

# Willow Archlinux installation script for personal use.
# This set up uses a GPT partition table: p1 EFI_System 512Mb
#                                         p2 Linux_root(x86-64)
#   *BTRFS root partition
#   *@root, @home, @var_log, @snapshots and @swap subvolumes(can opt out of snapshots)
#   *Manual swap file size
#   *Optional LUKS system encryption
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
    echo -e "${BOLD}${GREEN}[ ${YELLOW}${GREEN} ] $1${RESET}"
}

input_print () {
    echo -ne "${BOLD}${YELLOW}[ ${GREEN}${YELLOW} ] $1${RESET}"
}

error_print () {
    echo -e "${BOLD}${RED}[ ${BLUE}${RED} ] $1${RESET}"
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
select_disk() {
    info_print "Available disks:"
    lsblk -dpno NAME,SIZE,MODEL | grep -v "boot"

    input_print "Enter the disk you want to install Arch on (e.g., /dev/nvme0n1 or /dev/sda): "
    read -r disk
    # Basic validation
    if [[ ! -b "$disk" ]]; then
        error_print "Invalid disk: $disk"
        exit 1
    fi

    info_print "Selected disk: $disk"
}

partition_disk() {
    input_print "Do you wish to make a custom partition layout? [y/N]: "
    read -r custom
    info_print "Partitioning disk $disk..."

    if [[ "${custom,,}" =~ ^(yes|y)$ ]]; then
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

select_swap_size(){

}

format_partitions() {
    input_print "Do you wish to use system encryption [y/N]?: "
    read -r encryption_response
    if [[ "${encryption_response,,}" =~ ^(yes|y)$ ]];
    then
        cryptsetup -v luksformat $root_part
        cryptsetup open $root_part root
    else
        info_print "Formatting partitions..."
        mkfs.fat -F32 "$efi_part"
        mkfs.btrfs "$root_part"
    fi

    info_print "Creating Btrfs subvolumes..."
    mount "$root_part" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@snapshots
    btrfs subvolume create /mnt/@var_log
    btrfs subvolume create /mnt/@swap
    umount /mnt
}

mount_partitions() {
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

package_install() {

}


#┌──────────────────────────────  ──────────────────────────────┐
#                      Fstab/Timezone/Locale
#└──────────────────────────────  ──────────────────────────────┘
fstab_file() {

}

timezone_selector() {

}

locale_selector() {

}


#┌──────────────────────────────  ──────────────────────────────┐
#               Hostname/Users/Bootloader installation
#└──────────────────────────────  ──────────────────────────────┘
hostname_selector() {

}

set_usernpasswd() {

}

set_rootpasswd() {

}

grub_installation() {

}


#┌──────────────────────────────  ──────────────────────────────┐
#                       Installation process
#└──────────────────────────────  ──────────────────────────────┘

# Clean the tty before starting
clear

# ASCII Font: NScript
echo -ne "${BOLD}${GREEN}

 ,ggg,      gg      ,gg                                                                ,ggg,                                  
dP""Y8a     88     ,8P       ,dPYb, ,dPYb,                                            dP""8I                        ,dPYb,    
Yb, `88     88     d8'       IP'`Yb IP'`Yb                                           dP   88                        IP'`Yb    
 `"  88     88     88   gg   I8  8I I8  8I                                          dP    88                        I8  8I    
     88     88     88   ""   I8  8' I8  8'                                         ,8'    88                        I8  8'    
     88     88     88   gg   I8 dP  I8 dP    ,ggggg,    gg    gg    gg             d88888888    ,gggggg,    ,gggg,  I8 dPgg,  
     88     88     88   88   I8dP   I8dP    dP"  "Y8ggg I8    I8    88bg     __   ,8"     88    dP""""8I   dP"  "Yb I8dP" "8I 
     Y8    ,88,    8P   88   I8P    I8P    i8'    ,8I   I8    I8    8I      dP"  ,8P      Y8   ,8'    8I  i8'       I8P    I8 
      Yb,,d8""8b,,dP  _,88,_,d8b,_ ,d8b,_ ,d8,   ,d8'  ,d8,  ,d8,  ,8I      Yb,_,dP       `8b,,dP     Y8,,d8,_    _,d8     I8,
       "88"    "88"   8P""Y88P'"Y888P'"Y88P"Y8888P"    P""Y88P""Y88P"        "Y8P"         `Y88P      `Y8P""Y8888PP88P     `Y8
                                                                                                                              
${RESET}"

info_print "Welcome to the Willow-Arch! A somewhat flexible archlinux installation script"

check_uefi
check_clock_sync

input_print "Warning: this will wipe the selected disk. Continue [y/N]?: "
read -r disk_response
if ! [[ "${disk_response,,}" =~ ^(yes|y)$ ]]; then
    error_print "Quitting..."
    exit
fi

info_print "Please select a disk for partitioning:"

select_disk
partition_disk

input_print "Please set a swap size[k/m/g/e/p suffix, 0=no swap]: "

select_swap_size
format_partitions
mount_partitions

info_print "Device: $disk properly partitioned, formated and mounted."

kernel_selector
microcode_detector
reflector_conf
package_install

fstab_file
arch-chroot /mnt
timezone_selector
locale_selector
hostname_selector

info_print "Configuring /etc/mkinitcpio.conf."
cat > /mnt/etc/mkinitcpio.conf <<EOF
HOOKS=(systemd autodetect keyboard sd-vconsole modconf block sd-encrypt filesystems)
EOF
info_print "Recreating intramfs image..."
mkinitcpio -P

set_usernpasswd
set_rootpasswd
grub_installation

