#!/usr/bin/env bash

# Willow Archlinux installation script for personal use.
# This set up uses a GPT partition table: p1 EFI_System 512Mb
#                                         p2 Linux_root(x86-64)
#   *root_part root partition
#   *@root, @home, @var_log, @snapshots and @swap subvolumes
#   *Manual swap file size
#   *LUKS system encryption
#
# Credits to classy-giraffe for his script.
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

    info_print "Wiping $root_part..."
    cryptsetup open --type plain --key-file /dev/urandom --sector-size 4096 "$root_part" wipecrypt
    dd if=/dev/zero of=/dev/mapper/wipecrypt status=progress bs=1M
    cryptsetup close wipecrypt
    info_print "Wiping process complete."

    until set_luks_passwd; do : ; done

    echo -n "$encryption_passwd" | cryptsetup luksFormat "$root_part" -d - &>/dev/null
    echo -n "$encryption_passwd" | cryptsetup open "$root_part" root -d -
    BTRFS=/dev/mapper/root
    mkfs.btrfs "$BTRFS" &>/dev/null

    info_print "Creating Btrfs subvolumes..."
    mount "$BTRFS" /mnt
    subvols=( "" home var_log snapshots swap )
    for subvol in "${subvols[@]}"; do
        if [[ -z "$subvol" ]]; then
            btrfs su cr /mnt/@
        else
            btrfs su cr /mnt/@$subvol
        fi
    done

    umount /mnt
    info_print "Subvolumes created successfully"
}

mount_partitions() {
    info_print "Mounting subvolumes..."
    mountopts="ssd,noatime,compress-force=zstd:3,discard=async"
    
    mount -o "$mountopts",subvol=@ "$BTRFS" /mnt
    mkdir -p /mnt/{home,root,.snapshots,var/log,boot,swap}

    mount -o "$mountopts",subvol=@home "$BTRFS" /mnt/home
    mount -o "$mountopts",subvol=@var_log "$BTRFS" /mnt/var/log
    mount -o "$mountopts",subvol=@snapshots "$BTRFS" /mnt/.snapshots
    mount -o "$mountopts",subvol=@swap "$BTRFS" /mnt/swap

    chmod 750 /mnt/root
    chattr +C /mnt/var/log
    mount "$efi_part" /mnt/boot/

    info_print "Creating swap file..."
    if [[ "$swap_size" != "0" ]]; then
        mkdir -p /mnt/swap
        chattr +C /mnt/swap
        btrfs filesystem mkswapfile --size "$swap_size" --uuid clear /mnt/swap/swapfile
        swapon /mnt/swap/swapfile
    else
        info_print "No swap file will be created."
    fi
}


#┌──────────────────────────────  ──────────────────────────────┐
#                       Packages installation
#└──────────────────────────────  ──────────────────────────────┘
kernel_selector() {
    info_print "List of kernels:"
    info_print "1) Stable: Vanilla Linux kernel with a few specific Arch Linux patches applied"
    info_print "2) Hardened: A security-focused Linux kernel"
    info_print "3) Longterm: Long-term support (LTS) Linux kernel"
    info_print "4) Zen Kernel: A Linux kernel optimized for desktop usage"
    input_print "Please select the number of the corresponding kernel (e.g. 1): " 
    read -r kernel_choice
    case $kernel_choice in
        1 ) kernel="linux"
            return 0;;
        2 ) kernel="linux-hardened"
            return 0;;
        3 ) kernel="linux-lts"
            return 0;;
        4 ) kernel="linux-zen"
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

aur_helper_selector() {
    info_print "AUR helpers are used to install packages from the Arch User Repository (AUR)."
    input_print "Choose an AUR helper to install (yay/paru, leave empty to skip): "
    read -r aur_helper
    case "$aur_helper" in
        yay|paru)
            aur_bool=1
            info_print "AUR helper $aur_helper will be installed for user $username."
            ;;
        '')
            aur_bool=0
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
    [[ -z "$aur_helper" || -z "$username" ]] && return
    arch-chroot /mnt /bin/bash -c "
        sudo -u $username bash -c '
            cd ~
            rm -rf $aur_helper
            git clone https://aur.archlinux.org/$aur_helper.git
            cd $aur_helper
            makepkg -si --noconfirm
        '
    "
}

