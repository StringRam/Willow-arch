#!/usr/bin/env -S bash -e

# Willow Archlinux installation script for personal use.
# This set up uses a GPT partition table: p1 EFI_System 512Mb
#                                         p2 Linux_root(x86-64)
#   *root_part root partition
#   *@root, @home, @var_log, @snapshots and @swap subvolumes
#   *Manual swap file size
#   *LUKS system encryption
#   *Btrfs filesystem with compression and SSD optimizations
#   *zram for low RAM systems
#
# Credits to classy-giraffe for his script.
# MIT License Copyright (c) 2025 Mateo Correa Franco

set -Eeuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

#┌──────────────────────────────  ──────────────────────────────┐
#                           TUI stuff
#└──────────────────────────────  ──────────────────────────────┘


# ───────────────────────── Terminal helpers ─────────────────────────
if command -v tput >/dev/null 2>&1; then
  BOLD="$(tput bold)"; RESET="$(tput sgr0)"
  CYAN="$(tput setaf 6)"; GREEN="$(tput setaf 2)"
  YELLOW="$(tput setaf 3)"; RED="$(tput setaf 1)"
else
  BOLD=""; RESET=""; CYAN=""; GREEN=""; YELLOW=""; RED=""
fi

esc() { printf "\033[%s" "$1"; }         # raw ANSI
hide_cursor() { esc "?25l"; }
show_cursor() { esc "?25h"; }
move() { tput cup "$1" "$2"; }           # row col

term_cols() { tput cols; }
term_lines() { tput lines; }

#Traslada el tui a pantalla alternativa
enter_alt() { tput smcup; }
exit_alt()  { tput rmcup; }


# ───────────────────────── Drawing primitives ─────────────────────────
# draw_box top left height width title
draw_box() {
  local r="$1" c="$2" h="$3" w="$4" title="${5:-}"
  (( h >= 3 )) || return 0
  (( w >= 4 )) || return 0

  local top="┌$(printf '─%.0s' $(seq 1 $((w-2))))┐"
  local mid="│$(printf ' %.0s' $(seq 1 $((w-2))))│"
  local bot="└$(printf '─%.0s' $(seq 1 $((w-2))))┘"

  move "$r" "$c"; printf "%s" "$top"
  for i in $(seq 1 $((h-2))); do
    move $((r+i)) "$c"; printf "%s" "$mid"
  done
  move $((r+h-1)) "$c"; printf "%s" "$bot"

  if [[ -n "$title" ]]; then
    local t=" $title "
    local max=$((w-4))
    t="${t:0:$max}"
    move "$r" $((c+2))
    printf "%s" "$t"
  fi
}

