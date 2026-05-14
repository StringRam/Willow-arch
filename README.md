![📦 Downloads](https://img.shields.io/github/downloads/StringRam/Willow-arch/total?label=📦%20Downloads)
![📄 License](https://img.shields.io/github/license/StringRam/Willow-arch?label=📄%20License)
![⭐ Stars](https://img.shields.io/github/stars/StringRam/Willow-arch?label=⭐%20Stars)

# 🌿 Willow-Arch

Willow-Arch is a personal Arch Linux installation script designed to create the base system used by my Hyprland + Quickshell desktop environment.

It is not a general-purpose Arch installer yet.  
It is currently a personal, opinionated installation flow with an interactive terminal UI, full-disk encryption, Btrfs subvolumes, Snapper, GRUB, and a small set of base packages.

> ⚠️ This script partitions and formats disks. Read the code before running it.

Known limitations:
- There is no dry-run mode yet.
- There is no persistent install log yet.

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
