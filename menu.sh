#!/usr/bin/env bash
# Xray Management Menu (VMess/VLESS/Trojan/SS/HTTP/SOCKS)
# Versi 3.6 (Fix: Hide System Users in Routing)

# Gunakan set +e agar script tidak mati jika ada command error (penting untuk ux)
set +e

# ====== Lokasi berkas penting ======
CONFIG="/usr/local/etc/xray/config.json"
NGINX_CONF="/etc/nginx/conf.d/xray.conf"
DOMAIN_FILE="/usr/local/etc/xray/domain"
HOSTS_FILE="/usr/local/etc/xray/added_hosts.txt"
ACME_BIN="$HOME/.acme.sh/acme.sh"
ASSET_DIR="/usr/local/etc/xray"
ACCOUNTS_DIR="$ASSET_DIR/accounts"

# ====== Konfigurasi Cloudflare & Domain Tersedia ======
CF_TOKEN="qz31v4icXAb7593V_cafEHPEvskw5V8rWES95AZx"
AVAILABLE_DOMAINS=("vip01.qzz.io" "vip02.qzz.io" "vip03.qzz.io" "vip04.qzz.io")

# ======================================================================
# --- Variabel Warna ---
# ======================================================================
ESC="\033["
RESET="${ESC}0m"
BLACK="${ESC}30m"
RED="${ESC}31m"
GREEN="${ESC}32m"
YELLOW="${ESC}33m"
BLUE="${ESC}34m"
MAGENTA="${ESC}35m"
CYAN="${ESC}36m"
WHITE="${ESC}37m"

B_BLACK="${ESC}1;30m"
B_RED="${ESC}1;31m"
B_GREEN="${ESC}1;32m"
B_YELLOW="${ESC}1;33m"
B_BLUE="${ESC}1;34m"
B_MAGENTA="${ESC}1;35m"
B_CYAN="${ESC}1;36m"
B_WHITE="${ESC}1;37m"

# ======================================================================
# --- Fungsi UI / Helper ---
# ======================================================================
COLS=$(tput cols 2>/dev/null || echo 80)

print_line() {
    local char="$1"
    local color="$2"
    printf "${color}%*s${RESET}\n" "$COLS" "" | tr ' ' "$char"
}

print_center() {
    local text="$1"
    local color="$2"
    local padding=$(( (COLS - ${#text} - 2) / 2 ))
    [ $padding -lt 0 ] && $padding=0
    printf "${color}%*s %s %*s${RESET}\n" "$padding" "" "$text" "$padding" ""
}

print_header() {
    local text=":: $1 ::"
    echo -e "\n" # Spasi
    print_center "$text" "$B_CYAN"
    print_line "-" "$CYAN"
}

print_banner() {
    clear
    local title="Manajemen Xray-core"
    # --- PERUBAHAN VERSI ---
    local subtitle="Versi UI 3.6 (Xray Multi Protokol + Routing WARP)"
    
    print_line "=" "$B_GREEN"
    print_center "$title" "$B_GREEN"
    print_center "$subtitle" "$GREEN"
    print_line "=" "$B_GREEN"
    echo "" # Spasi
}

# --- Fungsi Logging Baru ---
print_info() { echo -e "${B_GREEN}[ i ]${RESET} $1"; }
print_warn() { echo -e "${B_YELLOW}[ ! ]${RESET} $1"; }
print_error() { echo -e "${B_RED}[ ✖ ]${RESET} $1"; }

# --- Fungsi Menu Baru ---
print_menu_option() {
    echo -e "  ${B_GREEN}$1${RESET}  $2"
}

print_menu_prompt() {
    local prompt_text="${1:-Pilih Opsi}"
    local var_name="$2"
    echo -e "\n  ${B_WHITE}${prompt_text}:${RESET}"
    printf "  ${B_YELLOW}>${RESET} "
    read "$var_name"
}

# --- Fungsi Pause Baru ---
pause_for_enter() {
    echo -e "\n  ${B_YELLOW}Tekan [Enter] untuk kembali...${RESET}"
    read -r
}

# ======================================================================
# --- FUNGSI SPINNER BARU (diimpor dari installer) ---
# ======================================================================
run_task() {
    local msg=$1
    shift
    local cmd=$@
    local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0
    # Buat file log sementara
    local tmp_log
    tmp_log=$(mktemp)
    
    tput civis # Sembunyikan kursor
    echo -n -e "${B_BLUE}[ → ]${RESET} $msg... "
    
    # Jalankan di background, log ke file sementara
    eval "$cmd" > "$tmp_log" 2>&1 &
    local pid=$!

    # Loop spinner
    while ps -p $pid > /dev/null; do
        i=$(( (i+1) % ${#chars} ))
        echo -n -e "${B_BLUE}${chars:$i:1}${RESET}"
        sleep 0.1
        echo -n -e "\b"
    done
    
    wait $pid
    local EXIT_CODE=$?
    tput cnorm # Tampilkan kursor kembali

    if [ $EXIT_CODE -eq 0 ]; then
        echo -e "${B_GREEN}✔${RESET} ${GREEN}OK${RESET}"
        rm -f "$tmp_log" # Hapus log sukses
        return 0 # Sukses
    else
        echo -e "${B_RED}✖${RESET} ${RED}FAIL${RESET}"
        print_error "Gagal: $msg."
        # Tampilkan isi log error
        echo -e "${RED}--- Output Error (dari $tmp_log) ---${RESET}\n"
        cat "$tmp_log"
        echo -e "\n${RED}-----------------------------------${RESET}"
        rm -f "$tmp_log" # Hapus log setelah ditampilkan
        return 1 # Gagal
    fi
}
# ======================================================================
# --- AKHIR FUNGSI SPINNER ---
# ======================================================================

# ======================================================================
# --- FUNGSI HEADER INFO SISTEM (DIPERBARUI) ---
# ======================================================================
get_service_status() {
    local service="$1"
    if systemctl is-active --quiet "$service"; then
        echo -e "${B_GREEN}● Aktif${RESET}"
    else
        echo -e "${B_RED}○ Nonaktif${RESET}"
    fi
}

# --- PERBAIKAN: Fungsi ambil trafik (gabungan in/out) ---
get_xray_total_traffic() {
    local _XRAY_BIN="/usr/local/bin/xray"
    # Port 10000 sesuai config installer
    local _XRAY_API_SERVER="127.0.0.1:10000" 
    
    if [[ ! -x "$_XRAY_BIN" ]]; then
        echo -e "${B_RED}Xray-bin T/A${RESET}"
        return
    fi

    # Panggil API
    local APIDATA
    APIDATA=$("$_XRAY_BIN" api statsquery --server="$_XRAY_API_SERVER" 2>/dev/null | \
        awk '
        {
            if (match($1, /"name":/)) {
                f=1; gsub(/^"|link"|,$/, "", $2);
                split($2, p,  ">>>");
                printf "%s:%s->%s\t", p[1],p[2],p[4];
            }
            else if (match($1, /"value":/) && f){
              f = 0;
              gsub(/"/, "", $2);
              printf "%.0f\n", $2;
            }
            else if (match($0, /}/) && f) { f = 0; print 0; }
        }')
    
    if [[ -z "$APIDATA" ]]; then
        echo -e "${B_RED}N/A (API Gagal/Nonaktif)${RESET}"
        return
    fi

    # --- PERUBAHAN: Kalkulasi gabungan inbound + outbound ---
    local TOTAL_UP=$(echo "$APIDATA" | grep -E "^(inbound|outbound)" | grep -- '->up' | awk '{sum+=$2} END {printf "%.0f", sum}')
    local TOTAL_DOWN=$(echo "$APIDATA" | grep -E "^(inbound|outbound)" | grep -- '->down' | awk '{sum+=$2} END {printf "%.0f", sum}')
    # --- AKHIR PERUBAHAN ---

    # Format ke human-readable
    local UP_FMT=$(echo "$TOTAL_UP" | numfmt --suffix=B --to=iec)
    local DOWN_FMT=$(echo "$TOTAL_DOWN" | numfmt --suffix=B --to=iec)

    echo -e "${B_GREEN}▲ $UP_FMT${RESET} / ${B_RED}▼ $DOWN_FMT${RESET}"
}
# --- AKHIR FUNGSI TRAFIK ---


print_system_header() {
    # 1. Get OS
    local os_info=""
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        os_info="$PRETTY_NAME"
    else
        os_info="Linux (unknown)"
    fi
    
    # 2. Get Uptime
    local uptime_val=$(uptime -p | sed 's/^up //')

    # 3. Get RAM
    local ram_info=$(free -m | awk '/^Mem:/ {printf "%d/%d MB", $3, $2}')

    # 4. Get CPU Load
    local cpu_load=$(uptime | awk -F'load average: ' '{print $2}' | cut -d',' -f1)

    # 5. Get IP Info (cache hasil untuk 1 jam)
    local ip_cache_file="/tmp/xray_menu_ipinfo.cache"
    local ip_info_json=""
    
    if [ -f "$ip_cache_file" ] && [ $(find "$ip_cache_file" -mmin -60 | wc -l) -gt 0 ]; then
        ip_info_json=$(cat "$ip_cache_file")
    else
        ip_info_json=$(curl -s ipinfo.io)
        if [ $? -eq 0 ] && [ -n "$ip_info_json" ]; then
            echo "$ip_info_json" > "$ip_cache_file"
        else
            ip_info_json="{\"ip\":\"?\",\"org\":\"?\",\"country\":\"?\"}" # Fallback
        fi
    fi
    
    local ip_val=$(echo "$ip_info_json" | jq -r '.ip // "?"')
    local isp_val_raw=$(echo "$ip_info_json" | jq -r '.org // "?"')
    local isp_val=$(echo "$isp_val_raw" | sed 's/^AS[0-9]\+ //')
    local country_val=$(echo "$ip_info_json" | jq -r '.country // "?"')

    # 6. Get Service Status
    local xray_status=$(get_service_status xray)
    local nginx_status=$(get_service_status nginx)
    local wireproxy_status=$(get_service_status wireproxy)
    
    # --- PERBAIKAN: Panggil fungsi baru ---
    local total_traffic=$(get_xray_total_traffic)
    
    # 7. Print formatted
    echo -e "  ${B_WHITE}Sistem:${RESET} $os_info"
    echo -e "  ${B_WHITE}Uptime:${RESET} $uptime_val"
    echo -e "  ${B_WHITE}CPU Load:${RESET} $cpu_load ${B_WHITE}RAM:${RESET} $ram_info"
    echo -e "  ${B_WHITE}IP:${RESET} $ip_val (${B_CYAN}$isp_val - $country_val${RESET})"
    
    # --- PERBAIKAN: Label diperbarui ---
    echo -e "  ${B_WHITE}Trafik Total Xray:${RESET} $total_traffic"

    echo -e "  ${B_WHITE}Status Layanan:${RESET}"
    echo -e "    ${CYAN}Xray:${RESET}      $xray_status  |  ${CYAN}Nginx:${RESET}     $nginx_status  |  ${CYAN}Wireproxy:${RESET} $wireproxy_status"
    
    print_line "-" "$CYAN"
}
# ======================================================================
# --- AKHIR FUNGSI HEADER ---
# ======================================================================


# --- Fungsi Tampilan 3 Kolom ---
print_three_columns() {
    local header_left="$1"
    local list_left="$2"   # Proto
    local header_mid="$3"
    local list_mid="$4"    # User Tersedia
    local header_right="$5"
    local list_right="$6"  # User SUDAH
    
    local col_width_left=15
    local col_width_mid=25
    local col_width_right=30

    # Header
    printf "\n  ${B_GREEN}%-${col_width_left}s${RESET} | ${B_GREEN}%-${col_width_mid}s${RESET} | ${B_YELLOW}%-${col_width_right}s${RESET}\n" "$header_left" "$header_mid" "$header_right"
    
    local total_width=$((col_width_left + col_width_mid + col_width_right + 6)) # 3 cols + 6 chars ' | '
    printf "  ${CYAN}%*s${RESET}\n" "$total_width" "" | tr ' ' "-"

    # Gunakan paste untuk menggabungkan ketiga list
    # Butuh padding untuk list
    local padded_list_left=$(echo "$list_left" | awk -v w="$col_width_left" '{printf "%-" w "s\n", $0}')
    local padded_list_mid=$(echo "$list_mid" | awk -v w="$col_width_mid" '{printf "%-" w "s\n", $0}')
    local padded_list_right=$(echo "$list_right" | awk -v w="$col_width_right" '{printf "%-" w "s\n", $0}')

    # Paste 3 file
    paste -d'|' <(echo "$padded_list_left") <(echo "$padded_list_mid") <(echo "$padded_list_right") \
    | while IFS='|' read -r left mid right; do
        # Cetak dengan warna
        printf "  ${GREEN}%s${RESET} | ${GREEN}%s${RESET} | ${YELLOW}%s${RESET}\n" "$left" "$mid" "$right"
    done
    
    echo "" # Spasi
}

# ======================================================================
# --- PERBAIKAN: Menambahkan kembali print_side_by_side (2 kolom) ---
# ======================================================================
print_side_by_side() {
    local header_left="$1"
    local list_left="$2"
    local header_right="$3"
    local list_right="$4"
    local col_width=35 # Lebar kolom

    printf "\n  ${B_GREEN}%-${col_width}s${RESET} | ${B_YELLOW}%-${col_width}s${RESET}\n" "$header_left" "$header_right"
    
    local line_char="-"
    local total_width=$((col_width * 2 + 3)) # 2 cols + 3 chars for ' | '
    printf "  ${CYAN}%*s${RESET}\n" "$total_width" "" | tr ' ' "$line_char"

    # Gunakan paste dan awk untuk format
    paste -d'|' <(echo "$list_left" | awk -v w="$col_width" '{printf "%-" w "s\n", $0}') \
                <(echo "$list_right" | awk -v w="$col_width" '{printf "%-" w "s\n", $0}') \
    | while IFS='|' read -r left right; do
        # Cetak dengan warna
        printf "  ${GREEN}%s${RESET} | ${YELLOW}%s${RESET}\n" "$left" "$right"
    done
    
    echo "" # Spasi
}
# ======================================================================
# --- AKHIR PERBAIKAN ---
# ======================================================================

# ======================================================================
# --- Logika Skrip (menu.sh) ---
# ======================================================================

# ====== Cek & Buat Direktori (UPDATED) ======
ensure_dirs(){
  local protos=("vmess" "vless" "trojan" "http" "socks" "shadowsocks")
  for p in "${protos[@]}"; do
    if [[ ! -d "$ACCOUNTS_DIR/$p" ]]; then
      mkdir -p "$ACCOUNTS_DIR/$p"
    fi
    if [[ ! -f "$ACCOUNTS_DIR/$p.db" ]]; then
      touch "$ACCOUNTS_DIR/$p.db"
    fi
  done
  
  if [[ ! -f "$HOSTS_FILE" ]]; then touch "$HOSTS_FILE"; fi
}

# ====== Guard ======
need_root(){ [[ "$(id -u)" -eq 0 ]] || { print_error "Jalankan sebagai root."; exit 1; }; }
need_cmd(){ for c in "$@"; do command -v "$c" >/dev/null 2>&1 || { print_error "Perintah '$c' tidak ditemukan."; exit 1; }; done; }

# ====== Validasi Input Domain ======
validate_domain_input(){
  local input="$1"
  if [[ "$input" =~ ^[a-zA-Z0-9.-]+$ ]]; then return 0; else return 1; fi
}

# ====== Util umum ======
rawurlencode(){
  local str="${1}" i c out=""
  for (( i=0; i<${#str}; i++ )); do
    c="${str:i:1}"
    case "$c" in [a-zA-Z0-9.~_-]) out+="$c" ;; *) printf -v h '%%%02X' "'$c"; out+="$h" ;; esac
  done
  echo -n "$out"
}

b64_oneline(){ if base64 --help 2>&1 | grep -q -- "-w"; then base64 -w 0; else base64 | tr -d '\n'; fi; }

get_domain(){
  if [[ -f "$DOMAIN_FILE" ]]; then cat "$DOMAIN_FILE"
  elif [[ -f "$NGINX_CONF" ]]; then awk '/server_name/ {for(i=2;i<=NF;i++){gsub(/;/,"",$i); print $i; exit}}' "$NGINX_CONF"
  else echo ""; fi
}

get_ws_path(){
  local proto="$1" target path=""
  case "$proto" in
    vmess) target="vmess_ws" ;;
    vless) target="vless_ws" ;;
    trojan) target="trojan_ws" ;;
    http) target="http_ws" ;;
    shadowsocks) target="shadowsocks_ws" ;;
    socks) target="socks_ws" ;;
    *) print_error "Proto tidak dikenal: $proto"; return 1 ;;
  esac

  if [[ -f "$NGINX_CONF" ]]; then
    path="$(awk -v T="$target" '
      $0 ~ /map[ \t]+\$uri[ \t]+\$xray_upstream[ \t]*\{/ {inmap=1; next}
      inmap && /\}/ {inmap=0}
      inmap {
        if (match($0, /^[ \t]*\/([^ \t;]+)[ \t]+([A-Za-z0-9_]+)[ \t]*;/, m)) {
          if (m[2]==T) { print m[1]; exit }
        }
      }' "$NGINX_CONF")"
  fi
  
  if [[ -z "$path" ]]; then
    print_warn "Gagal membaca path dari Nginx, mencoba fallback ke config.json..."
    path="$(jq -r --arg p "$proto" '(.inbounds[]? | select(.protocol==$p) | .streamSettings.wsSettings.path // "")' "$CONFIG" | sed -n '1s#^/##p')"
  fi
  
  [[ -n "$path" ]] && { echo -n "$path"; return 0; } || { print_error "Tidak bisa menemukan WS path untuk $proto."; return 1; }
}

# ====== FUNGSI BARU (Poin 1): Ambil Server PSK Shadowsocks ======
get_ss_server_psk() {
    jq -r '(.inbounds[] | select(.protocol=="shadowsocks") | .settings.password // "")' "$CONFIG"
}

# ======================================================================
# --- PERUBAHAN: restart_xray() menggunakan run_task ---
# ======================================================================
restart_xray(){
  if ! run_task "Me-restart layanan Xray" "systemctl restart xray"; then
      print_warn "Layanan Xray gagal restart. Cek status."
  fi
  # Beri waktu Xray untuk stabil
  sleep 0.5
}
# ======================================================================
# --- AKHIR PERUBAHAN ---
# ======================================================================


# ====== Operasi JSON klien (UPDATED) ======
add_client_std(){ # vmess, vless, trojan, shadowsocks
  local proto="$1" user="$2" secret="$3" tmp="$CONFIG.tmp.$$"
  local client_json=""
  case "$proto" in
    vmess) client_json="{\"id\":\"$secret\", \"alterId\":0, \"email\":\"$user\"}" ;;
    vless) client_json="{\"id\":\"$secret\", \"email\":\"$user\"}" ;;
    trojan) client_json="{\"password\":\"$secret\", \"email\":\"$user\"}" ;;
    shadowsocks) client_json="{\"password\":\"$secret\", \"email\":\"$user\"}" ;; # Secret adalah B64 Key
  esac
  jq --arg p "$proto" --argjson c "$client_json" '(.inbounds[] | select(.protocol==$p) | .settings.clients) += [$c]' "$CONFIG" > "$tmp"
  mv "$tmp" "$CONFIG"
}