# print_center row "text"
print_center() {
  local row="$1"; shift
  local text="$*"
  local cols; cols="$(term_cols)"
  local len=${#text}
  local col=$(( (cols - len) / 2 ))
  (( col < 0 )) && col=0
  move "$row" "$col"
  printf "%s" "$text"
}

# print_in_box r c w text  (prints and clears remainder)
print_in_box() {
  local r="$1" c="$2" w="$3"; shift 3
  local text="$*"

  # recortar a w
  text="${text:0:$w}"

  # rellenar con espacios para sobrescribir lo viejo
  local pad=$(( w - ${#text} ))
  (( pad < 0 )) && pad=0

  move "$r" "$c"
  printf "%s%*s" "$text" "$pad" ""
}


repeat_char() {
  local n="$1" ch="$2"
  (( n <= 0 )) && { printf ""; return 0; }
  local s
  printf -v s '%*s' "$n" ''
  printf '%s' "${s// /$ch}"
}

# ───────────────────────── State ─────────────────────────
# Left panel: log buffer (simple scroll)
LOG_MAX=500
declare -a LOG_LINES=()

# Right panel: key/value state
declare -A STATE=()

PROG_TOTAL=8
PROG_STEP=0

sanitize_stream() {
  # - tr: quita carriage-return (progreso tipo “spinner”)
  # - sed: quita secuencias ANSI (colores/progreso)
  tr -d '\r' | sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'
}

run_cmd() { # run_cmd LEVEL "Label" -- cmd args...
  local level="$1"; shift
  local label="$1"; shift
  [[ "${1:-}" == "--" ]] && shift || true

  info_print "⏳ $label"
  state_set "stage" "$label"
  tui_refresh_throttled

  # stdbuf hace line-buffering para ver output en vivo
  # si no existiera, podés quitar "stdbuf -oL -eL"
  stdbuf -oL -eL "$@" 2>&1 | sanitize_stream | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    log_add INFO "$line"
    tui_refresh_throttled
  done

  local rc=${PIPESTATUS[0]}
  if (( rc == 0 )); then
    info_print "✓ $label"
  else
    error_print "✗ $label (exit $rc)"
  fi
  render_content
  return "$rc"
}

log_add() {  # log_add LEVEL "mensaje"
  local level="${1:-INFO}"; shift || true
  local msg="$*"

  LOG_LINES+=("${level}|${msg}")

  if (( ${#LOG_LINES[@]} > LOG_MAX )); then
    LOG_LINES=("${LOG_LINES[@]: -$LOG_MAX}")
  fi
}

TUI_REFRESH_MS=80
_TUI_LAST_REFRESH=0

tui_refresh_throttled() {
  local now
  now=$(date +%s%3N 2>/dev/null || true)
  [[ -z "$now" ]] && { render_content; return 0; }

  if (( now - _TUI_LAST_REFRESH >= TUI_REFRESH_MS )); then
    _TUI_LAST_REFRESH="$now"
    render_content
  fi
}

info_print()  { log_add INFO "$*"; tui_refresh_throttled; }
error_print() { log_add ERR  "$*"; tui_refresh_throttled; }
ask_print()   { log_add ASK  "$*"; tui_refresh_throttled; }


log_prefix() { # log_prefix LEVEL -> imprime prefijo ya coloreado
  local level="$1"
  case "$level" in
    INFO) printf "%s[ o ]%s " "${BOLD}${GREEN}" "${RESET}" ;;
    ASK)  printf "%s[ ? ]%s " "${BOLD}${YELLOW}" "${RESET}" ;;
    ERR)  printf "%s[ x ]%s " "${BOLD}${RED}" "${RESET}" ;;
    *)    printf "%s     %s " "${BOLD}${CYAN}" "${RESET}" ;;
  esac
}

state_set() {
  local k="$1" v="$2"
  STATE["$k"]="$v"
}

progress_set() {
  PROG_STEP="$1"
}

# ───────────────────────── Layout ─────────────────────────
# computed each render (handles resize)
LEFT_R=1 LEFT_C=1 LEFT_H=10 LEFT_W=60
RIGHT_R=1 RIGHT_C=62 RIGHT_H=10 RIGHT_W=20
PROG_R=20

compute_layout() {
  local cols lines
  cols="$(term_cols)"
  lines="$(term_lines)"

  local margin=0      # 0-based: empezamos en (0,0)
  local prog_h=3
  local gap=2

  # Progress box top row (0-based). Debe terminar en lines-1
  PROG_R=$((lines - prog_h))
  (( PROG_R < 0 )) && PROG_R=0

  # Content area height (above progress)
  local content_h=$((PROG_R - margin))
  (( content_h < 8 )) && content_h=8

  local right_w=$(( cols / 3 ))
  (( right_w < 28 )) && right_w=28
  local left_w=$(( cols - right_w - gap - 2*margin ))
  (( left_w < 30 )) && left_w=30

  LEFT_R=$margin
  LEFT_C=$margin
  LEFT_H=$content_h
  LEFT_W=$left_w

  RIGHT_R=$margin
  RIGHT_C=$(( margin + left_w + gap ))
  RIGHT_H=$content_h
  RIGHT_W=$right_w

  # Clamp si se pasa del ancho total
  if (( RIGHT_C + RIGHT_W > cols )); then
    RIGHT_W=$(( cols - RIGHT_C ))
    (( RIGHT_W < 10 )) && RIGHT_W=10
  fi
}

tui_input_pos() {
  compute_layout
  local inner_r=$((LEFT_R + 2))
  local inner_c=$((LEFT_C + 2))
  local inner_w=$((LEFT_W - 4))

  # última línea usable del panel izquierdo (dentro del borde)
  local input_r=$((LEFT_R + LEFT_H - 3))   # -1 borde, -1 última línea, -1 para que no choque
  local input_c=$inner_c
  local input_w=$inner_w

  printf '%s %s %s\n' "$input_r" "$input_c" "$input_w"
}

tui_readline() { # tui_readline varname "Prompt" [default]
  local __var="$1"; shift
  local prompt="$1"; shift
  local def="${1:-}"

  ask_print "$prompt${def:+ (default: $def)}"

  local r c w
  read -r r c w < <(tui_input_pos)

  # pinta una línea de input limpia dentro del panel
  move "$r" "$c"
  printf "%s" "${YELLOW}> ${RESET}"
  printf "%*s" $((w-2)) ""   # limpia resto
  move "$r" $((c+2))

  local ans=""
  IFS= read -r ans || true
  [[ -z "$ans" && -n "$def" ]] && ans="$def"

  printf -v "$__var" '%s' "$ans"

  info_print "→ $prompt: $ans"
}

tui_readsecret() { # tui_readsecret varname "Prompt"
  local __var="$1"; shift
  local prompt="$1"; shift

  ask_print "$prompt"

  local r c w
  read -r r c w < <(tui_input_pos)

  move "$r" "$c"
  printf "%s" "${YELLOW}> ${RESET}"
  printf "%*s" $((w-2)) ""
  move "$r" $((c+2))

  local ans=""
  IFS= read -r -s ans || true
  echo  # importante: baja línea, pero estamos en alt-screen; igual ok

  printf -v "$__var" '%s' "$ans"
  info_print "→ (secret) captured"
}

# ───────────────────────── Screens ─────────────────────────

# ASCII Font: NScript
BANNER_ASCII=$' ,ggg,      gg      ,gg                                                                ,ggg,                                  \n'\
$'dP\"\"Y8a     88     ,8P       ,dPYb, ,dPYb,                                            dP\"\"8I                        ,dPYb,    \n'\
$'Yb, `88     88     d8\'       IP\'`Yb IP\'`Yb                                           dP   88                        IP\'`Yb    \n'\
$' `\"  88     88     88   gg   I8  8I I8  8I                                          dP    88                        I8  8I    \n'\
$'     88     88     88   \"\"   I8  8\' I8  8\'                                         ,8\'    88                        I8  8\'    \n'\
$'     88     88     88   gg   I8 dP  I8 dP    ,ggggg,    gg    gg    gg             d88888888    ,gggggg,    ,gggg,  I8 dPgg,  \n'\
$'     88     88     88   88   I8dP   I8dP    dP\"  \"Y8ggg I8    I8    88bg     __   ,8\"     88    dP\"\"\"\"8I   dP\"  \"Yb I8dP\" \"8I \n'\
$'     Y8    ,88,    8P   88   I8P    I8P    i8\'    ,8I   I8    I8    8I      dP\"  ,8P      Y8   ,8\'    8I  i8\'       I8P    I8 \n'\
$'      Yb,,d8\"\"8b,,dP  _,88,_,d8b,_ ,d8b,_ ,d8,   ,d8\'  ,d8,  ,d8,  ,8I      Yb,_,dP       `8b,,dP     Y8,,d8,_    _,d8     I8,\n'\
$'       \"88\"    \"88\"   8P\"\"Y88P\'\"Y888P\'\"Y88P\"Y8888P\"    P\"\"Y88P\"\"Y88P\"        \"Y8P\"         `Y88P      `Y8P\"\"Y8888PP88P     `Y8\n'

render_splash() {
  clear_screen
  hide_cursor

  local lines cols
  lines="$(term_lines)"
  cols="$(term_cols)"

  # count banner lines
  local banner_lines
  banner_lines=$(printf "%s" "$BANNER_ASCII" | wc -l | tr -d ' ')
  local banner_height=$banner_lines

  # find longest line length (rough centering)
  local maxlen=0
  while IFS= read -r line; do
    ((${#line} > maxlen)) && maxlen=${#line}
  done <<< "$BANNER_ASCII"

  local start_row=$(( (lines - banner_height) / 2 - 2 ))
  (( start_row < 0 )) && start_row=0
  local start_col=$(( (cols - maxlen) / 2 ))
  (( start_col < 0 )) && start_col=0

  local r="$start_row"
  while IFS= read -r line; do
    move "$r" "$start_col"
    printf "%s%s%s" "${BOLD}${GREEN}" "$line" "${RESET}"
    ((r++))
  done <<< "$BANNER_ASCII"

  local msg="Welcome to the Willow-Arch! A somewhat flexible archlinux installation script"
  print_center $((start_row + banner_height + 1)) "${BOLD}${GREEN}${msg}${RESET}"
  print_center $((start_row + banner_height + 3)) "${YELLOW}Press any key to continue...${RESET}"

  # wait key
  read -n1 -r -s || true
}

render_frame() {
  compute_layout
  clear_screen
  hide_cursor

  draw_box "$LEFT_R"  "$LEFT_C"  "$LEFT_H"  "$LEFT_W"  "Prompts"
  draw_box "$RIGHT_R" "$RIGHT_C" "$RIGHT_H" "$RIGHT_W" "Selections"
  draw_box "$PROG_R"  0          3          "$(term_cols)" "Progress"
}

render_log_line() { # row col width "LEVEL|msg"
  local r="$1" c="$2" w="$3" entry="$4"
  local level="${entry%%|*}"
  local msg="${entry#*|}"

  # ancho visible fijo del prefijo: "[ i ] " = 6
  local prefix_visible=6
  local msg_w=$(( w - prefix_visible ))
  (( msg_w < 0 )) && msg_w=0

  msg="${msg:0:$msg_w}"

  move "$r" "$c"
  log_prefix "$level"
  printf "%s" "$msg"

  # padding para limpiar solo dentro del panel
  local pad=$(( w - prefix_visible - ${#msg} ))
  (( pad < 0 )) && pad=0
  printf "%*s" "$pad" ""
}

render_state_line() { # row col width key value
  local r="$1" c="$2" w="$3" key="$4" val="$5"

  # Reservamos "key: " fijo visible = len(key) + 2
  local key_vis=$(( ${#key} + 2 ))
  local val_w=$(( w - key_vis ))
  (( val_w < 0 )) && val_w=0

  val="${val:0:$val_w}"

  move "$r" "$c"
  # key en verde, value normal
  printf "%s%s%s: %s" "${BOLD}${GREEN}" "$key" "${RESET}" "$val"

  local pad=$(( w - key_vis - ${#val} ))
  (( pad < 0 )) && pad=0
  printf "%*s" "$pad" ""
}

render_content() {
  compute_layout

  # ── Left inner area ──
  local inner_r=$((LEFT_R + 2))
  local inner_c=$((LEFT_C + 2))
  local inner_h=$((LEFT_H - 5))
  local inner_w=$((LEFT_W - 4))


  local start=0
  local n=${#LOG_LINES[@]}
  if (( n > inner_h )); then
    start=$((n - inner_h))
  fi

  local row="$inner_r"
  for ((i=0; i<inner_h; i++)); do
    local idx=$((start + i))
    local text=""
    if (( idx < n )); then text="${LOG_LINES[$idx]}"; fi
    local entry=""
    if (( idx < n )); then entry="${LOG_LINES[$idx]}"; else entry="|"; fi
    render_log_line "$row" "$inner_c" "$inner_w" "$entry"
    ((++row))
  done

  # ── Right inner area ──
  local sr=$((RIGHT_R + 2))
  local sc=$((RIGHT_C + 2))
  local sh=$((RIGHT_H - 4))
  local sw=$((RIGHT_W - 4))

  local keys=("${!STATE[@]}")
  IFS=$'\n' keys=($(printf "%s\n" "${keys[@]}" | sort))
  unset IFS

  row="$sr"
  local shown=0
  for k in "${keys[@]}"; do
    (( shown >= sh )) && break
    move "$row" "$sc"
    render_state_line "$row" "$sc" "$sw" "$k" "${STATE[$k]}"
    ((++row)); ((++shown))
  done
  while (( shown < sh )); do
    print_in_box "$row" "$sc" "$sw" ""
    ((++row)); ((++shown))
  done

  # ── Progress inner area ──
  local cols; cols="$(term_cols)"
  local bar_w=$((cols - 2 - 12))
  (( bar_w < 10 )) && bar_w=10

  local filled=$(( PROG_STEP * bar_w / PROG_TOTAL ))
  local empty=$(( bar_w - filled ))

  # Evitar seq aquí (puede fallar y además es caro)
  local bar
  bar="$(repeat_char "$filled" "#")$(repeat_char "$empty" "-")"

  move $((PROG_R + 1)) 2
  printf "%s" "${GREEN}${bar}${RESET}"
  move $((PROG_R + 1)) $((cols - 8))
  printf "%s/%s" "$PROG_STEP" "$PROG_TOTAL"
}

cleanup() {
  show_cursor
  esc "0m"
  exit_alt 2>/dev/null || true
  clear
}

# Para que el trap ERR se herede en funciones y subshells
set -o errtrace

trap cleanup EXIT INT TERM

trap 'show_cursor; esc "0m"; echo; echo "[ERR] line $LINENO: $BASH_COMMAND"; echo "status=$?"; read -n1 -r -s -p "Press a key..." || true' ERR

#┌──────────────────────────────  ──────────────────────────────┐
#                              Checks
#└──────────────────────────────  ──────────────────────────────┘
check_uefi() {
    if [[ -f /sys/firmware/efi/fw_platform_size ]]; then
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
    sync_status=$(timedatectl show -p NTPSynchronized --value)

    if [[ "$sync_status" == "yes" ]]; then
        info_print "System clock is synchronized."
    else
        error_print "Warning: System clock is NOT synchronized."
        info_print "Trying to enable time synchronization..."
        timedatectl set-ntp true
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

# Virtualization check (function).
virt_check () {
    hypervisor=$(systemd-detect-virt)
    case $hypervisor in
        kvm )   info_print "KVM has been detected, setting up guest tools."
                pacstrap /mnt qemu-guest-agent &>/dev/null
                systemctl enable qemu-guest-agent --root=/mnt &>/dev/null
                ;;
        vmware  )   info_print "VMWare Workstation/ESXi has been detected, setting up guest tools."
                    pacstrap /mnt open-vm-tools &>/dev/null
                    systemctl enable vmtoolsd --root=/mnt &>/dev/null
                    systemctl enable vmware-vmblock-fuse --root=/mnt &>/dev/null
                    ;;
        oracle )    info_print "VirtualBox has been detected, setting up guest tools."
                    pacstrap /mnt virtualbox-guest-utils &>/dev/null
                    systemctl enable vboxservice --root=/mnt &>/dev/null
                    ;;
        microsoft ) info_print "Hyper-V has been detected, setting up guest tools."
                    pacstrap /mnt hyperv &>/dev/null
                    systemctl enable hv_fcopy_daemon --root=/mnt &>/dev/null
                    systemctl enable hv_kvp_daemon --root=/mnt &>/dev/null
                    systemctl enable hv_vss_daemon --root=/mnt &>/dev/null
                    ;;
    esac
}


#┌──────────────────────────────  ──────────────────────────────┐
#                Disk partitioning, formatting, etc.
#└──────────────────────────────  ──────────────────────────────┘
select_disk() {
    info_print "Please select a disk for partitioning:"
    tui_readline disk_response "Warning: this will wipe the selected disk. Continue [y/N]?: "
    if ! [[ "${disk_response,,}" =~ ^(yes|y)$ ]]; then
        error_print "Quitting..."
        exit
    fi
    info_print "Available disks:"
    PS3="Please select the number of the corresponding disk (e.g. 1): "
    select entry in $(lsblk -dpnoNAME|grep -P "/dev/sd|nvme|vd|mmcblk");
    do
        disk="$entry"
        info_print "Arch Linux will be installed on the following disk: $disk"
        state_set "Installation Disk" "$disk"
        break
    done
}

# Note: experiment with both fdisk and parted tomorrow to find out if it is necessary to change this implementation
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

set_luks_passwd() {
    tui_readsecret encryption_passwd "Enter a LUKS container password (for security purposes you won't see it): "
    echo
    if [[ -z "$encryption_passwd" ]]; then
        error_print "You must enter a password for the LUKS container. Try again"
        return 1
    fi
    tui_readsecret encryption_passwd2 "Enter your LUKS container password again (for security purposes you won't see it): "
    echo
    if [[ "$encryption_passwd" != "$encryption_passwd2" ]]; then
        error_print "Passwords don't match, try again"
        return 1
    fi

    return 0
}

format_partitions() {
    info_print "Formatting partitions..."
    mkfs.fat -F 32 "$efi_part" &>/dev/null

    echo -n "$encryption_passwd" | cryptsetup luksFormat "$root_part" -d - &>/dev/null
    echo -n "$encryption_passwd" | cryptsetup open "$root_part" cryptroot -d -
    BTRFS="/dev/mapper/cryptroot"
    mkfs.btrfs "$BTRFS" &>/dev/null
    mount "$BTRFS" /mnt

    info_print "Creating Btrfs subvolumes..."
    subvols=(snapshots var_log home root srv)
    for subvol in '' "${subvols[@]}"; do
        btrfs su cr /mnt/@"$subvol" &>/dev/null
    done
    tui_readline swap_size "Please set a swap size[k/m/g/e/p suffix, 0=no swap]: "
    state_set "Swap Size" "$swap_size"
    [ "$swap_size" != "0" ] && btrfs su cr /mnt/@swap &>/dev/null
    umount /mnt
    info_print "Subvolumes created successfully"
}

mount_partitions() {
    info_print "Mounting subvolumes..."
    mountopts="ssd,noatime,compress-force=zstd:3,discard=async"
    mount -o "$mountopts",subvol=@ "$BTRFS" /mnt
    mkdir -p /mnt/{home,root,srv,.snapshots,var/log,boot}
    for subvol in "${subvols[@]:1}"; do
        mount -o "$mountopts",subvol=@"$subvol" "$BTRFS" /mnt/"${subvol//_//}"
    done
    chmod 750 /mnt/root
    mount -o "$mountopts",subvol=@snapshots "$BTRFS" /mnt/.snapshots
    chattr +C /mnt/var/log
    mount "$efi_part" /mnt/boot

    if [[ "$swap_size" != "0" ]]; then
        info_print "Creating swap file..."
        mkdir -p /mnt/.swap
        mount -o compress=zstd,subvol=@swap "$BTRFS" /mnt/.swap
        btrfs filesystem mkswapfile --size "$swap_size" --uuid clear /mnt/.swap/swapfile &>/dev/null
        swapon /mnt/.swap/swapfile
    else
        info_print "No swap file will be created."
    fi
}


#┌──────────────────────────────  ──────────────────────────────┐
#                       Packages installation
#└──────────────────────────────  ──────────────────────────────┘
kernel_selector() {
    info_print "List of kernels:"
    info_print "1) Stable: Vanilla Linux kernel with a few specific Arch Linux patches applied"
    info_print "2) Hardened: A security-focused Linux kernel"
    info_print "3) Longterm: Long-term support (LTS) Linux kernel"
    info_print "4) Zen Kernel: A Linux kernel optimized for desktop usage"
    tui_readline kernel_choice "Please select the number of the corresponding kernel (e.g. 1): " 
    case "$kernel_choice" in
        1 ) kernel="linux"
            state_set "Kernel" "Stable"
            return 0;;
        2 ) kernel="linux-hardened"
            state_set "Kernel" "Hardened"
            return 0;;
        3 ) kernel="linux-lts"
            state_set "Kernel" "Longterm"
            return 0;;
        4 ) kernel="linux-zen"
            state_set "Kernel" "Zen"
            return 0;;
        * ) error_print "You did not enter a valid selection, please try again."
            return 1
    esac
}

microcode_detector() {
    CPU=$(grep vendor_id /proc/cpuinfo)
    if [[ "$CPU" == *"AuthenticAMD"* ]]; then
        info_print "An AMD CPU has been detected, the AMD microcode will be installed."
        microcode="amd-ucode"
    else
        info_print "An Intel CPU has been detected, the Intel microcode will be installed."
        microcode="intel-ucode"
    fi
}

aur_helper_selector() {
    info_print "AUR helpers are used to install packages from the Arch User Repository (AUR)."
    tui_readline aur_helper "Choose an AUR helper to install (yay/paru, leave empty to skip): "
    case "$aur_helper" in
        yay|paru)
            info_print "AUR helper $aur_helper will be installed for user $username."
            state_set "AUR Helper" "$aur_helper"
            ;;
        '')
            info_print "No AUR helper will be installed."
            ;;
        *)
            error_print "Invalid choice. Supported: yay, paru."
            return 1
            ;;
    esac
    return 0
}

install_aur_helper() {
    [[ -z "$aur_helper" || -z "$username" ]] && return
    arch-chroot /mnt /bin/bash <<EOF
sudo -u "$username" bash -c 'cd ~
git clone https://aur.archlinux.org/$aur_helper.git && cd "$aur_helper"
makepkg -si --noconfirm'
EOF
    info_print "AUR helper $aur_helper has been installed for user $username."
}

read_pkglist() {
    local pkgfile="$SCRIPT_DIR/pkglist.txt"
    packages=()

    if [[ ! -r "$pkgfile" ]]; then
        error_print "Package list file not found: $pkgfile"
        exit 1
    fi

    while IFS= read -r line || [[ -n $line ]]; do
        # Skip empty lines and comment lines starting with #
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        packages+=("$line")
    done < "$pkgfile"

    info_print "Loaded ${#packages[@]} packages from $pkgfile"
}

package_install() {
    read_pkglist
    packages+=("$kernel" "$kernel"-headers "$microcode")

    info_print "Installing packages: ${packages[*]}"
    pacstrap -K /mnt "${packages[@]}" &>/dev/null
}


#┌──────────────────────────────  ──────────────────────────────┐
#                      Fstab/Timezone/Locale
#└──────────────────────────────  ──────────────────────────────┘
fstab_file() {
    info_print "Generating fstab file..."
    genfstab -U /mnt >> /mnt/etc/fstab
}

locale_selector() {
    tui_readline locale "Please insert the locale you use (format: xx_XX. Enter empty to use en_US, or \"/\" to search locales): "
    case "$locale" in
        '') locale="en_US.UTF-8"
            info_print "$locale will be the default locale."
            state_set "Locale" "$locale"
            return 0;;
        '/') sed -E '/^# +|^#$/d;s/^#| *$//g;s/ .*/ (Charset:&)/' /etc/locale.gen | less -M
                clear
                return 1;;
        *)  if ! grep -q "^#\?$(sed 's/[].*[]/\\&/g' <<< "$locale") " /etc/locale.gen; then
                error_print "The specified locale doesn't exist or isn't supported."
                return 1
            fi
            state_set "Locale" "$locale"
            return 0
    esac
}

keyboard_selector() {
    tui_readline kblayout "Please insert the keyboard layout to use in console (enter empty to use US, or \"/\" to look up for keyboard layouts): "
    case "$kblayout" in
        '') kblayout="us"
            info_print "The standard US keyboard layout will be used."
            return 0;;
        '/') localectl list-keymaps
             clear
             return 1;;
        *) if ! localectl list-keymaps | grep -Fxq "$kblayout"; then
               error_print "The specified keymap doesn't exist."
               return 1
           fi
        info_print "Changing console layout to $kblayout."
        loadkeys "$kblayout"
        state_set "Keyboard Layout" "$kblayout"
        return 0
    esac
}


