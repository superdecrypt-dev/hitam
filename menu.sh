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
QUOTA_DB="$ASSET_DIR/quota.db"
XRAY_BIN="/usr/local/bin/xray"
XRAY_API_SERVER="127.0.0.1:10000"

# Web panel
WEB_PANEL_DIR="$ASSET_DIR/webpanel"
WEB_PANEL_ACCOUNTS_DIR="$WEB_PANEL_DIR/accounts"

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

get_service_status() {
    local service="$1"
    if systemctl is-active --quiet "$service"; then
        echo -e "${B_GREEN}● Aktif${RESET}"
    else
        echo -e "${B_RED}○ Nonaktif${RESET}"
    fi
}

# Deteksi interface utama (default route) secara otomatis
detect_main_interface() {
    local iface=""

    # 1. Coba pakai ip route (paling akurat)
    if command -v ip >/dev/null 2>&1; then
        iface=$(ip route get 1.1.1.1 2>/dev/null | awk '
            /dev/ {
                for (i = 1; i <= NF; i++) {
                    if ($i == "dev") { print $(i+1); exit }
                }
            }')

        # fallback: default route biasa
        if [[ -z "$iface" ]]; then
            iface=$(ip route show default 2>/dev/null | awk '
                /default/ {
                    for (i = 1; i <= NF; i++) {
                        if ($i == "dev") { print $(i+1); exit }
                    }
                }')
        fi
    fi

    # 2. Kalau ip nggak ada / gagal, ambil interface pertama selain lo
    if [[ -z "$iface" && -d /sys/class/net ]]; then
        iface=$(ls /sys/class/net 2>/dev/null | awk '$1 != "lo" {print; exit}')
    fi

    # 3. Last resort, pakai eth0
    echo "${iface:-eth0}"
}

# --- PERBAIKAN: Fungsi ambil trafik (gabungan in/out) ---
get_xray_total_traffic() {
    # Sekarang ini artinya "trafik total server", bukan dari API Xray lagi
    local iface
    iface=$(detect_main_interface)

    local rx_bytes tx_bytes

    # Prioritas: pakai /sys (modern)
    if [[ -r "/sys/class/net/$iface/statistics/rx_bytes" ]]; then
        rx_bytes=$(<"/sys/class/net/$iface/statistics/rx_bytes")
        tx_bytes=$(<"/sys/class/net/$iface/statistics/tx_bytes")
    else
        # Fallback: /proc/net/dev
        read rx_bytes tx_bytes <<< "$(
            awk -v dev="$iface:" '
                $1 == dev {
                    gsub(":", "", $1);
                    # kolom 2 = RX bytes, kolom 10 = TX bytes
                    print $2, $10
                }' /proc/net/dev 2>/dev/null
        )"
    fi

    rx_bytes=${rx_bytes:-0}
    tx_bytes=${tx_bytes:-0}

    local rx_fmt tx_fmt
    rx_fmt=$(numfmt --to=iec --suffix=B "$rx_bytes" 2>/dev/null || echo "${rx_bytes}B")
    tx_fmt=$(numfmt --to=iec --suffix=B "$tx_bytes" 2>/dev/null || echo "${tx_bytes}B")

    # ▲ = TX (up), ▼ = RX (down)
    echo -e "${B_GREEN}▲ $tx_fmt${RESET} / ${B_RED}▼ $rx_fmt${RESET} ${CYAN}($iface)${RESET}"
}
# --- AKHIR FUNGSI TRAFIK ---

# Format bytes ke bentuk manusiawi (KB/MB/GB)
bytes_to_human(){
  local b="${1:-0}"
  numfmt --to=iec --suffix=B "$b" 2>/dev/null || echo "${b}B"
}

# Update pemakaian semua user di QUOTA_DB berdasarkan Xray Stats
quota_update_usage(){
  # Kalau quota.db kosong, nggak ada yang perlu diupdate
  if [[ ! -s "$QUOTA_DB" ]]; then
    return 0
  fi

  local _XRAY_BIN="/usr/local/bin/xray"
  local _XRAY_API_SERVER="127.0.0.1:10000"
  local APIDATA=""

  if [[ -x "$_XRAY_BIN" ]]; then
    APIDATA=$("$_XRAY_BIN" api statsquery --server="$_XRAY_API_SERVER" 2>/dev/null | awk '
      /"name"/ {
        gsub(/"|,/, "", $2);
        split($2, p, ">>>");
        key = p[1] ":" p[2] "->" p[4];
        next;
      }
      /"value"/ {
        gsub(/[,]/, "", $2);
        print key "\t" $2;
      }
    ')
  fi

  # Kalau gagal ambil stats, jangan rusak DB, langsung keluar
  if [[ -z "$APIDATA" ]]; then
    return 0
  fi

  local tmp="$QUOTA_DB.tmp.$$"
  > "$tmp"

  while IFS='|' read -r u q used last_up last_down; do
    [[ -z "$u" ]] && continue

    # Default jika kolom lama (kalau suatu saat ada upgrade format)
    [[ -z "$used" ]] && used=0
    [[ -z "$last_up" ]] && last_up=0
    [[ -z "$last_down" ]] && last_down=0

    # Ambil traffic terkini user u
    local curr_up curr_down
    curr_up=$(echo "$APIDATA" | awk -v u="$u" '$1 ~ "^user:"u"->uplink"   {sum+=$2} END{if(sum=="")sum=0; printf "%.0f", sum}')
    curr_down=$(echo "$APIDATA" | awk -v u="$u" '$1 ~ "^user:"u"->downlink" {sum+=$2} END{if(sum=="")sum=0; printf "%.0f", sum}')

    # Hitung delta (jaga-jaga kalau counter reset saat Xray di-restart)
    local du dd
    if (( curr_up >= last_up )); then
      du=$((curr_up - last_up))
    else
      du=$curr_up
    fi

    if (( curr_down >= last_down )); then
      dd=$((curr_down - last_down))
    else
      dd=$curr_down
    fi

    local new_used=$used
    new_used=$(( new_used + du + dd ))

    echo "$u|$q|$new_used|$curr_up|$curr_down" >> "$tmp"
  done < "$QUOTA_DB"

  mv "$tmp" "$QUOTA_DB"
}

# Tambahkan user ke rule 'blocked' khusus sistem kuota (rule yang mengandung "quota" di .user)
quota_block_user_norestart(){
  local user="$1"
  local tmp="$CONFIG.tmp.$$"

  # Ambil semua user dari rule blocked yang punya array .user dan mengandung "quota"
  local quota_rule_users_json
  quota_rule_users_json=$(jq -r '
    [
      .routing.rules[]
      | select(.outboundTag == "blocked"
               and (.user|type=="array")
               and (.user | index("quota") != null))
      | .user
    ] | add // []' "$CONFIG")

  # Kalau user sudah ada di rule kuota, tidak perlu ditambah lagi
  if echo "$quota_rule_users_json" | jq -e --arg u "$user" '.[] | select(. == $u)' > /dev/null 2>&1; then
    return 1
  fi

  # Tambahkan user hanya ke rule yang punya array .user dan mengandung "quota"
  if jq --arg user "$user" '
    (.routing.rules[]
      | select(.outboundTag == "blocked"
               and (.user|type=="array")
               and (.user | index("quota") != null))
      | .user) |= (. + [$user] | unique)
  ' "$CONFIG" > "$tmp"; then
    mv "$tmp" "$CONFIG"
    return 0
  else
    rm -f "$tmp"
    return 1
  fi
}

# Set / Ubah kuota user
quota_set_user(){
  clear
  print_header "SET / UBAH KUOTA AKUN"

  # === TAMPILAN HEADER INFORMASI (mirip quota_list_status) ===
  if [[ -s "$QUOTA_DB" ]]; then
    # Update pemakaian dulu biar data fresh
    quota_update_usage

    printf "  %-15s | %-12s | %-12s | %-12s | %-8s\n" "User" "Kuota" "Terpakai" "Sisa" "Status"
    echo   "  -------------------------------------------------------------------------------"

    while IFS='|' read -r u q used last_up last_down; do
      [[ -z "$u" ]] && continue
      [[ -z "$used" ]] && used=0

      local sisa=$(( q > used ? q - used : 0 ))
      local status="AKTIF"
      if (( used >= q )); then
        status="HABIS"
      fi

      printf "  %-15s | %-12s | %-12s | %-12s | %-8s\n" \
        "$u" "$(bytes_to_human "$q")" "$(bytes_to_human "$used")" "$(bytes_to_human "$sisa")" "$status"
    done < "$QUOTA_DB"

    echo   "  -------------------------------------------------------------------------------"
    echo ""  # spasi sebelum input
  else
    print_warn "Belum ada akun yang memiliki kuota. Isian di bawah akan membuat kuota baru."
    echo ""
  fi
  # === AKHIR HEADER INFORMASI ===

  print_menu_prompt "Masukkan username (0 untuk batal)" q_user
  if [[ "$q_user" == "0" ]]; then return 0; fi
  if [[ -z "$q_user" ]]; then
    print_error "Username tidak boleh kosong."
    pause_for_enter; return 1
  fi

  # Cek apakah user ada di ledger
  if ! grep -R -q "^${q_user}|" "$ACCOUNTS_DIR"/*.db 2>/dev/null; then
    print_error "User '$q_user' tidak ditemukan di ledger akun."
    pause_for_enter; return 1
  fi

  print_menu_prompt "Masukkan kuota (dalam GB, contoh: 10)" q_gb
  if [[ ! "$q_gb" =~ ^[0-9]+$ ]]; then
    print_error "Kuota harus angka (GB)."
    pause_for_enter; return 1
  fi

  local quota_bytes=$((q_gb * 1024 * 1024 * 1024))

  # Ambil traffic sekarang untuk dijadikan baseline
  local _XRAY_BIN="/usr/local/bin/xray"
  local _XRAY_API_SERVER="127.0.0.1:10000"
  local curr_up=0
  local curr_down=0

  if [[ -x "$_XRAY_BIN" ]]; then
    local APIDATA
    APIDATA=$("$_XRAY_BIN" api statsquery --server="$_XRAY_API_SERVER" 2>/dev/null | awk '
      /"name"/ {
        gsub(/"|,/, "", $2);
        split($2, p, ">>>");
        key = p[1] ":" p[2] "->" p[4];
        next;
      }
      /"value"/ {
        gsub(/[,]/, "", $2);
        print key "\t" $2;
      }
    ')
    if [[ -n "$APIDATA" ]]; then
      curr_up=$(echo "$APIDATA" | awk -v u="$q_user" '$1 ~ "^user:"u"->uplink"   {sum+=$2} END{if(sum=="")sum=0; printf "%.0f", sum}')
      curr_down=$(echo "$APIDATA" | awk -v u="$q_user" '$1 ~ "^user:"u"->downlink" {sum+=$2} END{if(sum=="")sum=0; printf "%.0f", sum}')
    fi
  fi

  # Tulis / update quota.db: user|quota_bytes|used_bytes|last_up|last_down
  local tmp="$QUOTA_DB.tmp.$$"
  # Buang entri lama user (kalau ada)
  grep -v "^$q_user|" "$QUOTA_DB" 2>/dev/null > "$tmp" || true
  echo "$q_user|$quota_bytes|0|$curr_up|$curr_down" >> "$tmp"
  mv "$tmp" "$QUOTA_DB"

  print_info "Kuota untuk user '$q_user' diset ke $(bytes_to_human "$quota_bytes")."
  print_info "Perhitungan dimulai dari pemakaian saat ini."
  pause_for_enter
}

# Buka blokir akun yang diblokir oleh sistem kuota
quota_unblock_user(){
  clear
  print_header "BUKA NONAKTIFKAN AKUN KUOTA"

  # Ambil semua user dari rule 'blocked' yang dipakai sistem kuota (mengandung "quota" di array .user)
  local quota_rule_users_json
  quota_rule_users_json=$(jq -r '
    [
      .routing.rules[]
      | select(.outboundTag == "blocked"
               and (.user|type=="array")
               and (.user | index("quota") != null))
      | .user
    ] | add // []' "$CONFIG")

  # Konversi ke list baris-per-baris dan buang entri "quota" (system sentinel)
  local quota_rule_users
  quota_rule_users=$(echo "$quota_rule_users_json" | jq -r '.[]' 2>/dev/null | grep -v '^quota$' || true)

  if [[ -z "$quota_rule_users" ]]; then
    print_warn "Tidak ada akun yang sedang dinonaktifkan oleh sistem kuota."
    pause_for_enter
    return 0
  fi

  # Ambil map user|proto dari ledger
  local all_users_map
  all_users_map=$(get_all_created_users_map)

  local blocked_proto_list=""
  local blocked_user_list=""

  while read -r u; do
    [[ -z "$u" ]] && continue
    local proto
    proto=$(echo "$all_users_map" | awk -F'|' -v uu="$u" '$1==uu {print $2; exit}')
    [[ -z "$proto" ]] && proto="-"
    blocked_proto_list+="$proto\n"
    blocked_user_list+="$u\n"
  done <<< "$quota_rule_users"

  echo -e "${B_WHITE}Daftar akun yang dinonaktifkan oleh sistem kuota:${RESET}"
  print_side_by_side "Protokol" "$(echo -e "$blocked_proto_list")" \
                     "User dinonaktifkan" "$(echo -e "$blocked_user_list")"

  print_menu_prompt "Masukkan username yang akan di aktifkan (0 untuk batal)" q_user
  if [[ "$q_user" == "0" ]]; then return 0; fi
  if [[ -z "$q_user" ]]; then
    print_error "Username tidak boleh kosong."
    pause_for_enter
    return 1
  fi

  # Pastikan username memang ada di daftar blokir kuota
  if ! echo "$quota_rule_users" | grep -qx "$q_user"; then
    print_warn "User '$q_user' tidak ditemukan akun berstatus nonaktif karena kuota."
    pause_for_enter
    return 1
  fi

  local tmp="$CONFIG.tmp.$$"
  # Hapus user itu dari rule 'blocked' yang punya "quota"
  if jq --arg user "$q_user" '
    (.routing.rules[]
      | select(.outboundTag == "blocked"
               and (.user|type=="array")
               and (.user | index("quota") != null))
      | .user) |= (del(.[] | select(. == $user)))
  ' "$CONFIG" > "$tmp"; then
    mv "$tmp" "$CONFIG"
    print_info "User '$q_user' berhasil di aktifkan."
    restart_xray
  else
    rm -f "$tmp"
    print_error "Gagal memperbarui konfigurasi Xray."
  fi

  pause_for_enter
}

# Reset kuota user (pakai kuota yang sama, pemakaian direset ke 0 dan di-unblock)
quota_delete_user(){
  clear
  print_header "RESET KUOTA AKUN"

  if [[ ! -s "$QUOTA_DB" ]]; then
    print_warn "Belum ada akun yang memiliki kuota."
    pause_for_enter; return 0
  fi

  # Sync dulu pemakaian supaya last_up/last_down = trafik terkini
  quota_update_usage

  echo -e "${B_WHITE}Daftar akun yang punya kuota:${RESET}"
  awk -F'|' '{printf "  %d. %s\n", NR, $1}' "$QUOTA_DB"
  echo ""

  print_menu_prompt "Masukkan username yang akan di-reset kuotanya (0 untuk batal)" q_user
  if [[ "$q_user" == "0" ]]; then return 0; fi
  if [[ -z "$q_user" ]]; then
    print_error "Username tidak boleh kosong."
    pause_for_enter; return 1
  fi

  # Pastikan user ada di quota.db
  if ! grep -q "^$q_user|" "$QUOTA_DB"; then
    print_warn "User '$q_user' tidak ditemukan di quota.db."
    pause_for_enter
    return 0
  fi

  # Reset kolom 'used' ke 0, kuota (q) & last_up/last_down tetap (sudah current)
  local tmp="$QUOTA_DB.tmp.$$"
  : > "$tmp"
  while IFS='|' read -r u q used last_up last_down; do
    [[ -z "$u" ]] && continue
    [[ -z "$used" ]] && used=0
    [[ -z "$last_up" ]] && last_up=0
    [[ -z "$last_down" ]] && last_down=0

    if [[ "$u" == "$q_user" ]]; then
      used=0
    fi

    echo "$u|$q|$used|$last_up|$last_down" >> "$tmp"
  done < "$QUOTA_DB"
  mv "$tmp" "$QUOTA_DB"

  print_info "Pemakaian kuota user '$q_user' telah di-reset ke 0 (batas kuota tetap)."

  # Hapus user ini dari rule 'blocked' khusus kuota (jika pernah diblokir)
  local cfg_tmp="$CONFIG.tmp.$$"
  if jq --arg user "$q_user" '
    (.routing.rules[]
      | select(.outboundTag == "blocked"
               and (.user|type=="array")
               and (.user | index("quota") != null))
      | .user) |= (del(.[] | select(. == $user)))
  ' "$CONFIG" > "$cfg_tmp"; then
    mv "$cfg_tmp" "$CONFIG"
    print_info "User '$q_user' juga dihapus dari daftar nonaktifkuota."
    restart_xray
  else
    rm -f "$cfg_tmp"
    print_warn "Gagal memperbarui konfigurasi Xray saat menghapus status nonaktif kuota user '$q_user'."
  fi

  pause_for_enter
}

# Tampilkan status kuota semua akun (setelah update pemakaian)
quota_list_status(){
  clear
  print_header "STATUS KUOTA AKUN"

  if [[ ! -s "$QUOTA_DB" ]]; then
    print_warn "Belum ada akun yang memiliki kuota."
    pause_for_enter; return 0
  fi

  # Update pemakaian dulu
  quota_update_usage

  # Sinkronkan tampilan kuota di web panel
  sync_quota_to_webpanel

  printf "  %-15s | %-12s | %-12s | %-12s | %-8s\n" "User" "Kuota" "Terpakai" "Sisa" "Status"
  echo   "  -------------------------------------------------------------------------------"

  while IFS='|' read -r u q used last_up last_down; do
    [[ -z "$u" ]] && continue
    [[ -z "$used" ]] && used=0

    local sisa=$(( q > used ? q - used : 0 ))
    local status="AKTIF"
    if (( used >= q )); then
      status="HABIS"
    fi

    printf "  %-15s | %-12s | %-12s | %-12s | %-8s\n" \
      "$u" "$(bytes_to_human "$q")" "$(bytes_to_human "$used")" "$(bytes_to_human "$sisa")" "$status"
  done < "$QUOTA_DB"

  echo   "  -------------------------------------------------------------------------------"
  pause_for_enter
}

# Cek kuota dan blokir akun yang habis
quota_enforce_now(){
  clear
  print_header "CEK & NONAKTIFKAN AKUN HABIS KUOTA"

  if [[ ! -s "$QUOTA_DB" ]]; then
    print_warn "Tidak ada akun yang diatur kuotanya."
    pause_for_enter; return 0
  fi

  # Update pemakaian dulu
  quota_update_usage

  # Sinkronkan tampilan kuota di web panel
  sync_quota_to_webpanel

  local need_restart=0

  while IFS='|' read -r u q used last_up last_down; do
    [[ -z "$u" ]] && continue
    [[ -z "$used" ]] && used=0

    if (( used >= q )); then
      if quota_block_user_norestart "$u"; then
        print_warn "Kuota user '$u' HABIS → ditambahkan ke daftar nonaktif."
        need_restart=1
      else
        print_info "User '$u' sudah dalam daftar nonaktif."
      fi
    fi
  done < "$QUOTA_DB"

  if (( need_restart == 1 )); then
    restart_xray
  else
    print_info "Tidak ada perubahan pada daftar nonaktif (belum ada kuota yang habis)."
  fi

  pause_for_enter
}

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
    echo -e "  ${B_WHITE}Trafik Total Server:${RESET} $total_traffic"

    echo -e "  ${B_WHITE}Status Layanan:${RESET}"
    echo -e "    ${CYAN}Xray:${RESET}      $xray_status  |  ${CYAN}Nginx:${RESET}     $nginx_status  |  ${CYAN}Wireproxy:${RESET} $wireproxy_status"
    
    print_line "-" "$CYAN"
}

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

# ====== Cek & Buat Direktori (UPDATED) ======
ensure_dirs(){
  local protos=("vmess" "vless" "trojan" "http" "socks" "shadowsocks")
  for p in "${protos[@]}"; do
    # DB + txt akun
    if [[ ! -d "$ACCOUNTS_DIR/$p" ]]; then
      mkdir -p "$ACCOUNTS_DIR/$p"
    fi
    if [[ ! -f "$ACCOUNTS_DIR/$p.db" ]]; then
      touch "$ACCOUNTS_DIR/$p.db"
    fi

    # HTML akun
    mkdir -p "$WEB_PANEL_ACCOUNTS_DIR/$p"
  done
  
  if [[ ! -f "$HOSTS_FILE" ]]; then touch "$HOSTS_FILE"; fi
  if [[ ! -f "$QUOTA_DB" ]]; then touch "$QUOTA_DB"; fi
  mkdir -p "$WEB_PANEL_DIR"
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

restart_xray(){
  # Restart Nginx, Xray, dan Wireproxy setiap ada perubahan penting
  if ! run_task "Me-restart layanan Nginx" "systemctl restart nginx"; then
      print_warn "Layanan Nginx gagal restart. Cek status."
  fi

  if ! run_task "Me-restart layanan Xray" "systemctl restart xray"; then
      print_warn "Layanan Xray gagal restart. Cek status."
  fi

  # Wireproxy opsional: kalau belum terpasang, abaikan error-nya
  if ! run_task "Me-restart layanan Wireproxy" "systemctl restart wireproxy"; then
      print_warn "Layanan Wireproxy gagal restart (abaikan jika belum terpasang)."
  fi

  # Kasih jeda sedikit biar semua service stabil
  sleep 0.5
}


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
ledger_add(){ 
    local quota="${6:-0}" # Default 0 (unlimited) jika tidak ada
    echo "$2|$3|$4|$5|$quota" >> "$ACCOUNTS_DIR/$1.db"; 
}

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
  local proto="$1" user="$2" add="$3"
  local db="$ACCOUNTS_DIR/$proto.db"
  local db_tmp="$ACCOUNTS_DIR/$proto.db.tmp"
  
  [[ ! -f "$db" ]] && return 1
  local line=$(grep "^$user|" "$db" || true)
  [[ -z "$line" ]] && return 1
  
  local secret=$(echo "$line" | cut -d'|' -f2)
  local cur_exp=$(echo "$line" | cut -d'|' -f3)
  local created=$(echo "$line" | cut -d'|' -f4)
  local quota=$(echo "$line" | cut -d'|' -f5)
  [[ -z "$quota" ]] && quota="0" # Handle legacy format

  local newexp=$(date -d "$cur_exp + $add days" +%F)
  
  grep -v "^$user|" "$db" > "$db_tmp"
  echo "$user|$secret|$newexp|$created|$quota" >> "$db_tmp"
  mv "$db_tmp" "$db"
  
  # Update file txt
  local txt_file="$ACCOUNTS_DIR/$proto/$user-$proto.txt"
  if [[ -f "$txt_file" ]]; then
      sed -i "s/^Expired[[:space:]]*: .*/Expired    : $newexp/" "$txt_file"
  fi
}

show_account_list_by_proto(){
  local p="$1"
  local db_file="$ACCOUNTS_DIR/$p.db"
  echo -e "\n${B_WHITE}Daftar Akun ${p^^} yang sudah ada:${RESET}"
  printf "  %-15s | %-12s | %-12s\n" "Username" "Dibuat" "Expired"
  echo "  ---------------------------------------------"
  if [[ -f "$db_file" ]]; then
    while IFS='|' read -r u s e c q; do
  [[ -z "$c" ]] && c="-"
  printf "  %-15s | %-12s | %-12s\n" "$u" "$c" "$e"
    done < "$db_file"
  fi
  echo "  ---------------------------------------------"
}

refresh_account_html(){
  local proto="$1"
  local user="$2"

  local domain
  domain="$(get_domain)"

  local db="$ACCOUNTS_DIR/$proto.db"
  [[ ! -f "$db" ]] && return 1

  local line
  line=$(grep "^$user|" "$db" | head -n1 || true)
  [[ -z "$line" ]] && return 1

  local secret created exp quota
  secret=$(echo "$line"  | cut -d'|' -f2)
  exp=$(echo "$line"     | cut -d'|' -f3)
  created=$(echo "$line" | cut -d'|' -f4)
  quota=$(echo "$line"   | cut -d'|' -f5)

  local path
  path="$(get_ws_path "$proto")"

  local link_tls="" link_nontls="" notes=""

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
      ;;
    socks)
      link_tls="$(socks_link_tls "$secret" "$domain" "$user" "$path")"
      link_nontls="$(socks_link_nontls "$secret" "$domain" "$user" "$path")"
      ;;
  esac

  render_account_html "$proto" "$user" "$domain" "$path" "$secret" "$exp" "$created" "$link_tls" "$link_nontls"
}

delete_account_html(){
  local proto="$1"
  local user="$2"

  local f="$WEB_PANEL_ACCOUNTS_DIR/$proto/$user.html"
  if [[ -f "$f" ]]; then
    rm -f "$f"
    print_info "Halaman web akun dihapus: $f"
  fi
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
               notes="--- Catatan Penting ---
  - Wajib menggunakan aplikasi Exclave (bisa cari di internet)
  - Untuk Websocket harus input manual seperti path websocket"
               ;;
             socks)
               link_tls="$(socks_link_tls "$secret" "$new_domain" "$user" "$path")"
               link_nontls="$(socks_link_nontls "$secret" "$new_domain" "$user" "$path")"
               notes="--- Catatan Penting ---
  - Wajib menggunakan aplikasi Exclave (bisa cari di internet)
  - Untuk Websocket harus input manual seperti path websocket"
               ;;
           esac

# ====== PANEL WEB: GENERATE ULANG HALAMAN HTML ======
         render_account_html "$proto" "$user" "$new_domain" "$path" "$secret" "$exp" "$created" "$link_tls" "$link_nontls"

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
Web Panel  : https://$new_domain/panel/accounts/$proto/$user.html

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
  rebuild_web_index
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

  # === Kuota (GB) ===
  print_menu_prompt "Kuota (GB, 0 = unlimited)" quota
  quota="${quota:-0}"
  while [[ ! "$quota" =~ ^[0-9]+$ ]]; do
    print_error "Kuota harus angka (GB)!"
    print_menu_prompt "Kuota (GB, 0 = unlimited)" quota
    quota="${quota:-0}"
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
  
  created="$(date +%F)"; exp="$(date -d "+$days days" +%F)"; ledger_add "$proto" "$user" "$secret" "$exp" "$created" "$quota"
  
# === Integrasi: jika kuota > 0, langsung daftarkan ke QUOTA_DB ===
  if (( quota > 0 )); then
    local quota_bytes=$((quota * 1024 * 1024 * 1024))
    local _XRAY_BIN="/usr/local/bin/xray"
    local _XRAY_API_SERVER="127.0.0.1:10000"
    local curr_up=0
    local curr_down=0

    if [[ -x "$_XRAY_BIN" ]]; then
      local APIDATA
      APIDATA=$("$_XRAY_BIN" api statsquery --server="$_XRAY_API_SERVER" 2>/dev/null | awk '
        /"name"/ {
          gsub(/"|,/, "", $2);
          split($2, p, ">>>");
          key = p[1] ":" p[2] "->" p[4];
          next;
        }
        /"value"/ {
          gsub(/[,]/, "", $2);
          print key "\t" $2;
        }
      ')
      if [[ -n "$APIDATA" ]]; then
        curr_up=$(echo "$APIDATA"   | awk -v u="$user" '$1 ~ "^user:"u"->uplink"   {sum+=$2} END{if(sum=="")sum=0; printf "%.0f", sum}')
        curr_down=$(echo "$APIDATA" | awk -v u="$user" '$1 ~ "^user:"u"->downlink" {sum+=$2} END{if(sum=="")sum=0; printf "%.0f", sum}')
      fi
    fi

    # Tulis / update quota.db: user|quota_bytes|used_bytes|last_up|last_down
    local tmpq="$QUOTA_DB.tmp.$$"
    grep -v "^$user|" "$QUOTA_DB" 2>/dev/null > "$tmpq" || true
    echo "$user|$quota_bytes|0|$curr_up|$curr_down" >> "$tmpq"
    mv "$tmpq" "$QUOTA_DB"
  fi
  
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
      notes="--- Catatan Penting ---
  - Wajib menggunakan aplikasi Exclave (bisa cari di internet)
  - Untuk Websocket harus input manual seperti path websocket"
      ;;
    socks)
      link_tls="$(socks_link_tls "$secret" "$domain" "$user" "$path")"
      link_nontls="$(socks_link_nontls "$secret" "$domain" "$user" "$path")"
      notes="--- Catatan Penting ---
  - Wajib menggunakan aplikasi Exclave (bisa cari di internet)
  - Untuk Websocket harus input manual seperti path websocket"
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
Web Panel  : https://$domain/panel/accounts/$proto/$user.html

--- Link TLS (Port 443) ---
${link_tls}

--- Link Non-TLS/HTTP (Port 80) ---
${link_nontls}

${notes}
=========================================
EOF

  # === baru: generate halaman HTML & index web panel ===
  render_account_html "$proto" "$user" "$domain" "$path" "$secret" "$exp" "$created" "$link_tls" "$link_nontls"
  rebuild_web_index

  clear
  cat "$file_out"
  echo ""
  print_info "Data disimpan di: $file_out"
  print_info "Halaman web akun: https://$domain/panel/accounts/$proto/$user.html"
  pause_for_enter
}

aksi_hapus(){
  clear; print_header "HAPUS AKUN"
  
  echo -e "\n${B_WHITE}Daftar Semua Akun:${RESET}"
  printf "  %-12s | %-15s | %-12s | %-12s\n" "Proto" "User" "Dibuat" "Expired"
  echo "  -------------------------------------------------------------"
  for p in vmess vless trojan http socks shadowsocks; do
    f="$ACCOUNTS_DIR/$p.db"
    [[ -f "$f" ]] && while IFS='|' read -r u s e c q; do
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

  # Hapus kuota user (jika ada) dari quota.db
  if [[ -f "$QUOTA_DB" ]]; then
      local tmpq="$QUOTA_DB.tmp.$$"
      grep -v "^$user|" "$QUOTA_DB" > "$tmpq" 2>/dev/null || true
      mv "$tmpq" "$QUOTA_DB"
      print_info "Entri kuota untuk user '$user' dihapus dari quota.db (jika ada)."
  fi
  
  # ====== PANEL WEB: HAPUS HALAMAN HTML + UPDATE INDEX ======
  delete_account_html "$proto" "$user"
  rebuild_web_index
  
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
          while IFS='|' read -r u s e c q; do
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
  restart_xray
  # ====== PANEL WEB: REFRESH HALAMAN AKUN + INDEX ======
  refresh_account_html "$proto" "$user"
  rebuild_web_index
  
  pause_for_enter
}

# Ambil ringkasan kuota untuk user (Total / Terpakai) dalam format manusia
get_quota_brief_for_user(){
  local u="$1"
  if [[ ! -s "$QUOTA_DB" ]]; then
    echo "-"
    return
  fi
  local line
  line=$(grep "^$u|" "$QUOTA_DB" 2>/dev/null | head -n1 || true)
  if [[ -z "$line" ]]; then
    echo "-"
    return
  fi
  local q used
  q=$(echo "$line"   | cut -d'|' -f2)
  used=$(echo "$line"| cut -d'|' -f3)
  [[ -z "$used" ]] && used=0
  echo "$(bytes_to_human "$q") / $(bytes_to_human "$used")"
}

aksi_daftar_akun(){
  clear
  print_header "DAFTAR AKUN"

  # Update pemakaian kuota dulu kalau ada DB
  if [[ -s "$QUOTA_DB" ]]; then
    quota_update_usage
    sync_quota_to_webpanel
  fi

  printf "  %-4s | %-12s | %-15s | %-12s | %-12s | %-18s\n" \
         "No" "Proto" "User" "Dibuat" "Expired" "Kuota (Total/Pakai)"
  echo "  ---------------------------------------------------------------------------------------------"
  
  local n=1
  
  read_db(){
    local p="$1"
    local f="$ACCOUNTS_DIR/$p.db"
    if [[ -f "$f" ]]; then
      while IFS='|' read -r u s e c q; do
        [[ -z "$u" ]] && continue
        [[ -z "$c" ]] && c="-"
        local qinfo
        qinfo=$(get_quota_brief_for_user "$u")
        printf "  %-4s | %-12s | %-15s | %-12s | %-12s | %-18s\n" \
               "$n" "${p^^}" "$u" "$c" "$e" "$qinfo"
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
  
  echo "  ---------------------------------------------------------------------------------------------"
  
  print_menu_prompt "Lihat Detail (Masukkan Username) atau [Enter] untuk kembali" target_user

  # Kalau user langsung Enter → cuma pause sebentar lalu balik ke menu utama
  if [[ -z "$target_user" ]]; then
    pause_for_enter
    return 0
  fi

  # Cari file detail akun berdasarkan username di semua protokol
  local detail_file=""
  local proto_found=""

  for p in vmess vless trojan shadowsocks http socks; do
    local fpath="$ACCOUNTS_DIR/$p/$target_user-$p.txt"
    if [[ -f "$fpath" ]]; then
      detail_file="$fpath"
      proto_found="$p"
      break
    fi
  done

  if [[ -n "$detail_file" ]]; then
    clear
    print_header "DETAIL AKUN: $target_user (${proto_found^^})"
    cat "$detail_file"
    echo ""
  else
    print_error "Detail akun untuk user '$target_user' tidak ditemukan."
    echo -e "  Cek lagi username atau pastikan akun sudah dibuat."
  fi

  pause_for_enter
}

render_account_html() {
  local proto="$1"
  local user="$2"
  local domain="$3"
  local path="$4"        # tanpa slash depan, mis: vmess-ws
  local secret="$5"
  local exp="$6"
  local created="$7"
  local link_tls="$8"
  local link_nontls="$9"

# Info kuota + status aktif/nonaktif
  local quota_info="Unlimited"
  local status_label="AKTIF"
  local status_class="status-on"

  if [[ -s "$QUOTA_DB" ]]; then
    local line
    line=$(grep "^$user|" "$QUOTA_DB" 2>/dev/null | head -n1 || true)
    if [[ -n "$line" ]]; then
      local q used
      q=$(echo "$line" | cut -d'|' -f2)
      used=$(echo "$line" | cut -d'|' -f3)
      [[ -z "$used" ]] && used=0

      if (( q > 0 )); then
        # Kuota terbatas: tampilkan "terpakai / total"
        quota_info="$(bytes_to_human "$used") / $(bytes_to_human "$q")"
        if (( used >= q )); then
          status_label="NONAKTIF"
          status_class="status-off"
        else
          status_label="AKTIF"
          status_class="status-on"
        fi
      else
        # q == 0 → unlimited
        quota_info="Unlimited"
        status_label="AKTIF"
        status_class="status-on"
      fi
    fi
  fi

  local extra_note=""
    case "$proto" in
      shadowsocks)
        extra_note="<div class=\"footer-note\">Rekomendasi: gunakan aplikasi <strong>Netmod / Netmod Syna</strong> untuk koneksi <strong>Shadowsocks WS 2022</strong>.</div>"
        ;;
      http|socks)
        extra_note="<div class=\"footer-note\">Gunakan aplikasi <strong>Exclave</strong>. Atur network ke <strong>WebSocket</strong> dan isi <strong>Path Websocket</strong> manual: <code>/$path</code>.</div>"
        ;;
    esac

  local out="$WEB_PANEL_ACCOUNTS_DIR/$proto/$user.html"

  cat > "$out" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Account $user – ${proto^^}</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    :root {
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #0f172a;
      color: #e5e7eb;
    }
    body {
      margin: 0;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
    }
    .card {
      max-width: 720px;
      width: 100%;
      background: rgba(15,23,42,0.9);
      border-radius: 16px;
      padding: 24px 24px 20px;
      box-shadow: 0 20px 40px rgba(0,0,0,0.6);
      border: 1px solid rgba(148,163,184,0.4);
      backdrop-filter: blur(16px);
    }
    .proto-pill {
      display:inline-flex;
      align-items:center;
      gap:8px;
      padding:4px 10px;
      border-radius:999px;
      background:rgba(59,130,246,0.1);
      border:1px solid rgba(59,130,246,0.5);
      font-size:12px;
      letter-spacing:0.06em;
      text-transform:uppercase;
      color:#93c5fd;
    }
    .header-row {
      display:flex;
      justify-content:space-between;
      align-items:center;
      gap:10px;
      flex-wrap:wrap;
    }
    .status-pill {
      display:inline-flex;
      align-items:center;
      gap:6px;
      padding:2px 10px;
      border-radius:999px;
      font-size:11px;
      text-transform:uppercase;
      letter-spacing:0.08em;
    }
    .status-on {
      background:rgba(34,197,94,0.15);
      border:1px solid rgba(34,197,94,0.7);
      color:#bbf7d0;
    }
    .status-off {
      background:rgba(248,113,113,0.15);
      border:1px solid rgba(248,113,113,0.7);
      color:#fecaca;
    }
    .footer-note {
      margin-top:10px;
      font-size:11px;
      color:#e5e7eb;
      background:#111827;
      border-radius:10px;
      padding:8px 10px;
      border:1px dashed rgba(148,163,184,0.7);
    }
    .footer-note code {
      font-size:11px;
    }
    h1 {
      margin: 12px 0 4px;
      font-size: 22px;
    }
    .meta {
      font-size: 13px;
      color: #9ca3af;
      display:flex;
      flex-wrap:wrap;
      gap:10px 18px;
    }
    .meta span {
      display:flex;
      align-items:center;
      gap:6px;
    }
    .label {
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: #9ca3af;
      margin-top: 18px;
      margin-bottom: 4px;
    }
    .value-box {
      background:#020617;
      border-radius:10px;
      padding:10px 12px;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
      font-size: 13px;
      display:flex;
      justify-content:space-between;
      align-items:center;
      gap:8px;
      border:1px solid rgba(31,41,55,0.9);
    }
    code {
      word-break: break-all;
    }
    button.copy {
      border:none;
      border-radius:999px;
      padding:6px 10px;
      font-size:11px;
      text-transform:uppercase;
      letter-spacing:0.08em;
      background:#22c55e;
      color:#022c22;
      cursor:pointer;
    }
    button.copy:hover {
      filter:brightness(1.05);
    }
    .links {
      display:flex;
      flex-direction:column;
      gap:10px;
      margin-top:8px;
    }
    a.conn-link {
      display:flex;
      justify-content:space-between;
      align-items:center;
      gap:8px;
      text-decoration:none;
      background:#020617;
      border-radius:10px;
      padding:10px 12px;
      border:1px solid rgba(31,41,55,0.9);
      color:#e5e7eb;
      font-size:13px;
    }
    .conn-link span.small {
      font-size:11px;
      text-transform:uppercase;
      letter-spacing:0.08em;
      color:#9ca3af;
    }
    .badge {
      font-size:11px;
      padding:3px 8px;
      border-radius:999px;
      border:1px solid rgba(148,163,184,0.5);
      color:#e5e7eb;
    }
    .footer {
      margin-top:16px;
      font-size:11px;
      color:#6b7280;
      display:flex;
      justify-content:space-between;
      gap:8px;
      flex-wrap:wrap;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="header-row">
      <div class="proto-pill">
        <span>${proto^^}</span>
        <span style="opacity:.7;">WS</span>
      </div>
      <span class="status-pill $status_class">$status_label</span>
    </div>
    <h1>$user@$domain</h1>
    <div class="meta">
      <span>📅 Created: $created</span>
      <span>⏰ Expired: $exp</span>
      <span>📦 Kuota: $quota_info</span>
      <span>🛣️ Path: /$path</span>
    </div>

    <div class="label">Credential Utama</div>
    <div class="value-box">
      <code>$secret</code>
      <button class="copy" data-copy="$secret">Copy</button>
    </div>

    <div class="label">Link Koneksi</div>
    <div class="links">
      <a class="conn-link" href="$link_tls">
        <div>
          <div><strong>TLS 443</strong></div>
          <div class="small">WebSocket + TLS</div>
        </div>
        <span class="badge">COPY</span>
      </a>
      <a class="conn-link" href="$link_nontls">
        <div>
          <div><strong>Non-TLS 80</strong></div>
          <div class="small">WS HTTP biasa</div>
        </div>
        <span class="badge">COPY</span>
      </a>
    </div>
$extra_note
    <div class="footer">
      <span>Generated by Xray Menu</span>
      <span>Share link ini ke user ⮕</span>
    </div>
  </div>

<script>
document.querySelectorAll('button.copy').forEach(btn => {
  btn.addEventListener('click', () => {
    const text = btn.getAttribute('data-copy');
    navigator.clipboard.writeText(text).then(() => {
      const old = btn.textContent;
      btn.textContent = 'Copied';
      setTimeout(() => btn.textContent = old, 1200);
    });
  });
});

// Copy link TLS / Non-TLS ke clipboard saat kartu di-klik
document.querySelectorAll('.conn-link').forEach(a => {
  a.addEventListener('click', (e) => {
    e.preventDefault(); // jangan buka link di browser
    const text = a.getAttribute('data-copy') || a.getAttribute('href');
    if (!text) return;
    navigator.clipboard.writeText(text).then(() => {
      const badge = a.querySelector('.badge');
      if (badge) {
        const old = badge.textContent;
        badge.textContent = 'Copied';
        setTimeout(() => badge.textContent = old, 1200);
      }
    });
  });
});
</script>
</body>
</html>
EOF
}

# Sinkronkan info kuota di web panel dengan quota.db
sync_quota_to_webpanel(){
  # Kalau tidak ada data kuota, tidak perlu apa-apa
  if [[ ! -s "$QUOTA_DB" ]]; then
    return 0
  fi

  # Map user -> proto dari ledger (.db)
  local all_map
  all_map=$(get_all_created_users_map)

  # Loop semua user yang punya kuota
  while IFS='|' read -r u q used last_up last_down; do
    [[ -z "$u" ]] && continue

    # Cari protokol user ini
    local proto
    proto=$(echo "$all_map" | awk -F'|' -v uu="$u" '$1==uu {print $2; exit}')
    [[ -z "$proto" ]] && continue

    # Regenerate halaman HTML user ini (quota_info akan ikut nilai terbaru dari quota.db)
    refresh_account_html "$proto" "$u"
  done < "$QUOTA_DB"
}

rebuild_web_index() {
  local out="$WEB_PANEL_DIR/index.html"

  cat > "$out" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Xray Accounts Panel</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    :root { font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background:#020617; color:#e5e7eb; }
    body { margin:0; padding:24px; min-height:100vh; }
    h1 { margin:0 0 4px; font-size:24px; }
    .sub { color:#9ca3af; font-size:13px; margin-bottom:16px; }
    .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:14px; margin-top:16px; }
    .card {
      border-radius:14px;
      padding:12px 12px 10px;
      background:rgba(15,23,42,0.96);
      border:1px solid rgba(51,65,85,0.9);
      text-decoration:none;
      color:inherit;
      display:block;
    }
    .tag { font-size:11px; text-transform:uppercase; letter-spacing:.08em; color:#93c5fd; }
    .user { font-weight:600; margin:4px 0 2px; font-size:15px; }
    .domain { font-size:12px; color:#9ca3af; }
    .meta { font-size:11px; color:#9ca3af; display:flex; justify-content:space-between; margin-top:6px; }
    .search-box { margin-top:8px; }
    input[type="search"] {
      width:100%; max-width:320px; padding:6px 10px; border-radius:999px;
      border:1px solid rgba(75,85,99,0.9); background:#020617; color:#e5e7eb;
    }
  </style>
</head>
<body>
  <h1>Xray Accounts</h1>
  <div class="sub">Klik salah satu kartu untuk melihat detail akun.</div>
  <div class="search-box">
    <input id="search" type="search" placeholder="Cari username atau proto...">
  </div>
  <div class="grid" id="grid">
EOF

  # Loop semua DB & isi kartu
  local domain
  domain="$(get_domain)"

  # ⬅️ tambahkan deklarasi lokal di sini
  local proto u s e c q

  for proto in vmess vless trojan shadowsocks http socks; do
    local db="$ACCOUNTS_DIR/$proto.db"
    [[ ! -f "$db" ]] && continue

    while IFS='|' read -r u s e c q; do
      [[ -z "$u" ]] && continue
      [[ -z "$c" ]] && c="-"
      cat >> "$out" <<EOF
    <a class="card" href="accounts/${proto}/${u}.html" data-user="${u}" data-proto="${proto}" data-exp="${e}">
      <div class="tag">${proto^^}</div>
      <div class="user">${u}</div>
      <div class="domain">${u}@${domain}</div>
      <div class="meta">
        <span>Exp: ${e}</span>
        <span>Created: ${c}</span>
      </div>
    </a>
EOF
    done < "$db"
  done

  cat >> "$out" <<'EOF'
  </div>

<script>
const input = document.getElementById('search');
const cards = Array.from(document.querySelectorAll('.card'));
input.addEventListener('input', () => {
  const q = input.value.toLowerCase();
  cards.forEach(card => {
    const text = (card.dataset.user + ' ' + card.dataset.proto).toLowerCase();
    card.style.display = text.includes(q) ? '' : 'none';
  });
});
</script>
</body>
</html>
EOF
}

# MENU: Sistem Kuota
aksi_kuota(){
  while true; do
    clear
    print_header "SISTEM KUOTA AKUN XRAY"

    print_menu_option "1)" "Set / Ubah kuota akun"
    print_menu_option "2)" "Reset kuota akun"
    print_menu_option "3)" "Lihat status kuota semua akun"
    print_menu_option "4)" "Cek & nonaktifkan akun yang habis kuota (nonaktif)"
    print_menu_option "5)" "Buka nonaktifkan akun kuota (nonaktif)"
    echo ""
    print_menu_option "0)" "Kembali ke Menu Utama"

    print_menu_prompt "Pilih Opsi (0-5)" q_opt

    case "$q_opt" in
      1) quota_set_user ;;
      2) quota_delete_user ;;
      3) quota_list_status ;;
      4) quota_enforce_now ;;
      5) quota_unblock_user ;;
      0) return 0 ;;
      *) print_error "Pilihan tidak valid."; sleep 1 ;;
    esac
  done
}

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
            print_info "Menghapus record lama..."
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
  
  restart_xray
  
  # TRIGGER FUNGSI UPDATE
  if [[ -n "$old_domain" && "$old_domain" != "$newdom" ]]; then
      update_all_accounts_domain "$newdom"
      update_cname_records "$old_domain" "$newdom"
  fi

  print_info "Domain berhasil diganti ke: $newdom ($mode)"
  pause_for_enter
}

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

