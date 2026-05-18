#!/usr/bin/env bash

# Environment and pre-install checks.

check_uefi() {
    if [[ -f /sys/firmware/efi/fw_platform_size ]]; then
        local fw_size
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
    local sync_status
    sync_status=$(timedatectl show -p NTPSynchronized --value)

    if [[ "$sync_status" == "yes" ]]; then
        info_print "System clock is synchronized."
    else
        error_print "Warning: System clock is NOT synchronized."
        info_print "Trying to enable time synchronization..."
        run_quiet CHECK -- timedatectl set-ntp true
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

virt_check() {
    local hypervisor
    hypervisor=$(systemd-detect-virt)
    case $hypervisor in
        kvm )   info_print "KVM has been detected, setting up guest tools."
                run_cmd RAW -- pacstrap /mnt qemu-guest-agent
                run_quiet SYS -- systemctl enable qemu-guest-agent --root=/mnt
                ;;
        vmware  )   info_print "VMWare Workstation/ESXi has been detected, setting up guest tools."
                    run_cmd RAW -- pacstrap /mnt open-vm-tools
                    run_quiet SYS -- systemctl enable vmtoolsd --root=/mnt
                    run_quiet SYS -- systemctl enable vmware-vmblock-fuse --root=/mnt
                    ;;
        oracle )    info_print "VirtualBox has been detected, setting up guest tools."
                    run_cmd RAW -- pacstrap /mnt virtualbox-guest-utils
                    run_quiet SYS -- systemctl enable vboxservice --root=/mnt
                    ;;
        microsoft ) info_print "Hyper-V has been detected, setting up guest tools."
                    run_cmd RAW -- pacstrap /mnt hyperv
                    run_quiet SYS -- systemctl enable hv_fcopy_daemon --root=/mnt
                    run_quiet SYS -- systemctl enable hv_kvp_daemon --root=/mnt
                    run_quiet SYS -- systemctl enable hv_vss_daemon --root=/mnt
                    ;;
    esac
}