read_pkglist() {
    local pkgfile="pkglist.txt"
    packages=()

    while IFS= read -r line || [[ -n $line ]]; do
        # Skip empty lines and comment lines starting with #
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        packages+=("$line")
    done < "$pkgfile"

    info_print "Loaded ${#packages[@]} packages from $pkgfile"
}

package_install() {
    read_pkglist
    packages+=("$kernel" "$kernel-headers" "$microcode")

    info_print "Installing packages: ${packages[*]}"
    pacstrap -K /mnt "${packages[@]}"
}


#┌──────────────────────────────  ──────────────────────────────┐
#                      Fstab/Timezone/Locale
#└──────────────────────────────  ──────────────────────────────┘
fstab_file() {
    info_print "Generating fstab file..."
    genfstab -U /mnt >> /mnt/etc/fstab
    
    if ! grep -q "^/swap/swapfile" /mnt/etc/fstab; then
        info_print "Adding swapfile entry to fstab..."
        echo "/swap/swapfile none swap defaults 0 0" >> /mnt/etc/fstab
    fi

    echo
    info_print "Here is the final /etc/fstab content:"
    echo "------------------------------------------------------------"
    cat /mnt/etc/fstab
    echo "------------------------------------------------------------"
}

locale_selector() {
    input_print "Please insert the locale you use (format: xx_XX. Enter empty to use en_US, or \"/\" to search locales): " locale
    read -r locale
    case "$locale" in
        '') locale="en_US.UTF-8"
            info_print "$locale will be the default locale."
            return 0;;
        '/') sed -E '/^# +|^#$/d;s/^#| *$//g;s/ .*/ (Charset:&)/' /etc/locale.gen | less -M
                clear
                return 1;;
        *)  if ! grep -q "^#\?$(sed 's/[].*[]/\\&/g' <<< "$locale") " /etc/locale.gen; then
                error_print "The specified locale doesn't exist or isn't supported."
                return 1
            fi
            return 0
    esac
}

keyboard_selector() {
    input_print "Please insert the keyboard layout to use in console (enter empty to use US, or \"/\" to look up for keyboard layouts): "
    read -r kblayout
    case "$kblayout" in
        '') kblayout="us"
            info_print "The standard US keyboard layout will be used."
            return 0;;
        '/') localectl list-keymaps
             clear
             return 1;;
        *) if ! localectl list-keymaps | grep -Fxq "$kblayout"; then
               error_print "The specified keymap doesn't exist."
               return 1
           fi
        info_print "Changing console layout to $kblayout."
        loadkeys "$kblayout"
        return 0
    esac
}


#┌──────────────────────────────  ──────────────────────────────┐
#               Hostname/Users/Bootloader installation
#└──────────────────────────────  ──────────────────────────────┘
hostname_selector() {
    input_print "Please enter the hostname: "
    read -r hostname
    if [[ -z "$hostname" ]]; then
        error_print "You need to enter a hostname in order to continue."
        return 1
    fi
    return 0
}

set_usernpasswd() {
    input_print "Please enter name for a user account: "
    read -r username
    if [[ -z "$username" ]]; then
        return 1
    fi
    input_print "Please enter a password for $username (you're not going to see the password): "
    read -r -s userpasswd
    if [[ -z "$userpasswd" ]]; then
        echo
        error_print "You need to enter a password for $username, please try again."
        return 1
    fi
    echo
    input_print "Please enter the password again (you're not going to see it): " 
    read -r -s userpasswd2
    echo
    if [[ "$userpasswd" != "$userpasswd2" ]]; then
        echo
        error_print "Passwords don't match, please try again."
        return 1
    fi
    return 0
}