add_client_acct(){ # http, socks
  local proto="$1" user="$2" secret="$3" tmp="$CONFIG.tmp.$$"
  # Menambahkan 'email' untuk konsistensi del_client
  local client_json="{\"user\":\"$user\", \"pass\":\"$secret\", \"email\":\"$user\"}"
  jq --arg p "$proto" --argjson c "$client_json" '(.inbounds[] | select(.protocol==$p) | .settings.accounts) += [$c]' "$CONFIG" > "$tmp"
  mv "$tmp" "$CONFIG"
}

del_client_std(){ # vmess, vless, trojan, shadowsocks
  local proto="$1" user="$2" tmp="$CONFIG.tmp.$$"
  # Hapus berdasarkan email
  jq --arg p "$proto" --arg user "$user" '(.inbounds[] | select(.protocol==$p) | .settings.clients) |= ( [ .[] | select(.email != $user) ] )' "$CONFIG" > "$tmp"
  mv "$tmp" "$CONFIG"
}

del_client_acct(){ # http, socks
  local proto="$1" user="$2" tmp="$CONFIG.tmp.$$"
  # Hapus berdasarkan user ATAU email (untuk konsistensi)
  jq --arg p "$proto" --arg user "$user" '(.inbounds[] | select(.protocol==$p) | .settings.accounts) |= ( [ .[] | select(.user != $user and .email != $user) ] )' "$CONFIG" > "$tmp"
  mv "$tmp" "$CONFIG"
}

count_clients(){
  local p="$1"
  local count_std=$(jq -r --arg p "$p" '[ .inbounds[]? | select(.protocol==$p) | .settings.clients[]? | select(has("email")) ] | length' "$CONFIG")
  local count_acct=$(jq -r --arg p "$p" '[ .inbounds[]? | select(.protocol==$p) | .settings.accounts[]? | select(has("email")) ] | length' "$CONFIG")
  echo $((count_std + count_acct))
}

# ====== Cek Duplikat Global (DB & Config) ======
username_exists_any_proto(){
  local user="$1"
  
  # 1. Cek di File Database (.db)
  for p in vmess vless trojan http socks shadowsocks; do
      local db="$ACCOUNTS_DIR/$p.db"
      if [[ -f "$db" ]]; then
          if grep -q "^$user|" "$db"; then
              return 0 # Ditemukan di DB
          fi
      fi
  done

  # 2. Cek di Config Xray (config.json) - clients[]
  if jq -e --arg user "$user" '
      .inbounds[]?.settings.clients[]? | 
      select(
          (.email == $user) or 
          (.id == $user) or 
          (.password == $user)
      )
  ' "$CONFIG" > /dev/null 2>&1; then
      return 0 # Ditemukan di Config (VMess/VLess/Trojan/SS)
  fi
  
  # 3. Cek juga untuk http/socks (settings.accounts)
  if jq -e --arg user "$user" '
      .inbounds[]?.settings.accounts[]? |
      select(
          (.user == $user) or
          (.email == $user) or
          (.pass == $user)
      )
  ' "$CONFIG" > /dev/null 2>&1; then
      return 0 # Ditemukan di Config (HTTP/SOCKS)
  fi

  return 1 # Tidak ditemukan di manapun
}