#┌──────────────────────────────  ──────────────────────────────┐
#               Hostname/Users/Bootloader installation
#└──────────────────────────────  ──────────────────────────────┘
hostname_selector() {
    tui_readline hostname "Please enter the hostname (it must contain from 1 to 63 characters, using only lowercase a to z, 0 to 9): "
    if [[ -z "$hostname" ]]; then
        echo
        error_print "You need to enter a hostname in order to continue."
        return 1
    fi
    state_set "Hostname" "$hostname"
    return 0
}

set_usernpasswd() {
    tui_readline username "Please enter name for a user account: "
    if [[ -z "$username" ]]; then
        return 1
    fi
    state_set "Username" "$username"
    tui_readsecret userpasswd "Please enter a password for $username (you're not going to see the password): "
    echo
    if [[ -z "$userpasswd" ]]; then
        error_print "You need to enter a password for $username, please try again."
        return 1
    fi
    tui_readsecret userpasswd2 "Please enter the password again (you're not going to see it): " 
    echo
    if [[ "$userpasswd" != "$userpasswd2" ]]; then
        error_print "Passwords don't match, please try again."
        return 1
    fi
    return 0
}

set_rootpasswd() {
    tui_readsecret rootpasswd "Please enter a password for the root user (you're not going to see it): "
    echo
    if [[ -z "$rootpasswd" ]]; then
        error_print "You need to enter a password for the root user, please try again."
        return 1
    fi
    tui_readsecret rootpasswd2 "Please enter the password again (you're not going to see it): " 
    echo
    if [[ "$rootpasswd" != "$rootpasswd2" ]]; then
        error_print "Passwords don't match, please try again."
        return 1
    fi
    return 0
}


