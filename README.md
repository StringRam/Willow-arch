![📦 Downloads](https://img.shields.io/github/downloads/StringRam/Willow-arch/total?label=📦%20Downloads)
![📄 License](https://img.shields.io/github/license/StringRam/Willow-arch?label=📄%20License)
![⭐ Stars](https://img.shields.io/github/stars/StringRam/Willow-arch?label=⭐%20Stars)


# 🌿 Willow-Arch

*A flexible and simple Arch Linux installation script. Made for personal and public use.*


## Features

### Automated Setup
- Verifies UEFI boot  
- Enables NTP and syncs system clock  
- Detects CPU microcode (Intel/AMD)  
- Supports kernel selection: `linux`, `lts`, `zen`, or `hardened`

### Disk Layout & Encryption
- Full disk encryption with LUKS  
- GPT partitioning scheme  
- Btrfs filesystem with subvolumes:
  - `@` for root
  - `@home` for user files
  - `@var_log` for logs
  - `@snapshots` for Snapper
  - `@swap` for swapfile

### Modular Package Installation
- Installs base system  
- Installs additional packages from `pkglist.txt`  
- Fully configurable using plain text

### Post-Install Automation
- Configures locale, timezone, hostname, and user  
- Installs and configures GRUB for encrypted boot  
- Enables systemd services:
  - `snapper`
  - `reflector`
  - `btrfs scrub`
  - `grub-btrfs`

### UX & Output
- Color-coded output  
- Clear section titles and separators


## 🗂️ Btrfs Subvolume Layout

```plaintext
/
├── @               → /
├── @home           → /home
├── @var_log        → /var/log
├── @srv            → /srv
├── @snapshots      → /.snapshots
└── @swap           → /swap
```

## Usage

### 1. Clone the Repository
```
git clone https://github.com/StringRam/Willow-arch.git
cd Willow-arch
```
### 2.Make the script executable
```
chmod +x WillowArch.sh
```
### 3.Run the script
```
./WillowArch.sh
```
You'll be guided through:

- Disk selection and formatting  
- Full-disk encryption  
- Kernel and package selection  
- Localization and user setup

Please check the [arch wiki](https://wiki.archlinux.org) out for more info.

> ⚠️ **Make sure you're running from a live Arch Linux environment with internet access.**


## Contributions

Contributions, suggestions, and constructive feedback are welcome.  
Feel free to open an issue or pull request.


## 📜 License

MIT License  
© 2025 Mateo Correa Franco

> Inspired by [classy-giraffe](https://github.com/classy-giraffe)
