![](https://img.shields.io/github/license/StringRam/Willow-arch?label=License)
![](https://img.shields.io/github/stars/StringRam/Willow-arch?label=Stars)
![](https://img.shields.io/github/forks/StringRam/Willow-arch?label=Forks)

# 🌿 Willow-Arch 🌿

*A flexible and simple Arch Linux installation script. Built for public and personal use.*

---

## Features:

### Smart & Automated
- Verifies UEFI boot  
- Enables NTP and syncs clock  
- Detects microcode for Intel/AMD CPUs  
- Custom kernel selection: `linux`, `lts`, `zen`, or `hardened`

### Disk Setup
- Full-disk **LUKS encryption**
- GPT partition table  
- Btrfs filesystem with pre-defined subvolumes:
  - `@` (root)
  - `@home`
  - `@var_log`
  - `@snapshots`
  - `@swap`

### Modular Package Installation
- Installs the base system  
- Reads and installs packages from `pkglist.txt`  
- Fully configurable via plain text

### Post Install Config
- Sets locale, timezone, hostname, and users  
- Installs and configures GRUB for encrypted boot  
- Enables systemd services:
  - `snapper`, `reflector`, `btrfs scrub`, `grub-btrfs`

### Easy to Read
- Color-coded output  
- Clear section titles and separators  

### Currently WIP:
- Gaming specific configurations
- Dotfiles integration
---

## Subvolume Layout

```plaintext
/
├── @               → /
├── @home           → /home
├── @var_log        → /var/log
├── @snapshots      → /.snapshots
└── @swap           → /swa
```

MIT License
© 2025 Mateo Correa Franco
*Credits to classy-giraffe for inspiration.*