rute_blokir_akun() {
  clear
  print_header "Nonaktif Akun (User/Email)"
  
  # Ambil SEMUA user dari aturan 'blocked' yang punya array .user
  local rule_users_all_json
  rule_users_all_json=$(jq -r '
    [
      .routing.rules[]
      | select(.outboundTag == "blocked"
               and (.user|type=="array"))
      | .user
    ] | add // []' "$CONFIG")

  # List user yang benar-benar diblokir (tanpa user system)
  local blocked_users
  blocked_users=$(echo "$rule_users_all_json" | jq -r '.[]' 2>/dev/null | grep -Ev '^(user2|quota)$' || true)

  # Panggil map user|proto dari ledger
  local all_users_map
  all_users_map=$(get_all_created_users_map)

  # Siapkan list untuk user yang BELUM diblokir
  local users_tersedia_proto=""
  local users_tersedia_user=""

  # Siapkan list untuk user yang SUDAH diblokir
  local blocked_proto_list=""
  local blocked_user_list=""

  # Build daftar user yang belum diblokir
  while IFS='|' read -r user proto; do
      [[ -z "$user" ]] && continue
      # cek apakah user ada di blocked_users
      if ! echo "$blocked_users" | grep -qx "$user"; then
          users_tersedia_proto+="$proto\n"
          users_tersedia_user+="$user\n"
      fi
  done < <(echo "$all_users_map")

  # Build daftar user yang sudah diblokir (hanya user yang ada di ledger)
  while read -r bu; do
      [[ -z "$bu" ]] && continue
      local proto
      proto=$(echo "$all_users_map" | awk -F'|' -v uu="$bu" '$1==uu {print $2; exit}')
      [[ -z "$proto" ]] && proto="-"
      blocked_proto_list+="$proto\n"
      blocked_user_list+="$bu\n"
  done <<< "$blocked_users"

  # Gabungkan proto:user untuk kolom kanan
  local blocked_combined=""
  paste -d':' <(echo -e "$blocked_proto_list") <(echo -e "$blocked_user_list") 2>/dev/null \
    | while read -r line; do
        [[ -n "$line" ]] && blocked_combined+="$line\n"
      done
  # Perlu echo supaya var terbawa ke luar subshell
  blocked_combined=$(echo -e "$blocked_combined")

  # Tampilkan tabel 3 kolom
  print_three_columns "Protokol" "$(echo -e "$users_tersedia_proto")" \
                      "User belum dinonaktifkan" "$(echo -e "$users_tersedia_user")" \
                      "User sudah dinonaktifkan (proto:user)" "$blocked_combined"

  # --- Menu Aksi ---
  echo ""
  print_menu_option "1)" "Tambah User ke Daftar Nonaktif"
  print_menu_option "2)" "Hapus User dari Daftar Nonaktif"
  echo ""
  print_menu_option "0)" "Kembali"
  
  print_menu_prompt "Pilih Opsi (0-2)" sub_opt
  
  local tmp="$CONFIG.tmp.$$"

  case "$sub_opt" in
    1) # Tambah
      print_menu_prompt "Masukkan User/Email yang akan dinonaktifkan (0 untuk batal)" user_baru
      if [[ "$user_baru" == "0" ]]; then return 0; fi
      if [[ -z "$user_baru" ]]; then
        print_error "Input tidak boleh kosong."
        pause_for_enter; return 1
      fi

      if echo "$rule_users_all_json" | jq -e --arg u "$user_baru" '.[] | select(. == $u)' > /dev/null 2>&1; then
        print_warn "User '$user_baru' sudah ada dalam daftar nonaktif."
        pause_for_enter
        return 1
      fi

      # Tambah user ke semua rule blocked yang punya array .user
      if jq --arg user_baru "$user_baru" '
        (.routing.rules[]
          | select(.outboundTag == "blocked"
                   and (.user|type=="array"))
          | .user) |= (. + [$user_baru] | unique)
      ' "$CONFIG" > "$tmp"; then
        mv "$tmp" "$CONFIG"
        print_info "User '$user_baru' berhasil ditambahkan ke daftar nonaktif."
        restart_xray
      else
        print_error "Gagal memperbarui konfigurasi."
        rm -f "$tmp"
      fi
      ;;

    2) # Hapus
      print_menu_prompt "Masukkan User/Email yang akan di aktifkan (0 untuk batal)" user_hapus
      if [[ "$user_hapus" == "0" ]]; then return 0; fi
      if [[ -z "$user_hapus" ]]; then
        print_error "Input tidak boleh kosong."
        pause_for_enter; return 1
      fi

      # Lindungi user system
      if [[ "$user_hapus" == "user2" || "$user_hapus" == "quota" ]]; then
          print_error "User system '$user_hapus' tidak dapat dihapus dari daftar nonaktif."
          pause_for_enter
          return 1
      fi

      if ! echo "$rule_users_all_json" | jq -e --arg u "$user_hapus" '.[] | select(. == $u)' > /dev/null 2>&1; then
        print_warn "User '$user_hapus' tidak ditemukan dalam daftar nonaktif."
        pause_for_enter
        return 1
      fi

      if jq --arg user_hapus "$user_hapus" '
        (.routing.rules[]
          | select(.outboundTag == "blocked"
                   and (.user|type=="array"))
          | .user) |= (del(.[] | select(. == $user_hapus)))
      ' "$CONFIG" > "$tmp"; then
        mv "$tmp" "$CONFIG"
        print_info "User '$user_hapus' berhasil di aktifkan (dihapus dari daftar nonaktif)."
        restart_xray
      else
        print_error "Gagal memperbarui konfigurasi."
        rm -f "$tmp"
      fi
      ;;

    0) return 0 ;;
    *) print_error "Pilihan tidak valid."; sleep 1 ;;
  esac
  
  pause_for_enter
}

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