#┌──────────────────────────────  ──────────────────────────────┐
#                      Main installation process
#└──────────────────────────────  ──────────────────────────────┘

enter_alt
render_splash
render_frame

check_uefi
check_clock_sync

until keyboard_selector; do : ; done

select_disk
until set_luks_passwd; do : ; done
until kernel_selector; do : ; done
until locale_selector; do : ; done
until hostname_selector; do : ; done
until set_usernpasswd; do : ; done
until set_rootpasswd; do : ; done

info_print "Wiping $disk."
wipefs -af "$disk" &>/dev/null
sgdisk -Zo "$disk" &>/dev/null

partition_disk
format_partitions
mount_partitions

info_print "Device: $disk properly partitioned, formated and mounted."

microcode_detector
package_install

echo "$hostname" > /mnt/etc/hostname

fstab_file

sed -i "/^#$locale/s/^#//" /mnt/etc/locale.gen
echo "LANG=$locale" > /mnt/etc/locale.conf
echo "KEYMAP=$kblayout" > /mnt/etc/vconsole.conf

info_print "Setting hosts file."
cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain   $hostname
EOF

virt_check

info_print "Configuring /etc/mkinitcpio.conf."
cat > /mnt/etc/mkinitcpio.conf <<EOF
HOOKS=(systemd autodetect microcode keyboard sd-vconsole modconf kms plymouth block sd-encrypt filesystems grub-btrfs-overlayfs)
EOF