# ====== Panggil semua user yang dibuat ======
get_all_created_users(){
  local all_users=()
  for p in vmess vless trojan http socks shadowsocks; do
    local f="$ACCOUNTS_DIR/$p.db"
    if [[ -f "$f" ]]; then
      # Baca hanya kolom pertama (username)
      while IFS='|' read -r u _ || [[ -n "$u" ]]; do
        if [[ -n "$u" ]]; then
          all_users+=("$u")
        fi
      done < "$f"
    fi
  done
  printf "%s\n" "${all_users[@]}" | sort -u
}

# ====== Helper baru: Panggil semua user DENGAN proto ======
get_all_created_users_map() {
    # Format: user|proto
    for p in vmess vless trojan http socks shadowsocks; do
        local f="$ACCOUNTS_DIR/$p.db"
        if [[ -f "$f" ]]; then
            while IFS='|' read -r u _ || [[ -n "$u" ]]; do
                if [[ -n "$u" ]]; then
                    echo "$u|$p"
                fi
            done < "$f"
        fi
    done | sort
}


# ====== Link Builders (UPDATED) ======
vmess_link_tls(){
  local uuid="$1" domain="$2" path="$3" name="$4"
  local payload="{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$domain\",\"port\":\"443\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$domain\",\"path\":\"/$path\",\"tls\":\"tls\",\"sni\":\"$domain\",\"alpn\":\"\"}"
  echo -n "vmess://$(echo -n "$payload" | b64_oneline)"
}

vmess_link_nontls(){
  local uuid="$1" domain="$2" path="$3" name="$4"
  local payload="{\"v\":\"2\",\"ps\":\"$name-HTTP\",\"add\":\"$domain\",\"port\":\"80\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$domain\",\"path\":\"/$path\",\"tls\":\"none\",\"sni\":\"\",\"alpn\":\"\"}"
  echo -n "vmess://$(echo -n "$payload" | b64_oneline)"
}

vless_link_tls(){ echo -n "vless://$1@$2:443?encryption=none&type=ws&security=tls&host=$2&path=$(rawurlencode "/$3")&sni=$2#$4"; }
vless_link_nontls(){ echo -n "vless://$1@$2:80?encryption=none&type=ws&security=none&host=$2&path=$(rawurlencode "/$3")#$4-HTTP"; }

trojan_link_tls(){ echo -n "trojan://$1@$2:443?type=ws&security=tls&host=$2&path=$(rawurlencode "/$3")&sni=$2#$4"; }
trojan_link_nontls(){ echo -n "trojan://$1@$2:80?type=ws&security=none&host=$2&path=$(rawurlencode "/$3")#$4-HTTP"; }

# ====== Poin 1: Perbaikan Link Shadowsocks ======
shadowsocks_link_tls(){
    local user_psk_b64="$1" domain="$2" path="$3" name="$4"
    local server_psk_b64=$(get_ss_server_psk)
    local method="2022-blake3-aes-128-gcm"
    
    # Format: method:server_psk:user_psk
    local ss_part=$(echo -n "$method:$server_psk_b64:$user_psk_b64" | b64_oneline)
    echo -n "ss://${ss_part}@$domain:443?path=$(rawurlencode "/$path")&security=tls&host=$domain&type=ws&sni=$domain#$name"
}
shadowsocks_link_nontls(){
    local user_psk_b64="$1" domain="$2" path="$3" name="$4"
    local server_psk_b64=$(get_ss_server_psk)
    local method="2022-blake3-aes-128-gcm"
    
    local ss_part=$(echo -n "$method:$server_psk_b64:$user_psk_b64" | b64_oneline)
    echo -n "ss://${ss_part}@$domain:80?path=$(rawurlencode "/$path")&host=$domain&type=ws#$name-HTTP"
}

# ====== Poin 2: Link HTTP ======
http_link_tls(){
    local secret="$1" domain="$2" user="$3" path="$4"
    # Format: https://user:pass@host.com:443?sni=host.com#http
    echo -n "https://$(rawurlencode "$user"):$(rawurlencode "$secret")@$domain:443?sni=$domain#$user-TLS"
}
http_link_nontls(){
    local secret="$1" domain="$2" user="$3" path="$4"
    # Format: http://user:pass@host.com:80#http
    echo -n "http://$(rawurlencode "$user"):$(rawurlencode "$secret")@$domain:80#$user-HTTP"
}

# ====== Poin 3: Link SOCKS ======
socks_link_tls(){
    local secret="$1" domain="$2" user="$3" path="$4"
    # Format: socks5://user:pass@host.com:443?sni=host.com&tls=true#socks
    echo -n "socks5://$(rawurlencode "$user"):$(rawurlencode "$secret")@$domain:443?sni=$domain&tls=true#$user-TLS"
}
socks_link_nontls(){
    local secret="$1" domain="$2" user="$3" path="$4"
    # Format: socks5://user:pass@host.com:80#socks
    echo -n "socks5://$(rawurlencode "$user"):$(rawurlencode "$secret")@$domain:80#$user-HTTP"
}

# ====== Ledger & Header Utils ======
ledger_add(){ echo "$2|$3|$4|$5" >> "$ACCOUNTS_DIR/$1.db"; }

ledger_del(){
  local proto="$1"
  local user="$2"
  local db="$ACCOUNTS_DIR/$proto.db"
  if [[ -f "$db" ]]; then
    grep -v "^$user|" "$db" > "$db.tmp"
    mv "$db.tmp" "$db"
  fi
}

ledger_extend(){
  local proto="$1" user="$2" add="$3" line secret cur_exp created base newexp
  local db="$ACCOUNTS_DIR/$proto.db"
  local db_tmp="$ACCOUNTS_DIR/$proto.db.tmp"
  
  if [[ ! -f "$db" ]]; then
      print_error "Database $proto tidak ditemukan."
      return 1
  fi

  line="$(grep "^$user|" "$db" || true)"
  if [[ -z "$line" ]]; then
      print_error "User '$user' tidak ditemukan di ledger $proto."
      return 1
  fi
  
  secret="$(echo "$line" | cut -d'|' -f2)"
  cur_exp="$(echo "$line" | cut -d'|' -f3)"
  created="$(echo "$line" | cut -d'|' -f4)" 
  
  local today_ts=$(date +%s)
  local cur_exp_ts
  if [[ -z "$cur_exp" ]]; then cur_exp_ts="$today_ts"; else cur_exp_ts=$(date -d "$cur_exp" +%s 2>/dev/null || echo "$today_ts"); fi
  
  if [[ $today_ts -gt $cur_exp_ts ]]; then base="$(date +%F)"; else base="$cur_exp"; fi
  
  if ! newexp="$(date -d "$base + $add days" +%F 2>/dev/null)"; then
      print_error "Gagal menghitung tanggal baru."
      return 1
  fi
  
  grep -v "^$user|" "$db" > "$db_tmp"
  echo "$user|$secret|$newexp|$created" >> "$db_tmp"
  mv "$db_tmp" "$db"
  
  local txt_file="$ACCOUNTS_DIR/$proto/$user-$proto.txt"
  if [[ -f "$txt_file" ]]; then
      sed -i "s/^Expired[[:space:]]*: .*/Expired    : $newexp/" "$txt_file"
      print_info "File informasi akun ($txt_file) telah diperbarui."
  else
      print_warn "File informasi akun text tidak ditemukan, hanya database yang diperbarui."
  fi
  
  print_info "Sukses! Akun $user ($proto) diperpanjang hingga $newexp (Dibuat: $created)"
}

show_account_list_by_proto(){
  local p="$1"
  local db_file="$ACCOUNTS_DIR/$p.db"
  echo -e "\n${B_WHITE}Daftar Akun ${p^^} yang sudah ada:${RESET}"
  printf "  %-15s | %-12s | %-12s\n" "Username" "Dibuat" "Expired"
  echo "  ---------------------------------------------"
  if [[ -f "$db_file" ]]; then
    while IFS='|' read -r u s e c; do
      [[ -z "$c" ]] && c="-"
      printf "  %-15s | %-12s | %-12s\n" "$u" "$c" "$e"
    done < "$db_file"
  fi
  echo "  ---------------------------------------------"
}