rute_tambah_user_warp() {
  clear
  print_header "Tambah/Hapus User dari Rute WARP"
  
  # Ambil SEMUA user dari aturan WARP yang punya array .user
  local rule_users_all_json
  rule_users_all_json=$(jq -r '
    [
      .routing.rules[]
      | select(.outboundTag == "warp"
               and (.user|type=="array"))
      | .user
    ] | add // []' "$CONFIG")

  # Filter user default "user1" HANYA untuk tampilan
  local warp_users
  warp_users=$(echo "$rule_users_all_json" | jq -r '[.[] | select(. != "user1")] | .[]' 2>/dev/null || true)
  
  # Panggil map user|proto
  local all_users_map
  all_users_map=$(get_all_created_users_map)
  
  # Siapkan list untuk user yang BELUM ke WARP
  local users_tersedia_proto=""
  local users_tersedia_user=""
  
  # Siapkan list untuk user yang SUDAH ke WARP (dengan proto)
  local warp_proto_list=""
  local warp_user_list=""

  # Build daftar user belum ke WARP
  while IFS='|' read -r user proto; do
      [[ -z "$user" ]] && continue
      if ! echo "$warp_users" | grep -qx "$user"; then
          users_tersedia_proto+="$proto\n"
          users_tersedia_user+="$user\n"
      fi
  done < <(echo "$all_users_map")

  # Build daftar user sudah ke WARP (hanya yang ada di ledger)
  while read -r wu; do
      [[ -z "$wu" ]] && continue
      local proto
      proto=$(echo "$all_users_map" | awk -F'|' -v uu="$wu" '$1==uu {print $2; exit}')
      [[ -z "$proto" ]] && proto="-"
      warp_proto_list+="$proto\n"
      warp_user_list+="$wu\n"
  done <<< "$warp_users"

  # Gabungkan proto:user untuk kolom kanan
  local warp_combined=""
  paste -d':' <(echo -e "$warp_proto_list") <(echo -e "$warp_user_list") 2>/dev/null \
    | while read -r line; do
        [[ -n "$line" ]] && warp_combined+="$line\n"
      done
  warp_combined=$(echo -e "$warp_combined")

  # Tampilkan 3 kolom
  print_three_columns "Protokol" "$(echo -e "$users_tersedia_proto")" \
                      "User belum ke WARP" "$(echo -e "$users_tersedia_user")" \
                      "User sudah ke WARP (proto:user)" "$warp_combined"

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
      print_menu_prompt "Masukkan User/Email yang akan diarahkan ke WARP (0 untuk batal)" user_baru
      if [[ "$user_baru" == "0" ]]; then return 0; fi
      if [[ -z "$user_baru" ]]; then
        print_error "Input tidak boleh kosong."
        pause_for_enter; return 1
      fi

      if echo "$rule_users_all_json" | jq -e --arg u "$user_baru" '.[] | select(. == $u)' > /dev/null 2>&1; then
        print_warn "User '$user_baru' sudah ada di rute WARP."
        pause_for_enter
        return 1
      fi

      if jq --arg user_baru "$user_baru" '
        (.routing.rules[]
          | select(.outboundTag == "warp"
                   and (.user|type=="array"))
          | .user) |= (. + [$user_baru] | unique)
      ' "$CONFIG" > "$tmp"; then
        mv "$tmp" "$CONFIG"
        print_info "User '$user_baru' berhasil ditambahkan ke rute WARP."
        restart_xray
      else
        print_error "Gagal memperbarui konfigurasi."
        rm -f "$tmp"
      fi
      ;;

    2) # Hapus
      print_menu_prompt "Masukkan User/Email yang akan DIHAPUS dari rute WARP (0 untuk batal)" user_hapus
      if [[ "$user_hapus" == "0" ]]; then return 0; fi
      if [[ -z "$user_hapus" ]]; then
        print_error "Input tidak boleh kosong."
        pause_for_enter; return 1
      fi

      # Lindungi user default
      if [[ "$user_hapus" == "user1" ]]; then
        print_error "User default 'user1' tidak dapat dihapus dari rute WARP."
        pause_for_enter
        return 1
      fi

      if ! echo "$rule_users_all_json" | jq -e --arg u "$user_hapus" '.[] | select(. == $u)' > /dev/null 2>&1; then
        print_warn "User '$user_hapus' tidak ditemukan dalam rute WARP."
        pause_for_enter
        return 1
      fi

      if jq --arg user_hapus "$user_hapus" '
        (.routing.rules[]
          | select(.outboundTag == "warp"
                   and (.user|type=="array"))
          | .user) |= (del(.[] | select(. == $user_hapus)))
      ' "$CONFIG" > "$tmp"; then
        mv "$tmp" "$CONFIG"
        print_info "User '$user_hapus' berhasil DIHAPUS dari rute WARP."
        restart_xray
      else
        print_error "Gagal memperbarui konfigurasi."
        rm -f "$tmp"
      fi
      ;;

    0) return 0 ;;
    *) print_error "Pilihan tidak valid."; sleep 1 ;;
  esac

  pause_for_enter
}

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

