![📦 Downloads](https://img.shields.io/github/downloads/StringRam/Willow-arch/total?label=📦%20Downloads)
![📄 License](https://img.shields.io/github/license/StringRam/Willow-arch?label=📄%20License)
![⭐ Stars](https://img.shields.io/github/stars/StringRam/Willow-arch?label=⭐%20Stars)


# 🌿 Willow-Arch

*A flexible and minimalist Arch Linux installation script — tailored for personal and public use.*

---

## Features

### ⚙️ Automated Setup
- Verifies UEFI boot  
- Enables NTP and syncs system clock  
- Detects CPU microcode (Intel/AMD)  
- Supports kernel selection: `linux`, `lts`, `zen`, or `hardened`

### 💾 Disk Layout & Encryption
- Full disk encryption with LUKS  
- GPT partitioning scheme  
- Btrfs filesystem with subvolumes:
  - `@` for root
  - `@home` for user files
  - `@var_log` for logs
  - `@snapshots` for Snapper
  - `@swap` for swapfile

### 📦 Modular Package Installation
- Installs base system  
- Installs additional packages from `pkglist.txt`  
- Fully configurable using plain text

### 🧩 Post-Install Automation
- Configures locale, timezone, hostname, and user  
- Installs and configures GRUB for encrypted boot  
- Enables systemd services:
  - `snapper`
  - `reflector`
  - `btrfs scrub`
  - `grub-btrfs`

### 🎨 UX & Output
- Color-coded output  
- Clear section titles and separators

---

## 🧪 Work In Progress
- Gaming-oriented setup profiles  
- Dotfile sync and integration  

---

## 🗂️ Btrfs Subvolume Layout

```plaintext
/
├── @               → /
├── @home           → /home
├── @var_log        → /var/log
├── @snapshots      → /.snapshots
└── @swap           → /swap
```

## 🚀 Usage

### 1. Clone the Repository
```bash
git clone https://github.com/StringRam/Willow-arch.git
cd Willow-arch
```
### 2.Make the script executable
```bash
chmod +x willow.sh
```
### 3.Run the script
```bash
./willow.sh
```
You'll be guided through:

- Disk selection and formatting  
- Optional full-disk encryption  
- Kernel and package selection  
- Localization and user setup  

> ⚠️ **Make sure you're running from a live Arch Linux environment with internet access.**

---

## 🤝 Contributions

Contributions, suggestions, and constructive feedback are welcome.  
Feel free to open an issue or pull request.

---

## 📜 License

MIT License  
© 2025 Mateo Correa Franco

> Inspired by [classy-giraffe](https://github.com/classy-giraffe)