# ====== FUNGSI: UPDATE AKUN SETELAH GANTI DOMAIN (UPDATED) ======
update_all_accounts_domain(){
  local new_domain="$1"
  print_info "Mengupdate semua file akun dengan domain baru: $new_domain"
  
  for proto in vmess vless trojan http socks shadowsocks; do
    local dir="$ACCOUNTS_DIR/$proto"
    if [[ -d "$dir" ]]; then
      for file in "$dir"/*.txt; do
        if [[ -f "$file" ]]; then
           local user=$(grep "Username" "$file" | cut -d: -f2 | tr -d ' ')
           local secret=$(grep "Password/ID" "$file" | cut -d: -f2 | tr -d ' ')
           local created=$(grep "Created" "$file" | cut -d: -f2 | tr -d ' ')
           local exp=$(grep "Expired" "$file" | cut -d: -f2 | tr -d ' ')
           local path=$(get_ws_path "$proto")
           
           local link_tls=""
           local link_nontls=""
           local notes="" # Untuk HTTP/SOCKS

           case "$proto" in 
             vmess) 
               link_tls="$(vmess_link_tls "$secret" "$new_domain" "$path" "$user")"
               link_nontls="$(vmess_link_nontls "$secret" "$new_domain" "$path" "$user")"
               ;; 
             vless) 
               link_tls="$(vless_link_tls "$secret" "$new_domain" "$path" "$user")"
               link_nontls="$(vless_link_nontls "$secret" "$new_domain" "$path" "$user")"
               ;; 
             trojan) 
               link_tls="$(trojan_link_tls "$secret" "$new_domain" "$path" "$user")"
               link_nontls="$(trojan_link_nontls "$secret" "$new_domain" "$path" "$user")"
               ;;
             shadowsocks)
               link_tls="$(shadowsocks_link_tls "$secret" "$new_domain" "$path" "$user")"
               link_nontls="$(shadowsocks_link_nontls "$secret" "$new_domain" "$path" "$user")"
               ;;
             http)
               link_tls="$(http_link_tls "$secret" "$new_domain" "$user" "$path")"
               link_nontls="$(http_link_nontls "$secret" "$new_domain" "$user" "$path")"
               notes="--- Catatan Penting ---\n- Wajib menggunakan aplikasi Exclave (bisa cari di internet)\n- Untuk Websocket harus input manual seperti path websocket"
               ;;
             socks)
               link_tls="$(socks_link_tls "$secret" "$new_domain" "$user" "$path")"
               link_nontls="$(socks_link_nontls "$secret" "$new_domain" "$user" "$path")"
               notes="--- Catatan Penting ---\n- Wajib menggunakan aplikasi Exclave (bisa cari di internet)\n- Untuk Websocket harus input manual seperti path websocket"
               ;;
           esac

           # Tulis ulang file
           cat <<EOF > "$file"
=========================================
            DETAIL AKUN XRAY
=========================================
Protokol   : ${proto^^}
Domain     : $new_domain
Username   : $user
Password/ID: $secret
Path WS    : /$path
Expired    : $exp
Created    : $created

--- Link TLS (Port 443) ---
${link_tls}

--- Link Non-TLS/HTTP (Port 80) ---
${link_nontls}

${notes}
=========================================
EOF
           echo "Updated: $file"
        fi
      done
    fi
  done
}

# ====== FUNGSI: UPDATE CNAME CLOUDFLARE ======
update_cname_records(){
    local old_domain="$1"
    local new_domain="$2"
    
    if [[ -z "$old_domain" || -z "$new_domain" ]]; then return; fi
    if [[ ! -f "$HOSTS_FILE" ]]; then return; fi

    local old_prefix=$(echo "$old_domain" | cut -d. -f1)
    local new_prefix=$(echo "$new_domain" | cut -d. -f1)
    
    print_info "Memeriksa update CNAME record dari $old_prefix ke $new_prefix..."
    
    local tmp_hosts=()
    while read -r line; do
        tmp_hosts+=("$line")
    done < "$HOSTS_FILE"
    > "$HOSTS_FILE"

    for host in "${tmp_hosts[@]}"; do
        if [[ "$host" == *".$old_prefix."* ]]; then
            local new_host_name="${host//.$old_prefix./.$new_prefix.}"
            print_info "Mengupdate Host: $host -> $new_host_name"
            
            local zone_name=""
            for d in "${AVAILABLE_DOMAINS[@]}"; do
                if [[ "$host" == *"$d" ]]; then zone_name="$d"; break; fi
            done
            
            if [[ -n "$zone_name" ]]; then
                local zone_id
                zone_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone_name" \
                  -H "Authorization: Bearer $CF_TOKEN" \
                  -H "Content-Type: application/json" | jq -r '.result[0].id')
                
                if [[ "$zone_id" != "null" ]]; then
                    local rec_id
                    rec_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=$host" \
                      -H "Authorization: Bearer $CF_TOKEN" \
                      -H "Content-Type: application/json" | jq -r '.result[0].id')
                    
                    if [[ "$rec_id" != "null" && -n "$rec_id" ]]; then
                        curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$rec_id" \
                          -H "Authorization: Bearer $CF_TOKEN" \
                          -H "Content-Type: application/json" \
                          --data '{"type":"CNAME","name":"'"$new_host_name"'","content":"'"$new_domain"'","proxied":true}' >/dev/null 2>&1
                        
                        print_info "Cloudflare Updated: $new_host_name -> $new_domain"
                        echo "$new_host_name" >> "$HOSTS_FILE"
                    else
                        print_warn "Record DNS untuk $host tidak ditemukan di Cloudflare. Skip."
                        echo "$host" >> "$HOSTS_FILE" 
                    fi
                else
                    echo "$host" >> "$HOSTS_FILE"
                fi
            else
                echo "$host" >> "$HOSTS_FILE"
            fi
        else
            echo "$host" >> "$HOSTS_FILE"
        fi
    done
}

# ====== Aksi Menu ======
aksi_buat(){
  clear; print_header "BUAT AKUN"
  print_menu_option "1)" "VMess (WS)"
  print_menu_option "2)" "VLESS (WS)"
  print_menu_option "3)" "Trojan (WS)"
  print_menu_option "4)" "Shadowsocks (WS)"
  print_menu_option "5)" "HTTP (WS) [Experimental]"
  print_menu_option "6)" "SOCKS (WS) [Experimental]"
  echo ""
  print_menu_option "0)" "Kembali"
  
  # ====== Poin 1 & 2: Memindahkan dan Memperbarui Info Box ======
  echo ""
  print_line "-" "$CYAN"
  echo -e "${B_YELLOW}INFORMASI APLIKASI:${RESET}"
  echo -e "${YELLOW}- Untuk Shadowsocks (WS), direkomendasikan memakai aplikasi ${B_WHITE}Netmod Syna${RESET}."
  echo -e "${YELLOW}- Khusus protokol HTTP (WS) dan SOCKS (WS), ${B_WHITE}WAJIB${RESET} memakai aplikasi ${B_WHITE}Exclave${RESET}."
  # Poin 3: Menggunakan path statis sesuai permintaan
  echo -e "${YELLOW}- Di Exclave, network ws dan Path Websocket (/ZQbXBZzV) harus diatur manual."
  print_line "-" "$CYAN"
  
  print_menu_prompt "Pilih Protokol (0-6)" s
  case "$s" in 
    1) proto="vmess";; 
    2) proto="vless";; 
    3) proto="trojan";; 
    4) proto="shadowsocks";; 
    5) proto="http";; 
    6) proto="socks";; 
    0) return 0;; 
    *) print_error "Pilihan tidak valid."; pause_for_enter; return 1;; 
  esac
  
  show_account_list_by_proto "$proto"
  echo ""

  print_menu_prompt "Username (0 untuk batal)" user
  if [[ "$user" == "0" ]]; then return 0; fi

  if [[ -z "$user" || ! "$user" =~ ^[a-zA-Z0-9._-]+$ ]]; then 
    print_error "Username tidak valid (hanya a-z, 0-9, ._-)."
    pause_for_enter
    return 1
  fi

  if username_exists_any_proto "$user"; then
    print_error "Username '$user' sudah digunakan (terdeteksi di .db atau config.json)."
    pause_for_enter
    return 1
  fi

  print_menu_prompt "Masa aktif (hari, default 30)" days; days="${days:-30}"
  while [[ ! "$days" =~ ^[0-9]+$ ]]; do
    print_error "Input harus angka!"
    print_menu_prompt "Masa aktif (hari)" days
  done
  
  domain="$(get_domain)"; path="$(get_ws_path "$proto")"
  if [[ -z "$path" ]]; then
      print_error "Gagal mendapatkan WS Path untuk $proto."
      pause_for_enter
      return 1
  fi
  
  if [[ -z "$domain" ]]; then
    print_error "Domain belum diset. Silakan ke menu Ganti Domain."
    pause_for_enter
    return 1
  fi
  
  local secret=""
  case "$proto" in 
    vmess|vless) secret="$(/usr/local/bin/xray uuid)";; 
    trojan|http|socks) secret="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 16 || true)";; 
    shadowsocks) secret="$(openssl rand -base64 16)";; # 16 bytes = 128 bit key
  esac
  
  case "$proto" in
    vmess|vless|trojan|shadowsocks) add_client_std "$proto" "$user" "$secret";;
    http|socks) add_client_acct "$proto" "$user" "$secret";;
  esac
  restart_xray
  
  created="$(date +%F)"; exp="$(date -d "+$days days" +%F)"; ledger_add "$proto" "$user" "$secret" "$exp" "$created"
  
  # Generate Links
  local link_tls=""
  local link_nontls=""
  local notes="" # Untuk HTTP/SOCKS

  case "$proto" in 
    vmess) 
      link_tls="$(vmess_link_tls "$secret" "$domain" "$path" "$user")"
      link_nontls="$(vmess_link_nontls "$secret" "$domain" "$path" "$user")"
      ;; 
    vless) 
      link_tls="$(vless_link_tls "$secret" "$domain" "$path" "$user")"
      link_nontls="$(vless_link_nontls "$secret" "$domain" "$path" "$user")"
      ;; 
    trojan) 
      link_tls="$(trojan_link_tls "$secret" "$domain" "$path" "$user")"
      link_nontls="$(trojan_link_nontls "$secret" "$domain" "$path" "$user")"
      ;;
    shadowsocks)
      link_tls="$(shadowsocks_link_tls "$secret" "$domain" "$path" "$user")"
      link_nontls="$(shadowsocks_link_nontls "$secret" "$domain" "$path" "$user")"
      ;;
    http)
      link_tls="$(http_link_tls "$secret" "$domain" "$user" "$path")"
      link_nontls="$(http_link_nontls "$secret" "$domain" "$user" "$path")"
      notes="--- Catatan Penting ---\n- Wajib menggunakan aplikasi Exclave (bisa cari di internet)\n- Untuk Websocket harus input manual seperti path websocket"
      ;;
    socks)
      link_tls="$(socks_link_tls "$secret" "$domain" "$user" "$path")"
      link_nontls="$(socks_link_nontls "$secret" "$domain" "$user" "$path")"
      notes="--- Catatan Penting ---\n- Wajib menggunakan aplikasi Exclave (bisa cari di internet)\n- Untuk Websocket harus input manual seperti path websocket"
      ;;
  esac

  local file_out="$ACCOUNTS_DIR/$proto/$user-$proto.txt"
  # Menulis ke file .txt
  cat <<EOF > "$file_out"
=========================================
            DETAIL AKUN XRAY
=========================================
Protokol   : ${proto^^}
Domain     : $domain
Username   : $user
Password/ID: $secret
Path WS    : /$path
Expired    : $exp
Created    : $created

--- Link TLS (Port 443) ---
${link_tls}

--- Link Non-TLS/HTTP (Port 80) ---
${link_nontls}

${notes}
=========================================
EOF

  clear
  cat "$file_out"
  echo ""
  print_info "Data disimpan di: $file_out"
  pause_for_enter
}

aksi_hapus(){
  clear; print_header "HAPUS AKUN"
  
  echo -e "\n${B_WHITE}Daftar Semua Akun:${RESET}"
  printf "  %-12s | %-15s | %-12s | %-12s\n" "Proto" "User" "Dibuat" "Expired"
  echo "  -------------------------------------------------------------"
  for p in vmess vless trojan http socks shadowsocks; do
    f="$ACCOUNTS_DIR/$p.db"
    [[ -f "$f" ]] && while IFS='|' read -r u s e c; do
      [[ -z "$c" ]] && c="-"
      printf "  %-12s | %-15s | %-12s | %-12s\n" "${p^^}" "$u" "$c" "$e"
    done < "$f"
  done
  echo "  -------------------------------------------------------------"
  echo ""

  print_menu_option "1)" "VMess"
  print_menu_option "2)" "VLESS"
  print_menu_option "3)" "Trojan"
  print_menu_option "4)" "Shadowsocks (WS)"
  print_menu_option "5)" "HTTP (WS)"
  print_menu_option "6)" "SOCKS (WS)"
  echo ""
  print_menu_option "0)" "Kembali"

  print_menu_prompt "Pilih Protokol (0-6)" s
  case "$s" in 
    1) proto="vmess";; 
    2) proto="vless";; 
    3) proto="trojan";; 
    4) proto="shadowsocks";; 
    5) proto="http";; 
    6) proto="socks";; 
    0) return 0;; 
    *) print_error "Pilihan tidak valid."; pause_for_enter; return 1;; 
  esac
  
  print_menu_prompt "Username (0 untuk batal)" user
  if [[ "$user" == "0" ]]; then return 0; fi
  if [[ -z "$user" ]]; then return 1; fi

  case "$proto" in
    vmess|vless|trojan|shadowsocks) del_client_std "$proto" "$user";;
    http|socks) del_client_acct "$proto" "$user";;
  esac
  restart_xray
  
  ledger_del "$proto" "$user"
  
  local txt_file="$ACCOUNTS_DIR/$proto/$user-$proto.txt"
  if [[ -f "$txt_file" ]]; then
      rm -f "$txt_file"
      print_info "File detail akun dihapus: $txt_file"
  fi
  
  print_info "Akun $user ($proto) berhasil dihapus."
  pause_for_enter
}

aksi_perpanjang(){
  clear; print_header "PERPANJANG AKUN"
  
  echo -e "\n${B_WHITE}Daftar Akun yang Bisa Diperpanjang:${RESET}"
  printf "  %-12s | %-15s | %-12s | %-12s\n" "Proto" "User" "Dibuat" "Expired"
  echo "  -------------------------------------------------------------"
  
  for p in vmess vless trojan http socks shadowsocks; do
      local db="$ACCOUNTS_DIR/$p.db"
      if [[ -f "$db" ]]; then
          while IFS='|' read -r u s e c; do
              [[ -z "$c" ]] && c="-" 
              printf "  %-12s | %-15s | %-12s | %-12s\n" "${p^^}" "$u" "$c" "$e"
          done < "$db"
      fi
  done
  echo "  -------------------------------------------------------------"
  echo ""

  print_menu_option "1)" "VMess"
  print_menu_option "2)" "VLESS"
  print_menu_option "3)" "Trojan"
  print_menu_option "4S)" "Shadowsocks (WS)"
  print_menu_option "5)" "HTTP (WS)"
  print_menu_option "6)" "SOCKS (WS)"
  echo ""
  print_menu_option "0)" "Kembali"

  print_menu_prompt "Pilih Protokol (0-6)" s
  case "$s" in 
    1) proto="vmess";; 
    2) proto="vless";; 
    3) proto="trojan";; 
    4) proto="shadowsocks";; 
    5) proto="http";; 
    6) proto="socks";; 
    0) return 0;; 
    *) print_error "Pilihan tidak valid."; pause_for_enter; return 1;; 
  esac
  
  print_menu_prompt "Masukkan Username" user
  
  if [[ -z "$user" ]]; then 
      print_error "Username tidak boleh kosong."
      pause_for_enter; return 1
  fi

  print_menu_prompt "Tambah hari (contoh 30)" days
  if [[ ! "$days" =~ ^[0-9]+$ ]]; then
      print_error "Input hari harus angka."
      pause_for_enter; return 1
  fi

  ledger_extend "$proto" "$user" "$days"
  pause_for_enter
}

aksi_daftar_akun(){
  clear
  print_header "DAFTAR AKUN"
  printf "  %-4s | %-12s | %-15s | %-12s | %-12s\n" "No" "Proto" "User" "Dibuat" "Expired"
  echo "  -----------------------------------------------------------------"
  
  local n=1
  
  read_db(){
    local p="$1"
    local f="$ACCOUNTS_DIR/$p.db"
    if [[ -f "$f" ]]; then
      while IFS='|' read -r u s e c; do
        [[ -z "$c" ]] && c="-"
        printf "  %-4s | %-12s | %-15s | %-12s | %-12s\n" "$n" "${p^^}" "$u" "$c" "$e"
        ((n++))
      done < "$f"
    fi
  }

  read_db "vmess"
  read_db "vless"
  read_db "trojan"
  read_db "shadowsocks"
  read_db "http"
  read_db "socks"
  
  echo "  -----------------------------------------------------------------"
  
  print_menu_prompt "Lihat Detail (Masukkan Username) atau [Enter] untuk kembali" target_user

  if [[ -z "$target_user" ]]; then return 0; fi

  local found_proto=""
  if [[ -f "$ACCOUNTS_DIR/vmess/$target_user-vmess.txt" ]]; then found_proto="vmess"
  elif [[ -f "$ACCOUNTS_DIR/vless/$target_user-vless.txt" ]]; then found_proto="vless"
  elif [[ -f "$ACCOUNTS_DIR/trojan/$target_user-trojan.txt" ]]; then found_proto="trojan"
  elif [[ -f "$ACCOUNTS_DIR/shadowsocks/$target_user-shadowsocks.txt" ]]; then found_proto="shadowsocks"
  elif [[ -f "$ACCOUNTS_DIR/http/$target_user-http.txt" ]]; then found_proto="http"
  elif [[ -f "$ACCOUNTS_DIR/socks/$target_user-socks.txt" ]]; then found_proto="socks"
  fi

  if [[ -z "$found_proto" ]]; then
    print_error "File informasi akun untuk user '$target_user' tidak ditemukan."
    pause_for_enter
    return 1
  fi

  local txt_file="$ACCOUNTS_DIR/$found_proto/$target_user-$found_proto.txt"
  clear
  print_header "DETAIL AKUN: $target_user"
  echo -e "${B_WHITE}Source File: ${RESET}$txt_file\n"
  cat "$txt_file"
  echo ""
  pause_for_enter
}

# ======================================================================
# --- PERUBAHAN: aksi_ganti_domain() menggunakan run_task ---
# ======================================================================
aksi_ganti_domain(){
  clear
  print_header "GANTI DOMAIN"
  print_menu_option "1)" "Gunakan Domain Sendiri (Manual)"
  print_menu_option "2)" "Gunakan Domain Tersedia (Auto Cloudflare)"
  echo ""
  print_menu_option "0)" "Kembali ke Menu Utama"
  
  print_menu_prompt "Pilih opsi (0-2)" choice

  if [[ "$choice" == "0" ]]; then return 0; fi

  local old_domain="$(get_domain)" # Simpan domain lama
  local newdom mode

  if [[ "$choice" == "1" ]]; then
    echo -e "\n${B_CYAN}Input domain anda sendiri.${RESET}"
    echo "  Validasi: Hanya huruf, angka, titik, dan strip."
    
    print_menu_prompt "Domain (0 untuk batal)" newdom
    if [[ "$newdom" == "0" ]]; then return 0; fi

    if ! validate_domain_input "$newdom"; then
      print_error "Format domain tidak valid!"
      pause_for_enter; return 1
    fi

    print_info "Memproses domain sendiri: $newdom (Standalone)"
    run_task "Menghentikan Nginx sementara" "systemctl stop nginx || true"
    run_task "Set default CA ke Letsencrypt" "\"$ACME_BIN\" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true"
    
    if run_task "Menerbitkan sertifikat (Standalone)" "\"$ACME_BIN\" --issue --standalone -d \"$newdom\" --force"; then
      mode="standalone"
    else
      # Error sudah dicetak oleh run_task
      run_task "Menjalankan Nginx kembali (gagal)" "systemctl start nginx || true"
      pause_for_enter; return 1
    fi

  elif [[ "$choice" == "2" ]]; then
    echo -e "\n${B_CYAN}Pilih Domain Tersedia:${RESET}"
    local i=1
    for d in "${AVAILABLE_DOMAINS[@]}"; do print_menu_option "$i." "$d"; ((i++)); done
    echo ""
    print_menu_option "0." "Kembali"
    
    print_menu_prompt "Pilih domain utama (angka)" d_idx
    
    if [[ "$d_idx" == "0" ]]; then return 0; fi
    local selected_domain="${AVAILABLE_DOMAINS[$((d_idx-1))]}"
    
    if [[ -z "$selected_domain" ]]; then
      print_error "Pilihan tidak valid."
      pause_for_enter; return 1
    fi

    echo -e "\n${B_CYAN}Konfigurasi Subdomain untuk $selected_domain:${RESET}"
    print_menu_option "1." "Generate Nama Random (Maks 7 huruf)"
    print_menu_option "2." "Masukkan Nama Sendiri"
    echo ""
    print_menu_option "0." "Kembali"
    
    print_menu_prompt "Pilih opsi subdomain (0-2)" sub_opt
    
    if [[ "$sub_opt" == "0" ]]; then return 0; fi

    local sub_name=""
    if [[ "$sub_opt" == "1" ]]; then
        sub_name="$(tr -dc 'a-z0-9' < /dev/urandom | head -c 7 || true)"
        echo -e "\n  Subdomain Random: ${B_GREEN}${sub_name}${RESET}"
    elif [[ "$sub_opt" == "2" ]]; then
        print_menu_prompt "Masukkan subdomain (huruf/angka/titik/strip) (0 untuk batal)" sub_input
        if [[ "$sub_input" == "0" ]]; then return 0; fi
        if ! validate_domain_input "$sub_input"; then
            print_error "Format salah."
            pause_for_enter; return 1
        fi
        sub_name="$sub_input"
    else
        print_error "Pilihan salah."
        pause_for_enter; return 1
    fi

    newdom="${sub_name}.${selected_domain}"
    print_info "Domain Target: $newdom"
    local my_ip
    my_ip=$(curl -sS ipv4.icanhazip.com)
    print_info "IP VPS terdeteksi: $my_ip"

    local zone_id
    zone_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$selected_domain" \
      -H "Authorization: Bearer $CF_TOKEN" \
      -H "Content-Type: application/json" | jq -r '.result[0].id')

    if [[ "$zone_id" == "null" || -z "$zone_id" ]]; then
      print_error "Gagal mendapatkan Zone ID. Cek Token."
      pause_for_enter; return 1
    fi

    local old_records
    old_records=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=A&content=$my_ip" \
      -H "Authorization: Bearer $CF_TOKEN" \
      -H "Content-Type: application/json")
    
    for rec_id in $(echo "$old_records" | jq -r '.result[]?.id'); do
        if [[ -n "$rec_id" && "$rec_id" != "null" ]]; then
            print_info "Menghapus record lama (ID: $rec_id)..."
            curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$rec_id" \
                -H "Authorization: Bearer $CF_TOKEN" \
                -H "Content-Type: application/json" >/dev/null 2>&1
        fi
    done

    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
      -H "Authorization: Bearer $CF_TOKEN" \
      -H "Content-Type: application/json" \
      --data '{"type":"A","name":"'"$newdom"'","content":"'"$my_ip"'","ttl":1,"proxied":false}' > /dev/null 2>&1
    
    print_info "DNS Record Updated."
    print_info "Memproses Issue Sertifikat (Wildcard & Full)..."
    
    # Export token untuk acme.sh
    export CF_Token="$CF_TOKEN"
    export CF_Account_ID=""
    
    run_task "Set default CA ke Letsencrypt" "\"$ACME_BIN\" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true"
    
    if run_task "Menerbitkan sertifikat (DNS Cloudflare)" "\"$ACME_BIN\" --issue --dns dns_cf -d \"$newdom\" -d \"*.$newdom\" --force"; then
      mode="wildcard"
    else
      # Error sudah dicetak oleh run_task
      pause_for_enter; return 1
    fi

  else
    print_error "Pilihan tidak valid."
    pause_for_enter; return 1
  fi

  run_task "Install sertifikat ke $ASSET_DIR" "\"$ACME_BIN\" --install-cert -d \"$newdom\" \
    --fullchain-file \"$ASSET_DIR/fullchain.pem\" \
    --key-file \"$ASSET_DIR/privkey.pem\""

  run_task "Mengatur izin file sertifikat" "chmod 644 \"$ASSET_DIR/privkey.pem\" \"$ASSET_DIR/fullchain.pem\""
  
  echo "$newdom" > "$DOMAIN_FILE"
  
  if [[ -f "$NGINX_CONF" ]]; then sed -i "s/server_name .*/server_name $newdom;/" "$NGINX_CONF"; fi
  
  run_task "Menjalankan Nginx" "systemctl start nginx"
  restart_xray
  
  # TRIGGER FUNGSI UPDATE
  if [[ -n "$old_domain" && "$old_domain" != "$newdom" ]]; then
      update_all_accounts_domain "$newdom"
      update_cname_records "$old_domain" "$newdom"
  fi

  print_info "Domain berhasil diganti ke: $newdom ($mode)"
  pause_for_enter
}
# ======================================================================
# --- AKHIR PERUBAHAN ---
# ======================================================================