info_print "Setting up grub config."
UUID=$(blkid -s UUID -o value "$root_part")
sed -i "\,^GRUB_CMDLINE_LINUX=\"\",s,\",&rd.luks.name=$UUID=cryptroot root=$BTRFS," /mnt/etc/default/grub

info_print "Configuring the system (timezone, system clock, initramfs, Snapper, GRUB)."
arch-chroot /mnt /bin/bash -e <<EOF

    # Setting up timezone.
    ln -sf /usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone) /etc/localtime &>/dev/null

    # Setting up clock.
    hwclock --systohc

    # Generating locales.
    locale-gen &>/dev/null

    # Generating a new initramfs.
    mkinitcpio -P &>/dev/null

    # Snapper configuration.
    umount /.snapshots
    rm -r /.snapshots
    snapper --no-dbus -c root create-config /
    btrfs subvolume delete /.snapshots &>/dev/null
    mkdir /.snapshots
    mount -a &>/dev/null
    chmod 750 /.snapshots

    # Installing GRUB.
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB &>/dev/null

    # Creating grub config file.
    grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null

EOF

info_print "Setting root password."
echo "root:$rootpasswd" | arch-chroot /mnt chpasswd

if [[ -n "$username" ]]; then
    echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/wheel
    info_print "Adding the user $username to the system with root privilege."
    arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$username"
    info_print "Setting user password for $username."
    echo "$username:$userpasswd" | arch-chroot /mnt chpasswd