# Poin 2: Sub-menu untuk "Rute Manajemen"
aksi_rute_manajemen() {
  while true; do
    clear
    print_header "RUTE MANAJEMEN (WARP)"
    print_menu_option "1)" "Nonaktif Akun (User/Email)"
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
    print_menu_option "9)" "Sistem Kuota Akun"
    echo ""
    print_menu_option "0)" "Keluar"
    
    print_menu_prompt "Pilih Opsi (0-9)" m
    
    case "$m" in
      1) aksi_buat ;;
      2) aksi_hapus ;;
      3) aksi_perpanjang ;;
      4) aksi_daftar_akun ;;
      5) aksi_rute_manajemen ;; # Poin 1: Menu baru ditambahkan
      6) aksi_ganti_domain ;;
      7) aksi_tambah_host ;;
      8) aksi_about ;;
      9) aksi_kuota ;;
      0) exit 0 ;;
      *) print_error "Pilihan tidak valid."; sleep 1 ;;
    esac
  done
}

# ====== Bootstrap ======
need_root
need_cmd jq awk sed grep systemctl nginx date base64 curl openssl paste comm mktemp uptime free numfmt
ensure_dirs

# Mode non-interaktif untuk cron: cek & blokir kuota
if [[ "${1:-}" == "--cek-kuota" ]]; then
  quota_enforce_now
  exit 0
fi

main_menu