aksi_tambah_host(){
  while true; do
    clear
    print_header "MANAJEMEN HOST / SUBDOMAIN"
    
    if [[ -f "$HOSTS_FILE" && -s "$HOSTS_FILE" ]]; then
      echo -e "\n${B_WHITE}Daftar Host yang sudah ditambahkan:${RESET}"
      local n=1
      while read -r line; do echo "  $n. $line"; ((n++)); done < "$HOSTS_FILE"
      echo "  -----------------------------------------"
    else
      echo -e "\n${B_YELLOW}Belum ada host yang ditambahkan.${RESET}"
      echo "  -----------------------------------------"
    fi
    echo ""
    print_menu_option "1)" "Tambah Host Baru"
    print_menu_option "2)" "Hapus Host dari daftar"
    echo ""
    print_menu_option "0)" "Kembali ke Menu Utama"
    
    print_menu_prompt "Pilih Opsi (0-2)" h_opt

    case "$h_opt" in
      1)
        echo -e "\n${B_CYAN}--- Tambah Host ---${RESET}"
        if [[ ! -f "$DOMAIN_FILE" ]]; then print_error "File domain VPS tidak ditemukan."; pause_for_enter; continue; fi
        local vps_domain_target
        vps_domain_target=$(cat "$DOMAIN_FILE" | tr -d ' \n\r')
        if [[ -z "$vps_domain_target" ]]; then print_error "Domain utama VPS belum diset."; pause_for_enter; continue; fi

        local vps_prefix
        vps_prefix=$(echo "$vps_domain_target" | cut -d. -f1)

        echo -e "\n  Masukkan nama host (subdomain). Contoh: ${B_WHITE}ava.game.naver.com${RESET}"
        print_menu_prompt "Host Input (0 untuk batal)" host_input
        if [[ "$host_input" == "0" ]]; then continue; fi
        if [[ -z "$host_input" ]]; then print_error "Nama host tidak boleh kosong."; sleep 1; continue; fi

        echo -e "\n${B_CYAN}Pilih Domain Tersedia (Auto Cloudflare):${RESET}"
        local i=1
        for d in "${AVAILABLE_DOMAINS[@]}"; do print_menu_option "$i." "$d"; ((i++)); done
        
        print_menu_prompt "Pilih domain utama (angka)" d_idx
        local selected_domain="${AVAILABLE_DOMAINS[$((d_idx-1))]}"
        
        if [[ -z "$selected_domain" ]]; then print_error "Pilihan tidak valid."; sleep 1; continue; fi

        local record_name="${host_input}.${vps_prefix}"
        local full_fqdn="${record_name}.${selected_domain}"
        local zone_name="$selected_domain"

        print_info "Full Record    : $full_fqdn"
        local zone_id
        zone_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone_name" \
          -H "Authorization: Bearer $CF_TOKEN" \
          -H "Content-Type: application/json" | jq -r '.result[0].id')

        if [[ "$zone_id" == "null" || -z "$zone_id" ]]; then print_error "Gagal mendapatkan Zone ID."; pause_for_enter; continue; fi

        local response
        response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
          -H "Authorization: Bearer $CF_TOKEN" \
          -H "Content-Type: application/json" \
          --data '{"type":"CNAME","name":"'"$full_fqdn"'","content":"'"$vps_domain_target"'","ttl":1,"proxied":true}')

        local success
        success=$(echo "$response" | jq -r '.success')

        if [[ "$success" == "true" ]]; then
          print_info "Berhasil menambahkan host!"
          echo "$full_fqdn" >> "$HOSTS_FILE"
        else
          local msg
          msg=$(echo "$response" | jq -r '.errors[0].message')
          print_error "Gagal menambahkan record. Cloudflare Error: $msg"
        fi
        pause_for_enter
        ;;
      
      2)
        echo -e "\n${B_CYAN}--- Hapus Host ---${RESET}"
        print_menu_prompt "Masukkan nomor urut host yang ingin dihapus (0 untuk batal)" del_num
        if [[ "$del_num" == "0" ]]; then continue; fi
        
        if [[ "$del_num" =~ ^[0-9]+$ ]]; then
             local total_lines
             total_lines=$(wc -l < "$HOSTS_FILE")
             
             if [[ "$del_num" -gt 0 && "$del_num" -le "$total_lines" ]]; then
                 local host_to_del
                 host_to_del=$(sed "${del_num}q;d" "$HOSTS_FILE")
                 print_info "Host dipilih: $host_to_del"
                 local zone_name=""
                 for d in "${AVAILABLE_DOMAINS[@]}"; do
                   if [[ "$host_to_del" == *"$d" ]]; then zone_name="$d"; break; fi
                 done

                 if [[ -n "$zone_name" ]]; then
                   local zone_id
                   zone_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone_name" \
                     -H "Authorization: Bearer $CF_TOKEN" \
                     -H "Content-Type: application/json" | jq -r '.result[0].id')
                   local rec_id
                   rec_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=$host_to_del" \
                     -H "Authorization: Bearer $CF_TOKEN" \
                     -H "Content-Type: application/json" | jq -r '.result[0].id')

                   if [[ "$rec_id" != "null" && -n "$rec_id" ]]; then
                     # Menggunakan run_task untuk menghapus record
                     local curl_cmd="curl -s -X DELETE 'https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$rec_id' -H 'Authorization: Bearer $CF_TOKEN' -H 'Content-Type: application/json'"
                     if ! run_task "Menghapus record $host_to_del dari Cloudflare" "$curl_cmd"; then
                        print_warn "Gagal menghapus dari Cloudflare, namun lanjut menghapus dari list lokal."
                     fi
                   else
                     print_warn "Record ID tidak ditemukan di Cloudflare. (Mungkin sudah dihapus)"
                   fi
                 fi
                 sed -i "${del_num}d" "$HOSTS_FILE"
                 print_info "Host dihapus dari daftar lokal."
             else
                 print_error "Nomor tidak valid."
             fi
        else
             print_error "Input bukan angka."
        fi
        sleep 1
        ;;

      0) return 0 ;;
      *) print_error "Pilihan tidak valid."; sleep 1 ;;
    esac
  done
}

