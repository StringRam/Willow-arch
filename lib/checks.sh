#!/usr/bin/env bash

# Environment and pre-install checks.

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
