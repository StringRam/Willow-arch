![📦 Downloads](https://img.shields.io/github/downloads/StringRam/Willow-arch/total?label=📦%20Downloads)
![📄 License](https://img.shields.io/github/license/StringRam/Willow-arch?label=📄%20License)
![⭐ Stars](https://img.shields.io/github/stars/StringRam/Willow-arch?label=⭐%20Stars)

# 🌿 Willow-Arch

Willow-Arch is a personal Arch Linux installation script designed to create the base system used by my Hyprland + Quickshell desktop environment.

It is not a general-purpose Arch installer yet.  
It is currently a personal, opinionated installation flow with an interactive terminal UI, full-disk encryption, Btrfs subvolumes, Snapper, GRUB, and a small set of base packages.

> ⚠️ This script partitions and formats disks. Read the code before running it.

---

## Current Status

**Stage:** experimental / personal-use installer

The script works as an automated base installer, but it is still being developed and audited. Some parts are intentionally opinionated and not yet fully configurable.

Known limitations:

- The installer is currently a single large orchestration script.
- Disk partition paths are derived from partition labels.
- Timezone is detected automatically through an external web request.
- There is no dry-run mode yet.
- There is no persistent install log yet.
- The TUI exists, but the installer flow still needs cleanup and modularization.

---

## What It Installs

Willow-Arch sets up a minimal Arch system with:

- UEFI boot
- GPT partitioning
- LUKS encryption
- Btrfs filesystem
- Btrfs subvolumes
- Optional swapfile
- Snapper snapshots
- GRUB encrypted boot
- Reflector
- NetworkManager
- Bluetooth
- zram
- Optional AUR helper installation

The installed package set is defined in:

```txt
pkglist.txt
