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
have_tty() { [[ -t 0 && -t 1 ]]; }

enter_alt() {
  have_tty || return 0
  tput smcup >/dev/null 2>&1 || return 0
}

exit_alt() {
  have_tty || return 0
  tput rmcup >/dev/null 2>&1 || return 0
}



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
raw_print()   { log_add RAW  "$*"; tui_refresh_throttled; }

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

  render_content

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

tui_suspend() {
  show_cursor
  exit_alt 2>/dev/null || true
}

tui_resume() {
  enter_alt
  render_frame
  render_content
}

tui_pager_cmd() { # tui_pager_cmd -- cmd args...
  [[ "${1:-}" == "--" ]] && shift || true
  local tmp
  tmp="$(mktemp -t willowcmd.XXXXXX)"

  # Capturá TODO sin spamear el render
  stdbuf -oL -eL "$@" 2>&1 | sanitize_stream > "$tmp"
  local rc=${PIPESTATUS[0]}

  tui_suspend
  less -M "$tmp"
  tui_resume

  rm -f "$tmp"
  return "$rc"
}

tui_pause() { # enter to continue
  local msg="${1:-Press Enter to continue...}"
  ask_print "$msg"
  local _
  IFS= read -r _ || true
}

tui_select_from_list() { # tui_select_from_list outvar "Prompt" items...
  local __var="$1"; shift
  local prompt="$1"; shift
  local -a items=("$@")

  (( ${#items[@]} > 0 )) || { error_print "No options available."; return 1; }

  info_print "$prompt"
  local i
  for i in "${!items[@]}"; do
    raw_print "  $((i+1))) ${items[i]}"
  done

  local idx=""
  while true; do
    tui_readline idx "Choose [1-${#items[@]}]:" "1"
    [[ "$idx" =~ ^[0-9]+$ ]] || { error_print "Invalid number."; continue; }
    (( idx >= 1 && idx <= ${#items[@]} )) || { error_print "Out of range."; continue; }
    printf -v "$__var" '%s' "${items[idx-1]}"
    return 0
  done
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
  clear
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

  # limpiar línea de input (reservada)
  local in_r=$((LEFT_R + LEFT_H - 3))
  local in_c=$((LEFT_C + 2))
  local in_w=$((LEFT_W - 4))
  print_in_box "$in_r" "$in_c" "$in_w" ""

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