# ======================================================================
# --- PERUBAHAN: aksi_about() ---
# ======================================================================
aksi_about(){
  clear
  local domain pv pl pt pss phttp psocks
  domain="$(get_domain)"
  pv="$(count_clients vmess)"; pl="$(count_clients vless)"; pt="$(count_clients trojan)"
  pss="$(count_clients shadowsocks)"; phttp="$(count_clients http)"; psocks="$(count_clients socks)"
  
  # --- BARU: Ambil Versi ---
  print_info "Mengambil versi terbaru dari GitHub..."
  
  # Poin 2: Versi Xray (di-parse)
  local xray_ver
  xray_ver=$(/usr/local/bin/xray -version 2>/dev/null | head -n1 | awk '{print $2}' || echo "unknown")
  
  # Poin 3: Versi Nginx (di-parse)
  local nginx_ver
  nginx_ver=$(nginx -v 2>&1 | awk '{print $3}' || echo "unknown")
  
  # Poin 1: Versi wgcf (API)
  local wgcf_ver
  wgcf_ver=$(curl -s "https://api.github.com/repos/ViRb3/wgcf/releases/latest" | jq -r '.tag_name' || echo "failed")
  [ "$wgcf_ver" == "null" -o -z "$wgcf_ver" -o "$wgcf_ver" == "failed" ] && wgcf_ver="unknown"

  # Poin 1: Versi wireproxy (API)
  local wp_ver
  wp_ver=$(curl -s "https://api.github.com/repos/whyvl/wireproxy/releases/latest" | jq -r '.tag_name' || echo "failed")
  [ "$wp_ver" == "null" -o -z "$wp_ver" -o "$wp_ver" == "failed" ] && wp_ver="unknown"
  # --- AKHIR BARU ---

  clear # Hapus "Mengambil versi..."
  print_header "ABOUT"
  echo -e "  ${B_WHITE}Domain${RESET}          : $domain"
  echo -e "  ${B_WHITE}WS Path VMess${RESET}   : /$(get_ws_path vmess || echo '?')"
  echo -e "  ${B_WHITE}WS Path VLESS${RESET}   : /$(get_ws_path vless || echo '?')"
  echo -e "  ${B_WHITE}WS Path Trojan${RESET}  : /$(get_ws_path trojan || echo '?')"
  echo -e "  ${B_WHITE}WS Path SS${RESET}      : /$(get_ws_path shadowsocks || echo '?')"
  echo -e "  ${B_WHITE}WS Path HTTP${RESET}    : /$(get_ws_path http || echo '?')"
  echo -e "  ${B_WHITE}WS Path SOCKS${RESET}   : /$(get_ws_path socks || echo '?')"
  echo ""
  echo -e "  ${B_WHITE}Akun VMess${RESET}      : $pv"
  echo -e "  ${B_WHITE}Akun VLESS${RESET}      : $pl"
  echo -e "  ${B_WHITE}Akun Trojan${RESET}     : $pt"
  echo -e "  ${B_WHITE}Akun Shadowsocks${RESET}: $pss"
  echo -e "  ${B_WHITE}Akun HTTP${RESET}       : $phttp"
  echo -e "  ${B_WHITE}Akun SOCKS${RESET}      : $psocks"
  echo ""
  # --- PERUBAHAN VERSI ---
  echo -e "  ${B_WHITE}Xray version${RESET}    : $xray_ver"
  echo -e "  ${B_WHITE}Nginx version${RESET}   : $nginx_ver"
  echo -e "  ${B_WHITE}wgcf version${RESET}    : $wgcf_ver (latest)"
  echo -e "  ${B_WHITE}wireproxy version${RESET}: $wp_ver (latest)"
  # --- AKHIR PERUBAHAN ---
  echo -e "\n  ${YELLOW}Catatan: tanggal kadaluarsa di ledger hanya pengingat.${RESET}"
  pause_for_enter
}
# ======================================================================
# --- AKHIR PERUBAHAN ---
# ======================================================================