fi

info_print "Configuring /boot backup when pacman transactions are made."
mkdir /mnt/etc/pacman.d/hooks
cat > /mnt/etc/pacman.d/hooks/50-bootbackup.hook <<EOF
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Path
Target = usr/lib/modules/*/vmlinuz

[Action]
Depends = rsync
Description = Backing up /boot...
When = PostTransaction
Exec = /usr/bin/rsync -a --delete /boot /.bootbackup
EOF

info_print "Enabling colours and parallel downloads for pacman."
sed -Ei 's/^#(Color)$/\1/;s/^#(ParallelDownloads).*/\1 = 10/' /mnt/etc/pacman.conf

info_print "Enabling multilib repository in pacman.conf."
sed -i "/^#\[multilib\]/,/^$/{s/^#//}" /mnt/etc/pacman.conf
arch-chroot /mnt pacman -Sy --noconfirm &>/dev/null

info_print "Enabling Reflector, automatic snapshots, BTRFS scrubbing, bluetooth and NetworkManager services."
services=(reflector.timer snapper-timeline.timer snapper-cleanup.timer btrfs-scrub@-.timer btrfs-scrub@home.timer btrfs-scrub@var-log.timer btrfs-scrub@\\x2esnapshots.timer grub-btrfsd.service bluetooth.service NetworkManager.service)
for service in "${services[@]}"; do
    systemctl enable "$service" --root=/mnt &>/dev/null
done

until aur_helper_selector; do : ; done
install_aur_helper

info_print "Done, you may now wish to reboot (further changes can be done by chrooting into /mnt)."
info_print "Remember to unmount all partitions before rebooting."

exit_alt