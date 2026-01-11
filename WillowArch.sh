#!/usr/bin/env -S bash -e

# Willow Archlinux installation script for personal use.
# This set up uses a GPT partition table: p1 EFI_System 512Mb
#                                         p2 Linux_root(x86-64)
#   *root_part root partition
#   *@root, @home, @var_log, @snapshots and @swap subvolumes
#   *Manual swap file size
#   *LUKS system encryption
#   *Btrfs filesystem with compression and SSD optimizations
#   *zram for low RAM systems
#
# Credits to classy-giraffe for his script.
# MIT License Copyright (c) 2025 Mateo Correa Franco

set -Eeuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib/tui.sh"
source "$SCRIPT_DIR/lib/run.sh"

RUN_STREAM=0
RUN_TAIL=30

#┌──────────────────────────────  ──────────────────────────────┐
#                              Checks
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

# Virtualization check (function).
virt_check () {
    hypervisor=$(systemd-detect-virt)
    case $hypervisor in
        kvm )   info_print "KVM has been detected, setting up guest tools."
                pacstrap /mnt qemu-guest-agent &>/dev/null
                systemctl enable qemu-guest-agent --root=/mnt &>/dev/null
                ;;
        vmware  )   info_print "VMWare Workstation/ESXi has been detected, setting up guest tools."
                    pacstrap /mnt open-vm-tools &>/dev/null
                    systemctl enable vmtoolsd --root=/mnt &>/dev/null
                    systemctl enable vmware-vmblock-fuse --root=/mnt &>/dev/null
                    ;;
        oracle )    info_print "VirtualBox has been detected, setting up guest tools."
                    pacstrap /mnt virtualbox-guest-utils &>/dev/null
                    systemctl enable vboxservice --root=/mnt &>/dev/null
                    ;;
        microsoft ) info_print "Hyper-V has been detected, setting up guest tools."
                    pacstrap /mnt hyperv &>/dev/null
                    systemctl enable hv_fcopy_daemon --root=/mnt &>/dev/null
                    systemctl enable hv_kvp_daemon --root=/mnt &>/dev/null
                    systemctl enable hv_vss_daemon --root=/mnt &>/dev/null
                    ;;
    esac
}


#┌──────────────────────────────  ──────────────────────────────┐
#                Disk partitioning, formatting, etc.
#└──────────────────────────────  ──────────────────────────────┘
select_disk() {
  info_print "Please select a disk for partitioning:"
  tui_readline disk_response "Warning, this will wipe the selected disk, continue [y/N]?: "
  if ! [[ "${disk_response,,}" =~ ^(yes|y)$ ]]; then
    error_print "Quitting..."
    exit
  fi

  mapfile -t disks < <(lsblk -dpno NAME | grep -E '^/dev/(sd|nvme|vd|mmcblk)')
  tui_select_from_list disk "Available disks:" "${disks[@]}"

  info_print "Arch Linux will be installed on: $disk"
  state_set "Installation Disk" "$disk"
}

# Note: experiment with both fdisk and parted tomorrow to find out if it is necessary to change this implementation
partition_disk() {
    info_print "Partitioning disk $disk..."
parted -s "$disk" \
    mklabel gpt \
    mkpart esp fat32 1MiB 513MiB \
    set 1 esp on \
    mkpart root 513MiB 100% ;

    efi_part="/dev/disk/by-partlabel/esp"
    root_part="/dev/disk/by-partlabel/root"

    info_print "Default partitioning complete: EFI=$efi_part, ROOT=$root_part"
    info_print "Informing the Kernel about the disk changes."
    partprobe "$disk"
}

set_luks_passwd() {
    tui_readsecret encryption_passwd "Enter a LUKS container password (for security purposes you won't see it): "
    echo
    if [[ -z "$encryption_passwd" ]]; then
        error_print "You must enter a password for the LUKS container. Try again"
        return 1
    fi
    tui_readsecret encryption_passwd2 "Enter your LUKS container password again (for security purposes you won't see it): "
    echo
    if [[ "$encryption_passwd" != "$encryption_passwd2" ]]; then
        error_print "Passwords don't match, try again"
        return 1
    fi

    return 0
}

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
    mountopts="ssd,noatime,compress-force=zstd:3,discard=async"
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