# ======================================================================
# --- FUNGSI MANAJEMEN RUTE (BARU) ---
# ======================================================================

# ======================================================================
# --- PERUBAHAN: rute_blokir_akun (Tambah/Hapus) ---
# ======================================================================
rute_blokir_akun() {
  clear
  print_header "Blokir Akun (User/Email)"
  
  # Ambil SEMUA user dari aturan
  local rule_users_all_json=$(jq -r '(.routing.rules[] | select(.outboundTag == "blocked" and .user != null) | .user) // []' "$CONFIG")
  
  # --- UPDATE DISINI: Filter "user2" DAN "quota" dari tampilan ---
  local rule_users_display=$(echo "$rule_users_all_json" | jq -r '[.[] | select(. != "user2" and . != "quota")] | .[]')
  
  # Siapkan list untuk 3 kolom
  local users_tersedia_proto=""
  local users_tersedia_user=""
  
  # Panggil map user|proto
  local all_users_map=$(get_all_created_users_map)
  
  while IFS='|' read -r user proto; do
      if [[ -n "$user" ]]; then
          # Cek apakah user ada di JSON aturan
          if ! echo "$rule_users_all_json" | jq -e --arg u "$user" '.[] | select(. == $u)' > /dev/null; then
              # Jika TIDAK ADA, masukkan ke daftar TERSEDIA
              users_tersedia_proto+=$(printf "%s\n" "$proto")
              users_tersedia_user+=$(printf "%s\n" "$user")
          fi
      fi
  done < <(echo "$all_users_map") # Feed map into loop
  
  # Tampilkan 3 kolom
  print_three_columns "Protokol" "$users_tersedia_proto" \
                     "User belum diblokir" "$users_tersedia_user" \
                     "User sudah diblokir" "$rule_users_display"
  
  # --- Menu Aksi ---
  echo ""
  print_menu_option "1)" "Tambah User ke Daftar Blokir"
  print_menu_option "2)" "Hapus User dari Daftar Blokir (Unblock)"
  echo ""
  print_menu_option "0)" "Kembali"
  
  print_menu_prompt "Pilih Opsi (0-2)" sub_opt
  
  local tmp="$CONFIG.tmp.$$"

  case "$sub_opt" in
    1) # Tambah
      print_menu_prompt "Masukkan User/Email yang akan diblokir (0 untuk batal)" user_baru
      if [[ "$user_baru" == "0" ]]; then return 0; fi
      if [[ -z "$user_baru" ]]; then print_error "Input tidak boleh kosong."; pause_for_enter; return 1; fi

      if echo "$rule_users_all_json" | jq -e --arg u "$user_baru" '.[] | select(. == $u)' > /dev/null; then
        print_warn "User '$user_baru' sudah ada dalam daftar blokir."
        pause_for_enter
        return 1
      fi

      jq --arg user_baru "$user_baru" '(.routing.rules[] | select(.outboundTag == "blocked" and .user != null) | .user) |= (. + [$user_baru] | unique)' "$CONFIG" > "$tmp"
      
      if [ $? -eq 0 ]; then
        mv "$tmp" "$CONFIG"
        print_info "User '$user_baru' berhasil ditambahkan ke daftar blokir."
        restart_xray
      else
        print_error "Gagal memperbarui konfigurasi. Periksa $tmp"
        rm -f "$tmp"
      fi
      ;;
      
    2) # Hapus
      print_menu_prompt "Masukkan User/Email yang akan di-UNBLOK (0 untuk batal)" user_hapus
      if [[ "$user_hapus" == "0" ]]; then return 0; fi
      if [[ -z "$user_hapus" ]]; then print_error "Input tidak boleh kosong."; pause_for_enter; return 1; fi

      # --- UPDATE DISINI: Tambahkan "quota" ke proteksi agar tidak dihapus manual ---
      if [[ "$user_hapus" == "user2" || "$user_hapus" == "quota" ]]; then
          print_error "User system '$user_hapus' tidak dapat dihapus dari daftar blokir."
          pause_for_enter
          return 1
      fi

      if ! echo "$rule_users_all_json" | jq -e --arg u "$user_hapus" '.[] | select(. == $u)' > /dev/null; then
        print_warn "User '$user_hapus' tidak ditemukan dalam daftar blokir."
        pause_for_enter
        return 1
      fi

      jq --arg user_hapus "$user_hapus" '(.routing.rules[] | select(.outboundTag == "blocked" and .user != null) | .user) |= (del(.[] | select(. == $user_hapus)))' "$CONFIG" > "$tmp"

      if [ $? -eq 0 ]; then
        mv "$tmp" "$CONFIG"
        print_info "User '$user_hapus' berhasil di-UNBLOK (dihapus dari daftar blokir)."
        restart_xray
      else
        print_error "Gagal memperbarui konfigurasi. Periksa $tmp"
        rm -f "$tmp"
      fi
      ;;
      
    0) return 0 ;;
    *) print_error "Pilihan tidak valid."; sleep 1 ;;
  esac
  
  pause_for_enter
}
# ======================================================================
# --- AKHIR PERUBAHAN ---
# ======================================================================


# Poin 5: Fungsi atur rute website yang sudah ditentukan ke warp
rute_toggle_website() {
  clear
  print_header "Toggle Rute Website (WARP/Direct)"
  
  # Ambil aturan
  local rule=$(jq -r '(.routing.rules[] | select(.domain[]? == "geosite:apple"))' "$CONFIG")
  
  if [[ -z "$rule" ]]; then
    print_error "Tidak dapat menemukan aturan rute untuk website (geosite:apple)."
    pause_for_enter
    return 1
  fi

  # Ambil tag saat ini
  local current_tag=$(echo "$rule" | jq -r '.outboundTag')
  # Ambil daftar domain
  local domain_list=$(echo "$rule" | jq -r '.domain | .[]')
  
  # Tampilkan daftar domain
  echo -e "  ${B_WHITE}Daftar Website/Domain yang diatur oleh aturan ini:${RESET}"
  while IFS= read -r domain; do
      echo -e "    - ${CYAN}$domain${RESET}"
  done < <(echo "$domain_list")
  echo "" # Spasi
  
  local new_tag
  if [[ "$current_tag" == "warp" ]]; then
    print_info "Status Saat Ini: ${B_YELLOW}WARP${RESET}"
    new_tag="direct"
  else
    print_info "Status Saat Ini: ${B_GREEN}DIRECT${RESET}"
    new_tag="warp"
  fi
  
  print_menu_prompt "Ubah status ke ${B_CYAN}${new_tag^^}${RESET}? (y/n)" confirm
  if [[ "$confirm" != "y" ]]; then
    print_info "Perubahan dibatalkan."
    pause_for_enter
    return 0
  fi

  local tmp="$CONFIG.tmp.$$"
  jq --arg new_tag "$new_tag" '(.routing.rules[] | select(.domain[]? == "geosite:apple") | .outboundTag) = $new_tag' "$CONFIG" > "$tmp"
  
  if [ $? -eq 0 ]; then
    mv "$tmp" "$CONFIG"
    print_info "Rute website berhasil diubah ke: ${B_CYAN}${new_tag^^}${RESET}"
    restart_xray
  else
    print_error "Gagal memperbarui konfigurasi. Periksa $tmp"
    rm -f "$tmp"
  fi
  pause_for_enter
}

# Poin 6: Fungsi atur semua koneksi ke warp
rute_toggle_semua() {
  clear
  print_header "Toggle Rute Semua Koneksi (WARP/Direct)"
  
  local current_tag=$(jq -r '(.routing.rules[] | select(.port == "1-65535") | .outboundTag)' "$CONFIG")
  
  if [[ -z "$current_tag" ]]; then
    print_error "Tidak dapat menemukan aturan rute untuk 'semua koneksi' (port: 1-65535)."
    pause_for_enter
    return 1
  fi
  
  local new_tag
  if [[ "$current_tag" == "warp" ]]; then
    print_info "Status Saat Ini: ${B_YELLOW}WARP${RESET} (Semua trafik dialihkan ke WARP)"
    new_tag="direct"
  else
    print_info "Status Saat Ini: ${B_GREEN}DIRECT${RESET} (Hanya trafik website tertentu ke WARP)"
    new_tag="warp"
  fi
  
  print_menu_prompt "Ubah status ke ${B_CYAN}${new_tag^^}${RESET}? (y/n)" confirm
  if [[ "$confirm" != "y" ]]; then
    print_info "Perubahan dibatalkan."
    pause_for_enter
    return 0
  fi

  local tmp="$CONFIG.tmp.$$"
  jq --arg new_tag "$new_tag" '(.routing.rules[] | select(.port == "1-65535") | .outboundTag) = $new_tag' "$CONFIG" > "$tmp"
  
  if [ $? -eq 0 ]; then
    mv "$tmp" "$CONFIG"
    print_info "Rute semua koneksi berhasil diubah ke: ${B_CYAN}${new_tag^^}${RESET}"
    restart_xray
  else
    print_error "Gagal memperbarui konfigurasi. Periksa $tmp"
    rm -f "$tmp"
  fi
  pause_for_enter
}

