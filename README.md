# 🌿 Willow-Arch

*A flexible and elegant Arch Linux installation script — built for power users who value automation, reproducibility, and clean systems.*

---

## 🚀 Features

🧠 **Smart & Automated**
- Verifies UEFI boot
- Enables NTP and syncs clock
- Detects microcode for Intel/AMD CPUs
- Custom kernel selection: `linux`, `lts`, `zen`, or `hardened`

💾 **Disk Setup**
- Full-disk **LUKS encryption**
- GPT partition table
- Btrfs filesystem with pre-defined subvolumes:
  - `@` (root)
  - `@home`
  - `@var_log`
  - `@snapshots`
  - `@swap`

📦 **Modular Package Installation**
- Base system + additional packages from `pkglist.txt`
- Configurable via plain text

🔧 **Post-Install Configuration**
- Sets locale, timezone, hostname, and users
- Installs and configures GRUB for encrypted boot
- Enables systemd services:
  - `snapper`, `reflector`, `btrfs scrub`, `grub-btrfs`

🎨 **Readable CLI Output**
- Color-coded messages
- Section titles and separators
- Optional quiet mode for automation

---

## 📁 Subvolume Layout

```plaintext
/
├── @               → /
├── @home           → /home
├── @var_log        → /var/log
├── @snapshots      → /.snapshots
└── @swap           → /swap