#┌──────────────────────────────  ──────────────────────────────┐
#                       Packages installation
#└──────────────────────────────  ──────────────────────────────┘
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
    [[ -z "$aur_helper" || -z "$username" ]] && return
    arch-chroot /mnt /bin/bash <<EOF
sudo -u "$username" bash -c 'cd ~
git clone https://aur.archlinux.org/$aur_helper.git && cd "$aur_helper"
makepkg -si --noconfirm'
EOF
    info_print "AUR helper $aur_helper has been installed for user $username."
}

read_pkglist() {
    local pkgfile="$SCRIPT_DIR/pkglist.txt"
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

    info_print "Loaded ${#packages[@]} packages from $pkgfile"
}

package_install() {
    read_pkglist
    packages+=("$kernel" "$kernel"-headers "$microcode")

    info_print "Installing packages..."
    run_cmd RAW -- pacstrap -K /mnt "${packages[@]}"
}


#┌──────────────────────────────  ──────────────────────────────┐
#                      Fstab/Timezone/Locale
#└──────────────────────────────  ──────────────────────────────┘
fstab_file() {
    info_print "Generating fstab file..."
    genfstab -U /mnt >> /mnt/etc/fstab
}

locale_selector() {
    tui_readline locale "Please insert a locale (Empty to use en_US, \"/\" to search locales): "
    case "$locale" in
        '') locale="en_US.UTF-8"
            info_print "$locale will be the default locale."
            state_set "Locale" "$locale"
            return 0;;
        '/') tui_pager_cmd -- sed -E '/^# +|^#$/d;s/^#| *$//g;s/ .*/ (Charset:&)/' /etc/locale.gen | less -M
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
        '') kblayout="us"
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
        loadkeys "$kblayout"
        state_set "Keyboard Layout" "$kblayout"
        return 0
    esac
}


#┌──────────────────────────────  ──────────────────────────────┐
#               Hostname/Users/Bootloader installation
#└──────────────────────────────  ──────────────────────────────┘
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


#┌──────────────────────────────  ──────────────────────────────┐
#                      Main installation process
#└──────────────────────────────  ──────────────────────────────┘

clear

enter_alt
render_splash
render_frame

check_uefi
check_clock_sync

until keyboard_selector; do : ; done

select_disk
until set_luks_passwd; do : ; done
until kernel_selector; do : ; done
until locale_selector; do : ; done
until hostname_selector; do : ; done
until set_usernpasswd; do : ; done
until set_rootpasswd; do : ; done

info_print "Wiping $disk."
wipefs -af "$disk" &>/dev/null
sgdisk -Zo "$disk" &>/dev/null

partition_disk
format_partitions
mount_partitions

info_print "Device: $disk properly partitioned, formated and mounted."

microcode_detector
package_install

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

virt_check

info_print "Configuring /etc/mkinitcpio.conf."
cat > /mnt/etc/mkinitcpio.conf <<EOF
HOOKS=(systemd autodetect microcode keyboard sd-vconsole modconf kms plymouth block sd-encrypt filesystems grub-btrfs-overlayfs)
EOF

info_print "Setting up grub config."
UUID=$(blkid -s UUID -o value "$root_part")
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
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB &>/dev/null

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
mkdir /mnt/etc/pacman.d/hooks
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
services=(reflector.timer snapper-timeline.timer snapper-cleanup.timer btrfs-scrub@-.timer btrfs-scrub@home.timer btrfs-scrub@var-log.timer btrfs-scrub@\\x2esnapshots.timer grub-btrfsd.service bluetooth.service NetworkManager.service)
for service in "${services[@]}"; do
    systemctl enable "$service" --root=/mnt &>/dev/null
done

until aur_helper_selector; do : ; done
install_aur_helper

info_print "Done, you may now wish to reboot (further changes can be done by chrooting into /mnt)."
info_print "Remember to unmount all partitions before rebooting."

exit_alt