# ======================================================================
# --- PERUBAHAN: rute_tambah_user_warp (Tambah/Hapus) ---
# ======================================================================
rute_tambah_user_warp() {
  clear
  print_header "Tambah/Hapus User dari Rute WARP"
  
  # Ambil SEMUA user dari aturan
  local rule_users_all_json=$(jq -r '(.routing.rules[] | select(.outboundTag == "warp" and .user != null) | .user) // []' "$CONFIG")
  # Filter user default "user1" HANYA untuk tampilan
  local rule_users_display=$(echo "$rule_users_all_json" | jq -r '[.[] | select(. != "user1")] | .[]')
  
  # Siapkan list untuk 3 kolom
  local users_tersedia_proto=""
  local users_tersedia_user=""
  
  # Panggil map user|proto
  local all_users_map=$(get_all_created_users_map)
  
  while IFS='|' read -r user proto; do
      if [[ -n "$user" ]]; then
          # Cek apakah user ada di JSON aturan
          if ! echo "$rule_users_all_json" | jq -e --arg u "$user" '.[] | select(. == $u)' > /dev/null; then
              # Jika TIDAK ADA, masukkan ke daftar TERSEDIA
              users_tersedia_proto+=$(printf "%s\n" "$proto")
              users_tersedia_user+=$(printf "%s\n" "$user")
          fi
      fi
  done < <(echo "$all_users_map") # Feed map into loop
  
  # Tampilkan 3 kolom
  print_three_columns "Protokol" "$users_tersedia_proto" \
                     "User belum ke WARP" "$users_tersedia_user" \
                     "User sudah ke WARP" "$rule_users_display"
  
  # --- Menu Aksi ---
  echo ""
  print_menu_option "1)" "Tambah User ke Rute WARP"
  print_menu_option "2)" "Hapus User dari Rute WARP"
  echo ""
  print_menu_option "0)" "Kembali"
  
  print_menu_prompt "Pilih Opsi (0-2)" sub_opt
  
  local tmp="$CONFIG.tmp.$$"

  case "$sub_opt" in
    1) # Tambah
      print_menu_prompt "Masukkan User/Email yang akan dirutekan ke WARP (0 untuk batal)" user_baru
      if [[ "$user_baru" == "0" ]]; then return 0; fi
      if [[ -z "$user_baru" ]]; then print_error "Input tidak boleh kosong."; pause_for_enter; return 1; fi

      if echo "$rule_users_all_json" | jq -e --arg u "$user_baru" '.[] | select(. == $u)' > /dev/null; then
        print_warn "User '$user_baru' sudah ada dalam daftar rute WARP."
        pause_for_enter
        return 1
      fi

      jq --arg user_baru "$user_baru" '(.routing.rules[] | select(.outboundTag == "warp" and .user != null) | .user) |= (. + [$user_baru] | unique)' "$CONFIG" > "$tmp"
      
      if [ $? -eq 0 ]; then
        mv "$tmp" "$CONFIG"
        print_info "User '$user_baru' berhasil ditambahkan ke rute WARP."
        restart_xray
      else
        print_error "Gagal memperbarui konfigurasi. Periksa $tmp"
        rm -f "$tmp"
      fi
      ;;
      
    2) # Hapus
      print_menu_prompt "Masukkan User/Email yang akan DIHAPUS dari rute WARP (0 untuk batal)" user_hapus
      if [[ "$user_hapus" == "0" ]]; then return 0; fi
      if [[ -z "$user_hapus" ]]; then print_error "Input tidak boleh kosong."; pause_for_enter; return 1; fi
      
      if [[ "$user_hapus" == "user1" ]]; then
          print_error "User default 'user1' tidak dapat dihapus dari rute WARP."
          pause_for_enter
          return 1
      fi

      if ! echo "$rule_users_all_json" | jq -e --arg u "$user_hapus" '.[] | select(. == $u)' > /dev/null; then
        print_warn "User '$user_hapus' tidak ditemukan dalam daftar rute WARP."
        pause_for_enter
        return 1
      fi

      jq --arg user_hapus "$user_hapus" '(.routing.rules[] | select(.outboundTag == "warp" and .user != null) | .user) |= (del(.[] | select(. == $user_hapus)))' "$CONFIG" > "$tmp"

      if [ $? -eq 0 ]; then
        mv "$tmp" "$CONFIG"
        print_info "User '$user_hapus' berhasil DIHAPUS dari rute WARP."
        restart_xray
      else
        print_error "Gagal memperbarui konfigurasi. Periksa $tmp"
        rm -f "$tmp"
      fi
      ;;
      
    0) return 0 ;;
    *) print_error "Pilihan tidak valid."; sleep 1 ;;
  esac
  
  pause_for_enter
}
# ======================================================================
# --- AKHIR PERUBAHAN ---
# ======================================================================

# ======================================================================
# --- PERUBAHAN: rute_tambah_protokol_warp (Tambah/Hapus) ---
# ======================================================================
rute_tambah_protokol_warp() {
  clear
  # --- Judul Diubah ---
  print_header "Tambah/Hapus Protokol dari Rute WARP"
  
  # Daftar statis semua protokol yang bisa dipilih
  local ALL_PROTOCOLS=("vmess" "vless" "trojan" "shadowsocks" "http" "socks")
  
  # Ambil SEMUA tag dari aturan
  local rule_tags_all=$(jq -r '(.routing.rules[] | select(.outboundTag == "warp" and .inboundTag != null) | .inboundTag) // []' "$CONFIG")
  # Filter tag default "default" HANYA untuk tampilan
  local rule_tags_display=$(echo "$rule_tags_all" | jq -r '[.[] | select(. != "default")] | .[]')
  
  # Cari protokol yang BELUM ada di aturan WARP
  local tags_not_in_rule=$(comm -23 <(printf "%s\n" "${ALL_PROTOCOLS[@]}" | sort) <(echo "$rule_tags_all" | jq -r '.[]' | sort))
  
  # Tampilkan side-by-side (Fungsi 2 kolom asli)
  print_side_by_side "Protokol belum ke WARP" "$tags_not_in_rule" \
                     "Protokol sudah ke WARP" "$rule_tags_display"

  # --- Menu Aksi (BARU) ---
  echo ""
  print_menu_option "1)" "Tambah Protokol ke Rute WARP"
  print_menu_option "2)" "Hapus Protokol dari Rute WARP"
  echo ""
  print_menu_option "0)" "Kembali"
  
  print_menu_prompt "Pilih Opsi (0-2)" sub_opt
  
  local tmp="$CONFIG.tmp.$$"

  case "$sub_opt" in
    1) # Tambah
      echo -e "\n${B_CYAN}InboundTag yang tersedia: vmess, vless, trojan, shadowsocks, http, socks${RESET}"
      print_menu_prompt "Masukkan InboundTag yang akan dirutekan ke WARP (0 untuk batal)" proto_baru
      if [[ "$proto_baru" == "0" ]]; then return 0; fi
      if [[ -z "$proto_baru" ]]; then print_error "Input tidak boleh kosong."; pause_for_enter; return 1; fi

      # Validasi apakah input ada di ALL_PROTOCOLS
      local valid_proto=0
      for p in "${ALL_PROTOCOLS[@]}"; do
        if [[ "$p" == "$proto_baru" ]]; then
          valid_proto=1
          break
        fi
      done
      
      if [[ "$valid_proto" -eq 0 ]]; then
        print_error "Protokol '$proto_baru' tidak valid. Pilih dari daftar yang tersedia."
        pause_for_enter
        return 1
      fi

      if echo "$rule_tags_all" | jq -e --arg p "$proto_baru" '.[] | select(. == $p)' > /dev/null; then
        print_warn "Protokol '$proto_baru' sudah ada dalam daftar rute WARP."
        pause_for_enter
        return 1
      fi

      jq --arg proto_baru "$proto_baru" '(.routing.rules[] | select(.outboundTag == "warp" and .inboundTag != null) | .inboundTag) |= (. + [$proto_baru] | unique)' "$CONFIG" > "$tmp"
      
      if [ $? -eq 0 ]; then
        mv "$tmp" "$CONFIG"
        print_info "Protokol '$proto_baru' berhasil ditambahkan ke rute WARP."
        restart_xray
      else
        print_error "Gagal memperbarui konfigurasi. Periksa $tmp"
        rm -f "$tmp"
      fi
      ;;

    2) # Hapus (BARU)
      print_menu_prompt "Masukkan Protokol yang akan DIHAPUS dari rute WARP (0 untuk batal)" proto_hapus
      if [[ "$proto_hapus" == "0" ]]; then return 0; fi
      if [[ -z "$proto_hapus" ]]; then print_error "Input tidak boleh kosong."; pause_for_enter; return 1; fi
      
      if [[ "$proto_hapus" == "default" ]]; then
          print_error "Protokol 'default' tidak dapat dihapus dari rute WARP."
          pause_for_enter
          return 1
      fi

      if ! echo "$rule_tags_all" | jq -e --arg p "$proto_hapus" '.[] | select(. == $p)' > /dev/null; then
        print_warn "Protokol '$proto_hapus' tidak ditemukan dalam daftar rute WARP."
        pause_for_enter
        return 1
      fi

      jq --arg proto_hapus "$proto_hapus" '(.routing.rules[] | select(.outboundTag == "warp" and .inboundTag != null) | .inboundTag) |= (del(.[] | select(. == $proto_hapus)))' "$CONFIG" > "$tmp"

      if [ $? -eq 0 ]; then
        mv "$tmp" "$CONFIG"
        print_info "Protokol '$proto_hapus' berhasil DIHAPUS dari rute WARP."
        restart_xray
      else
        print_error "Gagal memperbarui konfigurasi. Periksa $tmp"
        rm -f "$tmp"
      fi
      ;;
      
    0) return 0 ;;
    *) print_error "Pilihan tidak valid."; sleep 1 ;;
  esac
  
  pause_for_enter
}
# ======================================================================
# --- AKHIR PERUBAHAN ---
# ======================================================================


# Poin 2: Sub-menu untuk "Rute Manajemen"
aksi_rute_manajemen() {
  while true; do
    clear
    print_header "RUTE MANAJEMEN (WARP)"
    print_menu_option "1)" "Blokir Akun (User/Email)"
    print_menu_option "2)" "Atur Rute Website (WARP/Direct)"
    print_menu_option "3)" "Atur Semua Koneksi (WARP/Direct)"
    print_menu_option "4)" "Atur Koneksi ke WARP (by User/Email)"
    print_menu_option "5)" "Atur Koneksi ke WARP (by Protokol)"
    echo ""
    print_menu_option "0)" "Kembali ke Menu Utama"

    print_menu_prompt "Pilih Opsi (0-5)" m
    
    case "$m" in
      1) rute_blokir_akun ;;
      2) rute_toggle_website ;;
      3) rute_toggle_semua ;;
      4) rute_tambah_user_warp ;;
      5) rute_tambah_protokol_warp ;; # Ini sekarang memiliki sub-menu
      0) return 0 ;;
      *) print_error "Pilihan tidak valid."; sleep 1 ;;
    esac
  done
}

# ======================================================================
# --- MENU UTAMA (DIPERBARUI) ---
# ======================================================================

main_menu(){
  while true; do
    print_banner
    # --- HEADER INFO BARU DITAMBAHKAN ---
    print_system_header
    
    print_menu_option "1)" "Buat akun"
    print_menu_option "2)" "Hapus akun"
    print_menu_option "3)" "Perpanjang akun"
    print_menu_option "4)" "Daftar Akun"
    # --- Garis pemisah lama dihapus dari sini ---
    print_menu_option "5)" "Rute Manajemen (WARP)"
    print_menu_option "6)" "Ganti domain"
    print_menu_option "7)" "Tambah host (Subdomain)"
    print_menu_option "8)" "About"
    echo ""
    print_menu_option "0)" "Keluar"
    
    print_menu_prompt "Pilih Opsi (0-8)" m
    
    case "$m" in
      1) aksi_buat ;;
      2) aksi_hapus ;;
      3) aksi_perpanjang ;;
      4) aksi_daftar_akun ;;
      5) aksi_rute_manajemen ;; # Poin 1: Menu baru ditambahkan
      6) aksi_ganti_domain ;;
      7) aksi_tambah_host ;;
      8) aksi_about ;;
      0) exit 0 ;;
      *) print_error "Pilihan tidak valid."; sleep 1 ;;
    esac
  done
}
# ======================================================================
# --- AKHIR PERUBAHAN ---
# ======================================================================

# ====== Bootstrap ======
need_root
# Pastikan 'paste' dan 'comm' ada
# --- DIPERBARUI: Menambahkan uptime, free, dan numfmt ---
need_cmd jq awk sed grep systemctl nginx date base64 curl openssl paste comm mktemp uptime free numfmt
ensure_dirs
main_menu

