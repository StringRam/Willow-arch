#!/usr/bin/env bash

# Disk selection and partitioning.

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
