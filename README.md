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
```

---

## Repository Structure

```txt
Willow-arch/
├── installer.sh
├── config/
│   ├── defaults.conf
│   └── packages/
├── lib/
│   ├── checks.sh
│   ├── disk.sh
│   ├── luks.sh
│   ├── btrfs.sh
│   ├── packages.sh
│   ├── bootloader.sh
│   ├── system.sh
│   ├── run.sh
│   └── tui.sh
└── README.md
```

---

## Btrfs Layout

The installer creates a LUKS container and formats it as Btrfs.

Current subvolume layout:
```txt
/
├── @            -> /
├── @home        -> /home
├── @root        -> /root
├── @srv         -> /srv
├── @var_log     -> /var/log
├── @snapshots   -> /.snapshots
└── @swap        -> /.swap        # only when swap is enabled
```

Mount options currently used:
```txt
ssd,noatime,compress-force=zstd:3,discard=async
```

---

## Main Features
### Installation Flow

The script currently handles:
- UEFI check
- System clock sync check
- Keyboard layout selection
- Disk selection
- LUKS password setup
- Kernel selection
- Locale selection
- Hostname setup
- User and root password setup
- Disk wipe and partitioning
- Btrfs subvolume creation
- Base package installation
- fstab generation
- mkinitcpio configuration
- GRUB installation
- Snapper configuration
- Pacman configuration
- System service enablement
- AUR helper selection and installation
### Kernel Selection

The installer supports selecting one of:
```txt
linux
linux-lts
linux-zen
linux-hardened
```
### CPU Microcode

The installer attempts to detect CPU vendor and install the matching microcode package:
```txt
intel-ucode
amd-ucode
```
### Services Enabled

The script currently enables services/timers such as:
```txt
NetworkManager.service
bluetooth.service
reflector.timer
snapper-timeline.timer
snapper-cleanup.timer
grub-btrfsd.service
systemd-oomd.service
btrfs scrub timers
```

---
## Usage

Boot into an Arch Linux live environment with internet access.

Clone the repository:
```sh
git clone https://github.com/StringRam/Willow-arch.git
cd Willow-arch
```

Make the installer executable:
```sh
chmod +x installer.sh
```

Run the installer:
```sh
./installer.sh
```

---
## ⚠️ Important Warning

Before running it, make sure that:
- You are in an Arch Linux live ISO.
- You have internet access.
- You have backed up important data.
- You understand what the script does.
- You are comfortable recovering/chrooting manually if something fails.

---
## Contributing

Suggestions, audits, and constructive criticism are welcome.
This project is still highly personal and experimental, so not every contribution will fit the intended direction.

---
## 📜 License

MIT License  
© 2025 Mateo Correa Franco

Inspired by [classy-giraffe](https://github.com/classy-giraffe).