set_rootpasswd() {
    input_print "Please enter a password for the root user (you're not going to see it): "
    read -r -s rootpasswd
    if [[ -z "$rootpasswd" ]]; then
        echo
        error_print "You need to enter a password for the root user, please try again."
        return 1
    fi
    echo
    input_print "Please enter the password again (you're not going to see it): " 
    read -r -s rootpasswd2
    echo
    if [[ "$rootpasswd" != "$rootpasswd2" ]]; then
        error_print "Passwords don't match, please try again."
        return 1
    fi
    return 0
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
package_install

until locale_selector; do : ; done
until keyboard_selector; do : ; done
until hostname_selector; do : ; done
until set_usernpasswd; do : ; done
until set_rootpasswd; do : ; done
until aur_helper_selector; do : ; done

echo "$hostname" > /mnt/etc/hostname

fstab_file

sed -i "/^#$locale/s/^#//" /mnt/etc/locale.gen
echo "LANG=$locale" > /mnt/etc/locale.conf
echo "KEYMAP=$kblayout" > /mnt/etc/vconsole.conf

info_print "Configuring /etc/mkinitcpio.conf."
cat > /mnt/etc/mkinitcpio.conf <<EOF
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt lvm2 filesystems fsck grub-btrfs-overlayfs)
EOF

info_print "Setting up grub config."
UUID=$(blkid -s UUID -o value $root_part)
sed -i "\,^GRUB_CMDLINE_LINUX=\"\",s,\",&rd.luks.name=$UUID=cryptroot root=$BTRFS," /mnt/etc/default/grub

info_print "Configuring the system (timezone, system clock, initramfs, Snapper, GRUB)."
arch-chroot /mnt /bin/bash -e <<EOF

    # Setting up timezone.
    ln -sf /usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone) /etc/localtime &>/dev/null

    # Setting up clock.
    hwclock --systohc

    # Generating locales.
    locale-gen &>/dev/null

    # Generating a new initramfs.
    mkinitcpio -P &>/dev/null

    # Snapper configuration.
    umount /.snapshots
    rm -r /.snapshots
    snapper --no-dbus -c root create-config /
    btrfs subvolume delete /.snapshots &>/dev/null
    mkdir /.snapshots
    mount -a &>/dev/null
    chmod 750 /.snapshots

    # Installing GRUB.
    grub-install --target=x86_64-efi --efi-directory=/boot/ --bootloader-id=GRUB &>/dev/null

    # Creating grub config file.
    grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null

EOF

info_print "Setting root password."
echo "root:$rootpasswd" | arch-chroot /mnt chpasswd

if [[ -n "$username" ]]; then
    echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/wheel
    info_print "Adding the user $username to the system with root privilege."
    arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$username"
    info_print "Setting user password for $username."
    echo "$username:$userpasswd" | arch-chroot /mnt chpasswd
fi

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

info_print "Enabling colours, animations, and parallel downloads for pacman."
sed -Ei 's/^#(Color)$/\1\nILoveCandy/;s/^#(ParallelDownloads).*/\1 = 10/' /mnt/etc/pacman.conf

info_print "Enabling multilib repository in pacman.conf."
sed -i '/^\[multilib\]/,/^\[/{s/^#//}' /mnt/etc/pacman.conf

if [[ $aur_bool -eq 1 ]]; then
    install_aur_helper
fi

info_print "Enabling Reflector, automatic snapshots and BTRFS scrubbing"
services=(reflector.timer snapper-timeline.timer snapper-cleanup.timer btrfs-scrub@-.timer btrfs-scrub@home.timer btrfs-scrub@var-log.timer btrfs-scrub@\\x2esnapshots.timer grub-btrfsd.service)
for service in "${services[@]}"; do
    systemctl enable "$service" --root=/mnt &>/dev/null
done

info_print "Done, you may now wish to reboot (further changes can be done by chrooting into /mnt)."
exit
