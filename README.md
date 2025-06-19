# 🌿 Willow-Arch 🌿

*A flexible and simple Arch Linux installation script. Built for public and personal use.*

---

## Features:

##┌──────────────────────────────  ──────────────────────────────┐
##                       **Smart & Automated**
##└──────────────────────────────  ──────────────────────────────┘
- Verifies UEFI boot
- Enables NTP and syncs clock
- Detects microcode for Intel/AMD CPUs
- Custom kernel selection: `linux`, `lts`, `zen`, or `hardened`

##┌──────────────────────────────  ──────────────────────────────┐
##                          **Disk Setup**
##└──────────────────────────────  ──────────────────────────────┘
- Full-disk **LUKS encryption**
- GPT partition table
- Btrfs filesystem with pre-defined subvolumes:
  - `@` (root)
  - `@home`
  - `@var_log`
  - `@snapshots`
  - `@swap`

##┌──────────────────────────────  ──────────────────────────────┐
##                 **Modular package installation**
##└──────────────────────────────  ──────────────────────────────┘
- Base system + additional packages from `pkglist.txt`
- Configurable via plain text

##┌──────────────────────────────  ──────────────────────────────┐
##                     **Post install config**
##└──────────────────────────────  ──────────────────────────────┘
- Sets locale, timezone, hostname, and users
- Installs and configures GRUB for encrypted boot
- Enables systemd services:
  - `snapper`, `reflector`, `btrfs scrub`, `grub-btrfs`

##┌──────────────────────────────  ──────────────────────────────┐
##                         **Easy to read**
##└──────────────────────────────  ──────────────────────────────┘
- Color-coded messages
- Section titles and separators

---

##┌──────────────────────────────  ──────────────────────────────┐
##                       **Subvolume layout**
##└──────────────────────────────  ──────────────────────────────┘

```plaintext
/
├── @               → /
├── @home           → /home
├── @var_log        → /var/log
├── @snapshots      → /.snapshots
└── @swap           → /swap

MIT License
© 2025 Mateo Correa Franco
*Credits to classy-giraffe for inspiration.*
