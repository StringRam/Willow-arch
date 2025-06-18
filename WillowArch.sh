#! /usr/bin/env bash

# Willow Archlinux installation script for personal use.
# This set up uses a GPT partition table: p1 EFI_System 512Mb
#                                         p2 Linux_root(x86-64)
#   *root_part root partition
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
# Reset color
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

    PS3="Select the disk you want to install Arch on (e.g. 1): "
    select disk in $(lsblk -dpno NAME | grep -v "boot"); do
        if [[ -b $disk ]]; then
            info_print "Selected disk: $disk"
            break
        else
            error_print "Invalid selection."
        fi
    done
    info_print "Informing kernel about disk changes..."
    partprobe "$disk" || udevadm settle
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
        efi_part=$(lsblk -lnpo NAME "$disk" | sed -n '2p')
        root_part=$(lsblk -lnpo NAME "$disk" | sed -n '3p')
        info_print "Default partitioning complete: EFI=$efi_part, ROOT=$root_part"
    fi
}

set_luks_passwd() {
    input_print "Enter your LUKS container password (for security purposes you won't see it): "
    read -r -s encryption_passwd
    if [[ -z $encryption_passwd ]]; then
        echo
        error_print "You must enter a password for the LUKS container. Try again"
        return 1
    fi

    input_print "Enter your LUKS container password again (for security purposes you won't see it): "
    read -r -s encryption_passwd2
    if [[ $encryption_passwd != $encryption_passwd2 ]]; then
        error_print "Passwords don't match, try again"
        return 1
    fi

    return 0
}

format_partitions() {
    input_print "Please set a swap size[k/m/g/e/p suffix, 0=no swap]: "
    read -r swap_size

    info_print "Formatting partitions..."
    mkfs.fat -F32 "$efi_part" &>/dev/null

    input_print "Do you wish to use system encryption [y/N]?: "
    read -r encryption_response
    if [[ "${encryption_response,,}" =~ ^(yes|y)$ ]];
    then
        info_print "Wiping $root_part..."
        cryptsetup open --type plain --key-file /dev/urandom --sector-size 4096 "$root_part" wipecrypt
        dd if=/dev/zero of=/dev/mapper/wipecrypt status=progress bs=1M
        cryptsetup close wipecrypt
        info_print "Wiping process complete."

        until set_luks_passwd; do : ; done

        echo -n "$encryption_passwd" | cryptsetup luksFormat "$root_part" -d - &>/dev/null
        echo -n "$encryption_passwd" | cryptsetup open "$root_part" root -d -
        root_part=/dev/mapper/root
        mkfs.btrfs "$root_part" &>/dev/null
    else
        mkfs.btrfs "$root_part" &>/dev/null
    fi

    info_print "Creating Btrfs subvolumes..."
    mount "$root_part" /mnt
    subvols=(snapshots swap var_log home root)
    for subvol in '' "${subvols[@]}"; do
        btrfs su cr /mnt/@"$subvol" &>/dev/null
    done

    umount /mnt
    info_print "Subvolumes created successfully"
}

mount_partitions() {
    info_print "Mounting subvolumes..."
    mountopts="ssd,noatime,compress-force=zstd:3,discard=async"
    
    mount -o "$mountopts",subvol=@ "$root_part" /mnt
    mkdir -p /mnt/{home,root,.snapshots,var/log,boot,swap}
    for subvol in "${subvols[@]:1}"; do
        mount -o "$mountopts",subvol=@"$subvol" "$root_part" /mnt/"${subvol//_//}"
    done
    chmod 750 /mnt/root
    mount -o "$mountopts",subvol=@snapshots "$root_part" /mnt/.snapshots
    chattr +C /mnt/var/log
    mount "$efi_part" /mnt/boot/
    info_print "Creating swap file..."
    chattr +C /mnt/swap
    btrfs filesystem mkswapfile --size "$swap_size" --uuid clear /mnt/swap/swapfile
    swapon /mnt/swap/swapfile
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
format_partitions
mount_partitions

info_print "Device: $disk properly partitioned, formated and mounted."

until kernel_selector; do : ; done
microcode_detector
reflector_conf
package_install

fstab_file
timezone_selector
until locale_selector; do : ; done
until hostname_selector; do : ; done
until set_usernpasswd; do : ; done
until set_rootpasswd; do : ; done

if [[ "${encryption_response,,}" =~ ^(yes|y)$ ]]; then
    info_print "Configuring /etc/mkinitcpio.conf."
    cat > /mnt/etc/mkinitcpio.conf <<EOF
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt lvm2 filesystems fsck grub-btrfs-overlayfs)
EOF
fi

arch-chroot /mnt
