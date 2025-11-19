#!/bin/bash

# ======================================================================
# Skrip Instalasi Xray-core & Nginx (Auto DNS Cloudflare + Validasi)
# Versi 5.0 (Added: Clean Start / Auto Delete Expired Account)
# ======================================================================

# --- Variabel Warna (Diperluas) ---
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

# --- Konfigurasi Cloudflare ---
CF_TOKEN="qz31v4icXAb7593V_cafEHPEvskw5V8rWES95AZx" 
DOMAIN_OPT_1="vip01.qzz.io"
DOMAIN_OPT_2="vip02.qzz.io"
DOMAIN_OPT_3="vip03.qzz.io"
DOMAIN_OPT_4="vip04.qzz.io"

# --- KONFIGURASI SUMBER MENU (GITHUB) ---
# PENTING: Ganti URL ini dengan URL RAW file xray_menu.sh dari repo Github Anda
MENU_URL="https://raw.githubusercontent.com/superdecrypt-dev/hitam/main/menu.sh"

# --- Log File ---
LOG_FILE="/tmp/xray_install.log"
rm -f $LOG_FILE

# --- Variabel Global untuk Versi ---
XRAY_VERSION_INSTALLED="?"
WGCF_VERSION_INSTALLED="?"
WP_VERSION_INSTALLED="?"

# --- Fungsi UI / Helper ---
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
    [ $padding -lt 0 ] && padding=0
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
    local title="Skrip Instalasi Xray-core & Nginx"
    local subtitle="Versi 5.0 (Clean Install & Auto Delete)"
    
    print_line "=" "$B_GREEN"
    echo -e "\n"
    print_center "$title" "$B_GREEN"
    print_center "$subtitle" "$GREEN"
    echo -e "\n"
    print_line "=" "$B_GREEN"
    echo -e " Log file akan disimpan di: ${B_YELLOW}${LOG_FILE}${RESET}\n"
    sleep 1
}

print_info() { echo -e "${B_GREEN}[ i ]${RESET} $1"; }
print_warn() { echo -e "${B_YELLOW}[ ! ]${RESET} $1"; }
print_error() { echo -e "${B_RED}[ ✖ ]${RESET} $1"; }

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

run_task() {
    local msg=$1
    shift
    local cmd=$@
    local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0

    tput civis # Sembunyikan kursor
    echo -n -e "${B_BLUE}[ → ]${RESET} $msg... "
    
    eval "$cmd" >> $LOG_FILE 2>&1 &
    local pid=$!

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
        echo -e "\b${B_GREEN}✔${RESET} ${GREEN}OK${RESET}"
    else
        echo -e "\b${B_RED}✖${RESET} ${RED}FAIL${RESET}"
        print_error "Gagal: $msg. Cek ${B_YELLOW}$LOG_FILE${RESET} untuk detail."
        exit 1
    fi
}

# --- 1. Cek Root ---
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "Harap jalankan sebagai root."
        exit 1
    fi
}

# --- 2. Validasi OS ---
validate_os() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        if [[ "$ID" == "ubuntu" && $(echo "$VERSION_ID" | cut -d. -f1) -ge 22 ]] || \
           [[ "$ID" == "debian" && $(echo "$VERSION_ID" | cut -d. -f1) -ge 11 ]]; then
            OS=$ID
            print_info "OS terdeteksi: ${B_WHITE}${PRETTY_NAME}${RESET}"
        else
            print_error "Hanya mendukung Ubuntu 22.04+ atau Debian 11+."
            exit 1
        fi
    else
        print_error "Tidak dapat memvalidasi OS."
        exit 1
    fi
}

# --- 2b. Clean Up Previous Install (BARU) ---
cleanup_previous_state() {
    print_info "Memeriksa sisa instalasi sebelumnya..."
    
    if [[ -d "/usr/local/etc/xray" ]]; then
        if [[ "$(ls -A /usr/local/etc/xray)" ]]; then
            print_warn "Ditemukan file lama di /usr/local/etc/xray."
            run_task "Menghapus konfigurasi Xray lama" "rm -rf /usr/local/etc/xray/*"
        else
            print_info "Direktori konfigurasi sudah bersih."
        fi
    else
        print_info "Direktori baru akan dibuat."
    fi
    
    # Pastikan direktori ada dan kosong
    mkdir -p /usr/local/etc/xray
}

# --- 3. Instal Dependensi ---
install_dependencies() {
    run_task "Update repositori paket" "apt update -y"
    run_task "Install paket (curl, jq, cron, dll)" "apt install -y curl wget socat lsof unzip git jq openssl cron"
}

# --- Cloudflare Handler ---
update_cloudflare_dns() {
    local ZONE_NAME="$1"
    local SUBDOMAIN="$2"
    local FULL_DOMAIN="${SUBDOMAIN}.${ZONE_NAME}"

    print_info "Cloudflare DNS: Membersihkan A record lama & membuat A record baru."

    MY_IP=$(curl -s https://api.ipify.org)
    if [[ -z "$MY_IP" ]]; then
        print_error "Gagal mendapatkan IP publik VPS."
        exit 1
    fi
    print_info "IP VPS: ${B_WHITE}$MY_IP${RESET}"

    ZONE_META=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${ZONE_NAME}" \
        -H "Authorization: Bearer ${CF_TOKEN}" \
        -H "Content-Type: application/json")
    ZONE_ID=$(echo "$ZONE_META" | jq -r '.result[0].id')
    if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
        print_error "Tidak bisa mendapatkan Zone ID untuk ${ZONE_NAME}. Periksa token atau nama zona."
        exit 1
    fi

    fetch_all_records() {
        local TYPE="$1"
        local PAGE=1
        local PER_PAGE=100
        local ACCUM="[]"
        while :; do
            RESP=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=${TYPE}&page=${PAGE}&per_page=${PER_PAGE}" \
                -H "Authorization: Bearer ${CF_TOKEN}" \
                -H "Content-Type: application/json")
            CHUNK=$(echo "$RESP" | jq '.result')
            if ! jq -e 'if type == "array" then true else false end' <<< "$CHUNK" > /dev/null 2>&1; then
                print_error "Respon API Cloudflare tidak valid saat fetching records."
                break
            fi
            ACCUM=$(jq -s '.[0] + .[1]' <(echo "$ACCUM") <(echo "$CHUNK"))
            TOTAL_PAGES=$(echo "$RESP" | jq -r '.result_info.total_pages // 1')
            if [[ -z "$TOTAL_PAGES" || "$TOTAL_PAGES" == "null" ]]; then TOTAL_PAGES=1; fi
            if (( PAGE >= TOTAL_PAGES )); then
                break
            fi
            PAGE=$((PAGE+1))
        done
        echo "$ACCUM"
    }

    print_info "Mengambil A records & menyaring yang mengarah ke $MY_IP ..."
    ALL_A=$(fetch_all_records "A")

    IDS_A_TO_DELETE=$(echo "$ALL_A" | jq -r --arg IP "$MY_IP" '.[] | select(.content==$IP) | .id')
    DELETED_A_HOSTS=()
    if [[ -n "$IDS_A_TO_DELETE" ]]; then
        while read -r AID; do
            [[ -z "$AID" ]] && continue
            AOBJ=$(echo "$ALL_A" | jq -r --arg ID "$AID" '.[] | select(.id==$ID)')
            ANAME=$(echo "$AOBJ" | jq -r '.name')
            print_warn "Menghapus A record lama: ${ANAME} -> ${MY_IP}"
            curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${AID}" \
                -H "Authorization: Bearer ${CF_TOKEN}" \
                -H "Content-Type: application/json" >/dev/null
            DELETED_A_HOSTS+=("$ANAME")
        done <<< "$IDS_A_TO_DELETE"
    else
        print_info "Tidak ada A record yang mengarah ke $MY_IP; tidak ada yang dihapus."
    fi

    if (( ${#DELETED_A_HOSTS[@]} > 0 )); then
        print_info "Host A yang berhasil dihapus:"
        for h in "${DELETED_A_HOSTS[@]}"; do
            echo -e "    - ${RED}$h${RESET}"
        done
    fi

    print_info "Membuat A record baru: ${B_CYAN}${FULL_DOMAIN}${RESET} -> ${B_WHITE}${MY_IP}${RESET}"
    CREATE_A=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CF_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"${SUBDOMAIN}\",\"content\":\"${MY_IP}\",\"ttl\":1,\"proxied\":false}")
    
    if [[ "$(echo "$CREATE_A" | jq -r '.success')" != "true" ]]; then
        print_error "Gagal membuat A record baru."
        echo "$CREATE_A" | jq .errors
        exit 1
    fi
    print_info "${B_GREEN}Sukses${RESET} membuat A record."
    DOMAIN=$FULL_DOMAIN
}

# --- Menu Domain ---
get_domain_menu() {
    # Pastikan direktori ada (redundant safe check)
    mkdir -p /usr/local/etc/xray
    
    while true; do
        clear
        print_header "Langkah 2: Konfigurasi Domain"
        echo -e "${B_WHITE}Silakan pilih metode untuk mengatur domain Anda:${RESET}\n"
        print_menu_option "1." "Gunakan Domain Sendiri (Manual)"
        print_menu_option "2." "Gunakan Domain Tersedia (Auto Cloudflare)"
        echo -e "\n"
        print_menu_option "0." "Batal Instalasi"
        
        print_menu_prompt "Pilih Opsi (0-2)" DOMAIN_OPTION

        case $DOMAIN_OPTION in
            0) print_error "Instalasi dibatalkan oleh pengguna."; exit 0 ;;
            1)
                while true; do
                    echo -e "\n  ${B_CYAN}Masukkan domain Anda (contoh: sub.domain.com)${RESET}"
                    echo -e "  ${YELLOW}Ketik 'k' untuk kembali ke menu utama.${RESET}"
                    read -p "  > " DOMAIN_INPUT
                    
                    if [[ "$DOMAIN_INPUT" == [Kk] ]]; then 
                        DOMAIN=""
                        break
                    elif [[ -z "$DOMAIN_INPUT" ]]; then 
                        print_error "Domain tidak boleh kosong."
                    elif ! [[ "$DOMAIN_INPUT" =~ ^[a-zA-Z0-9.-]+$ ]]; then
                        print_error "Format domain SALAH!"; print_warn "Hanya huruf, angka, titik (.), dan strip (-)."
                    else
                        DOMAIN="$DOMAIN_INPUT"
                        CERT_MODE="standalone"
                        print_info "Domain diatur ke: ${B_GREEN}$DOMAIN${RESET} (mode: standalone)"
                        echo "$DOMAIN" > /usr/local/etc/xray/domain
                        break
                    fi
                done
                [[ -n "$DOMAIN" ]] && break
                ;;
            2)
                while true; do
                    clear
                    print_header "Opsi 2: Domain Auto Cloudflare"
                    echo -e "${B_WHITE}Pilih Domain Induk:${RESET}\n"
                    print_menu_option "A." "${DOMAIN_OPT_1}"
                    print_menu_option "B." "${DOMAIN_OPT_2}"
                    print_menu_option "C." "${DOMAIN_OPT_3}"
                    print_menu_option "D." "${DOMAIN_OPT_4}"
                    echo -e "\n"
                    print_menu_option "K." "Kembali ke Menu Utama"
                    
                    print_menu_prompt "Pilih (A/B/C/D/K)" CF_DOMAIN_OPT
        
                    if   [[ "$CF_DOMAIN_OPT" == [Kk] ]]; then break
                    elif [[ "$CF_DOMAIN_OPT" == [Aa] ]]; then SELECTED_ZONE=$DOMAIN_OPT_1
                    elif [[ "$CF_DOMAIN_OPT" == [Bb] ]]; then SELECTED_ZONE=$DOMAIN_OPT_2
                    elif [[ "$CF_DOMAIN_OPT" == [Cc] ]]; then SELECTED_ZONE=$DOMAIN_OPT_3
                    elif [[ "$CF_DOMAIN_OPT" == [Dd] ]]; then SELECTED_ZONE=$DOMAIN_OPT_4
                    else print_error "Pilihan tidak valid."; sleep 1; continue; fi
        
                    print_info "Domain Induk dipilih: ${B_YELLOW}${SELECTED_ZONE}${RESET}"
                    
                    while true; do
                        clear
                        print_header "Opsi 2: Tentukan Nama DNS"
                        echo -e "${B_WHITE}Domain Induk: ${B_YELLOW}${SELECTED_ZONE}${RESET}\n"
                        print_menu_option "1." "Generate nama random (misal: ${CYAN}a7b2cde.${SELECTED_ZONE}${RESET})"
                        print_menu_option "2." "Masukkan nama sendiri (misal: ${CYAN}vpnku.${SELECTED_ZONE}${RESET})"
                        echo -e "\n"
                        print_menu_option "K." "Kembali (pilih domain induk)"
                        
                        print_menu_prompt "Pilih Opsi (1/2/K)" NAME_OPT

                        case "$NAME_OPT" in
                            1)
                                SUB_NAME=$(LC_ALL=C tr -dc 'a-z' < /dev/urandom | head -c 7)
                                if [[ -z "$SUB_NAME" ]]; then
                                    print_error "Gagal generate nama random. Coba lagi."
                                    continue
                                fi
                                print_info "Nama DNS random: ${B_GREEN}${SUB_NAME}.${SELECTED_ZONE}${RESET}"
                                CERT_MODE="wildcard_cf"
                                update_cloudflare_dns "$SELECTED_ZONE" "$SUB_NAME"
                                echo "$DOMAIN" > /usr/local/etc/xray/domain
                                return 0
                                ;;
                            2)
                                while true; do
                                    echo -e "\n  ${B_CYAN}Masukkan nama DNS (contoh: 'vpnku')${RESET}"
                                    echo -e "  ${YELLOW}Ketik 'k' untuk kembali.${RESET}"
                                    read -p "  > " SUB_NAME
                                    
                                    if   [[ "$SUB_NAME" == [Kk] ]]; then break
                                    elif [[ -z "$SUB_NAME" ]]; then print_error "Nama DNS tidak boleh kosong."
                                    elif ! [[ "$SUB_NAME" =~ ^[a-zA-Z0-9.-]+$ ]]; then
                                        print_error "Format nama DNS SALAH!"; print_warn "Hanya huruf, angka, titik (.), dan strip (-)."
                                    else
                                        print_info "Nama DNS valid: ${B_GREEN}${SUB_NAME}.${SELECTED_ZONE}${RESET}"
                                        CERT_MODE="wildcard_cf"
                                        update_cloudflare_dns "$SELECTED_ZONE" "$SUB_NAME"
                                        echo "$DOMAIN" > /usr/local/etc/xray/domain
                                        return 0
                                    fi
                                done
                                ;;
                            [Kk])
                                break
                                ;;
                            *)
                                print_error "Opsi tidak valid."
                                ;;
                        esac
                    done
                done
                ;;
            *)
                print_error "Opsi tidak valid."
                ;;
        esac
    done
}

# --- Port & Path Acak ---
generate_random_paths_and_ports() {
    print_info "Membuat path & port acak..."
    RANDOM_PATH_VMESS_WS=$(LC_ALL=C tr -dc 'a-zA-Z' < /dev/urandom | head -c 8)
    RANDOM_PATH_VLESS_WS=$(LC_ALL=C tr -dc 'a-zA-Z' < /dev/urandom | head -c 8)
    RANDOM_PATH_TROJAN_WS=$(LC_ALL=C tr -dc 'a-zA-Z' < /dev/urandom | head -c 8)
    RANDOM_PATH_HTTP_WS=$(LC_ALL=C tr -dc 'a-zA-Z' < /dev/urandom | head -c 8)
    RANDOM_PATH_SHADOWSOCKS_WS=$(LC_ALL=C tr -dc 'a-zA-Z' < /dev/urandom | head -c 8)
    RANDOM_PATH_SOCKS_WS=$(LC_ALL=C tr -dc 'a-zA-Z' < /dev/urandom | head -c 8)

    local used_ports=()
    gen_port() {
        local p
        while :; do
            p=$(shuf -i 10000-65535 -n 1)
            local clash=0
            for up in "${used_ports[@]}"; do
                if [ "$p" -eq "$up" ]; then
                    clash=1
                    break
                fi
            done
            [ "$clash" -eq 0 ] && { used_ports+=("$p"); echo "$p"; return 0; }
        done
    }

    PORT_VMESS_WS=$(gen_port)
    PORT_VLESS_WS=$(gen_port)
    PORT_TROJAN_WS=$(gen_port)
    PORT_HTTP_WS=$(gen_port)
    PORT_SHADOWSOCKS_WS=$(gen_port)
    PORT_SOCKS_WS=$(gen_port)
    
    print_info "Path & port berhasil dibuat."
}

# --- 4. Setup Nginx Repo ---
add_nginx_repo() {
  if [ "$OS" == "ubuntu" ]; then
    run_task "Install keyring Nginx (Ubuntu)" "sudo apt install curl gnupg2 ca-certificates lsb-release ubuntu-keyring -y"
    run_task "Tambah repositori Nginx (Ubuntu)" "echo \"deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/ubuntu \`lsb_release -cs\` nginx\" | sudo tee /etc/apt/sources.list.d/nginx.list"
    run_task "Ambil signing key Nginx (Ubuntu)" "curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null"
  elif [ "$OS" == "debian" ]; then
    run_task "Install keyring Nginx (Debian)" "sudo apt install curl gnupg2 ca-certificates lsb-release debian-archive-keyring -y"
    run_task "Tambah repositori Nginx (Debian)" "echo \"deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/debian \`lsb_release -cs\` nginx\" | sudo tee /etc/apt/sources.list.d/nginx.list"
    run_task "Ambil signing key Nginx (Debian)" "curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null"
  fi
  run_task "Set Pin-Priority untuk Nginx" "echo -e \"Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n\" | sudo tee /etc/apt/preferences.d/99nginx"
}

install_nginx() {
  print_info "Menyiapkan repositori Nginx..."
  add_nginx_repo
  run_task "Update apt setelah menambah repo Nginx" "sudo apt update"
  run_task "Install paket Nginx" "sudo apt install nginx -y"
  run_task "Enable service Nginx" "sudo systemctl enable nginx"
  run_task "Bersihkan konfigurasi default Nginx" "rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf"

  print_info "Menulis konfigurasi Nginx utama..."
  cat << 'EOF' > /etc/nginx/nginx.conf
user  www-data;
worker_processes 1;
worker_rlimit_nofile 100000;
pid /run/nginx.pid;
events {
    use epoll;
    worker_connections 2048;
    multi_accept on;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    access_log  /var/log/nginx/access.log;
    error_log   /var/log/nginx/error.log warn;
    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout   30;
    keepalive_requests  1000;
    client_max_body_size        0;
    client_body_timeout         15;
    client_header_timeout       15;
    send_timeout                30;
    client_body_buffer_size     32k;
    client_header_buffer_size   2k;
    large_client_header_buffers 2 4k;
    proxy_http_version          1.1;
    proxy_connect_timeout       5s;
    proxy_send_timeout          3600s;
    proxy_read_timeout          3600s;
    proxy_buffering             off;
    proxy_request_buffering     off;
    proxy_buffers               4 8k;
    proxy_busy_buffers_size     16k;
    gzip on;
    gzip_comp_level 5;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_types
        text/plain
        text/css
        application/json
        application/javascript
        application/xml
        text/xml
        text/javascript
        application/x-javascript;
    gzip_vary on;
    include /etc/nginx/conf.d/*.conf;
}
EOF
}

# --- 5. SSL Certificate ---
issue_certificate() {
    local MODE="${CERT_MODE:-standalone}"
    RANDOM_EMAIL=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 12)@gmail.com

    print_info "Mode sertifikat: ${B_WHITE}$MODE${RESET} untuk domain: ${B_GREEN}$DOMAIN${RESET}"

    if [[ ! -x "$HOME/.acme.sh/acme.sh" ]]; then
        run_task "Install acme.sh" "curl https://get.acme.sh | sh -s email=$RANDOM_EMAIL"
    fi
    ACME_SH_BIN="$HOME/.acme.sh/acme.sh"

    print_info "Membersihkan folder sertifikat lama (jika ada)..."
    run_task "Bersihkan folder acme.sh lama" "rm -rf \"$HOME/.acme.sh/*_ecc\""

    run_task "Set CA ke Let's Encrypt" "\"$ACME_SH_BIN\" --set-default-ca --server letsencrypt"

    if [[ "$MODE" == "wildcard_cf" ]]; then
        print_info "Menerbitkan sertifikat wildcard via DNS-01 Cloudflare..."
        run_task "Issue Wildcard (*.${DOMAIN})" "CF_Token='${CF_TOKEN}' \"$ACME_SH_BIN\" --issue --dns dns_cf -d \"$DOMAIN\" -d \"*.$DOMAIN\" --force"
    else
        run_task "Hentikan Nginx sementara (untuk validasi)" "systemctl stop nginx || true"
        print_info "Menerbitkan sertifikat Standalone HTTP-01..."
        run_task "Issue Standalone ($DOMAIN)" "\"$ACME_SH_BIN\" --issue --standalone -d \"$DOMAIN\" --force"
    fi

    run_task "Install sertifikat ke /usr/local/etc/xray" "mkdir -p /usr/local/etc/xray && \"$ACME_SH_BIN\" --install-cert -d \"$DOMAIN\" \
        --fullchain-file /usr/local/etc/xray/fullchain.pem \
        --key-file /usr/local/etc/xray/privkey.pem"

    run_task "Set izin file sertifikat" "chmod 644 /usr/local/etc/xray/privkey.pem && chmod 644 /usr/local/etc/xray/fullchain.pem"
}

# --- 6. Install Xray Core ---
install_xray() {
    print_info "Mencari versi Xray-core terbaru..."
    LATEST_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.tag_name')
    if [[ -z "$LATEST_VERSION" || "$LATEST_VERSION" == "null" ]]; then
        print_error "Gagal mendapatkan versi Xray terbaru dari GitHub."
        exit 1
    fi
    XRAY_VERSION_INSTALLED=$LATEST_VERSION # <-- Simpan versi
    print_info "Versi terbaru: ${B_WHITE}$LATEST_VERSION${RESET}"
    
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="64" ;;
        aarch64) ARCH="arm64-v8a" ;;
        *) print_error "Arsitektur $ARCH tidak didukung"; exit 1 ;;
    esac
    print_info "Arsitektur terdeteksi: ${B_WHITE}$ARCH${RESET}"

    run_task "Download Xray $LATEST_VERSION" "curl -L -o xray.zip https://github.com/XTLS/Xray-core/releases/download/$LATEST_VERSION/Xray-linux-$ARCH.zip"
    run_task "Unzip Xray ke /usr/local/bin" "unzip -o xray.zip -d /usr/local/bin && rm xray.zip"
    run_task "Set izin +x untuk xray" "chmod +x /usr/local/bin/xray"
    run_task "Buat direktori log & asset" "mkdir -p /var/log/xray /usr/local/share/xray"
    
    run_task "Download GeoIP" "curl -L -o /usr/local/share/xray/geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
    run_task "Download GeoSite" "curl -L -o /usr/local/share/xray/geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"

    print_info "Membuat file service systemd untuk Xray..."
    cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target nss-lookup.target
[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
Environment=XRAY_LOCATION_ASSET=/usr/local/share/xray
ExecStart=/usr/local/bin/xray run --config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
EOF
    run_task "Reload daemon systemd" "systemctl daemon-reload"
    run_task "Enable service Xray" "systemctl enable xray"
}

# ==========================================================
# PERUBAHAN: Fungsi install_warp_tools
# Mendeteksi versi WireProxy dari API GitHub SEBELUM download
# ==========================================================
install_warp_tools() {
    print_info "Mendeteksi arsitektur untuk WARP tools..."
    local ARCH_WGCF
    local ARCH_WP
    
    case $(uname -m) in
        x86_64)
            ARCH_WGCF="amd64"
            ARCH_WP="amd64"
            ;;
        aarch64)
            ARCH_WGCF="arm64"
            ARCH_WP="arm64"
            ;;
        *)
            print_error "Arsitektur $(uname -m) tidak didukung untuk wgcf/wireproxy.";
            exit 1
            ;;
    esac
    print_info "Arsitektur terdeteksi: $(uname -m) (wgcf: ${ARCH_WGCF}, wireproxy: ${ARCH_WP})"

    # 1. Install wgcf
    WGCF_LATEST=$(curl -s "https://api.github.com/repos/ViRb3/wgcf/releases/latest" | jq -r .tag_name)
    if [[ -z "$WGCF_LATEST" || "$WGCF_LATEST" == "null" ]]; then
        print_warn "Gagal deteksi rilis wgcf, menggunakan v2.2.9 (fallback)."
        WGCF_LATEST="v2.2.9"
    fi
    WGCF_VERSION_INSTALLED=$WGCF_LATEST # <-- Simpan versi
    print_info "Mengunduh wgcf ${WGCF_LATEST}..."
    run_task "Download wgcf" "curl -L -o /usr/local/bin/wgcf https://github.com/ViRb3/wgcf/releases/download/${WGCF_LATEST}/wgcf_${WGCF_LATEST#v}_linux_${ARCH_WGCF}"
    run_task "Set executable wgcf" "chmod +x /usr/local/bin/wgcf"

    # 2. Install wireproxy
    WP_LATEST=$(curl -s "https://api.github.com/repos/whyvl/wireproxy/releases/latest" | jq -r .tag_name)
    if [[ -z "$WP_LATEST" || "$WP_LATEST" == "null" ]]; then
        print_warn "Gagal deteksi rilis wireproxy, menggunakan v1.0.9 (fallback)."
        WP_LATEST="v1.0.9"
    fi
    WP_VERSION_INSTALLED=$WP_LATEST
    print_info "Mengunduh wireproxy ${WP_LATEST}..."
    
    local WP_FILENAME="wireproxy_linux_${ARCH_WP}.tar.gz"
    local WP_DOWNLOAD_URL="https://github.com/whyvl/wireproxy/releases/download/${WP_LATEST}/${WP_FILENAME}"
    
    cd /tmp
    run_task "Download wireproxy" "curl -L -o ${WP_FILENAME} ${WP_DOWNLOAD_URL}"
    run_task "Ekstrak wireproxy" "tar -xzf ${WP_FILENAME}"
    run_task "Install wireproxy" "mv -f wireproxy /usr/local/bin/wireproxy"
    run_task "Set executable wireproxy" "chmod +x /usr/local/bin/wireproxy"
    run_task "Bersihkan sisa download" "rm -f ${WP_FILENAME}"
    cd - > /dev/null
}

# --- 8. Konfigurasi WireProxy ---
setup_wireproxy_config() {
    print_info "Membuat konfigurasi WireProxy..."
    cd /tmp
    run_task "Register akun wgcf" "/usr/local/bin/wgcf register --accept-tos"
    run_task "Generate profil wgcf" "/usr/local/bin/wgcf generate"
    
    run_task "Salin profil ke wireproxy.conf" "cp wgcf-profile.conf /usr/local/etc/xray/wireproxy.conf"
    run_task "Tambah config SOCKS5" "echo -e \"\n[Socks5]\nBindAddress = 127.0.0.1:8010\n\" >> /usr/local/etc/xray/wireproxy.conf"
    
    run_task "Bersihkan file sementara wgcf" "rm -f wgcf-account.toml wgcf-profile.conf"
    cd - > /dev/null
    print_info "File ${B_WHITE}/usr/local/etc/xray/wireproxy.conf${RESET} berhasil dibuat."
}

# --- 9. Buat Service WireProxy ---
setup_wireproxy_service() {
    print_info "Membuat file service systemd untuk Wireproxy..."
    cat <<EOF > /etc/systemd/system/wireproxy.service
[Unit]
Description=WireProxy SOCKS5 Client (via Cloudflare WARP)
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/usr/local/bin/wireproxy -c /usr/local/etc/xray/wireproxy.conf
Restart=on-failure
RestartSec=5
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
    run_task "Reload daemon systemd (wireproxy)" "systemctl daemon-reload"
    run_task "Enable service wireproxy" "systemctl enable wireproxy"
}


# --- 10. Generate Configs Xray & Nginx ---
generate_configs() {
    print_info "Membuat UUID dan password acak..."
    UUID_VMESS=$(/usr/local/bin/xray uuid)
    UUID_VLESS=$(/usr/local/bin/xray uuid)
    PASS_TROJAN=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 16)
    USER_HTTP=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 8)
    PASS_HTTP=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 16)
    SERVER_PSK=$(openssl rand -base64 16)
    USER_PSK=$(openssl rand -base64 16)
    while [ "$USER_PSK" = "$SERVER_PSK" ]; do
        USER_PSK=$(openssl rand -base64 16)
    done
    USER_SOCKS=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 8)
    PASS_SOCKS=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 16)
    print_info "Credential acak berhasil dibuat."

    # Xray Config
    print_info "Menulis konfigurasi Xray (config.json)..."
    cat << EOF > /usr/local/etc/xray/config.json
{
  "api": {
    "services": [
      "HandlerService",
      "LoggerService",
      "StatsService"
    ],
    "tag": "api"
  },
  "dns": {
    "queryStrategy": "UseIP",
    "servers": [
      "https://1.1.1.1/dns-query"
    ],
    "tag": "dns_inbound"
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10000,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "tag": "api"
    },
    {
      "listen": "127.0.0.1",
      "port": ${PORT_VMESS_WS},
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID_VMESS}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess-ws"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "vmess"
    },
    {
      "listen": "127.0.0.1",
      "port": ${PORT_VLESS_WS},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID_VLESS}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vless-ws"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "vless"
    },
    {
      "listen": "127.0.0.1",
      "port": ${PORT_TROJAN_WS},
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "${PASS_TROJAN}"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/trojan-ws"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "trojan"
    },
    {
      "listen": "127.0.0.1",
      "port": ${PORT_HTTP_WS},
      "protocol": "http",
      "settings": {
        "accounts": [
          {
            "user": "${USER_HTTP}",
            "pass": "${PASS_HTTP}"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/http-ws"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "http"
    },
    {
      "listen": "127.0.0.1",
      "port": ${PORT_SHADOWSOCKS_WS},
      "protocol": "shadowsocks",
      "settings": {
        "method": "2022-blake3-aes-128-gcm",
        "password": "${SERVER_PSK}",
        "clients": [
          {
            "password": "${USER_PSK}"
          }
        ],
        "network": "tcp,udp"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/shadowsocks-ws"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "shadowsocks"
    },
    {
      "listen": "127.0.0.1",
      "port": ${PORT_SOCKS_WS},
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "${USER_SOCKS}",
            "pass": "${PASS_SOCKS}"
          }
        ],
        "udp": true,
        "ip": "127.0.0.1"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/socks-ws"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "socks"
    }
  ],
  "log": {
    "access": "/var/log/xray/access.log",
    "dnsLog": false,
    "error": "/var/log/xray/error.log",
    "loglevel": "info"
  },
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "AsIs",
        "noises": [],
        "redirect": ""
      },
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    },
    {
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": 8010,
            "users": []
          }
        ]
      },
      "tag": "warp"
    }
  ],
  "policy": {
    "levels": {
      "0": {
        "statsUserDownlink": true,
        "statsUserUplink": true
      }
    },
    "system": {
      "statsInboundDownlink": true,
      "statsInboundUplink": true,
      "statsOutboundDownlink": false,
      "statsOutboundUplink": false
    }
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "inboundTag": [
          "api"
        ],
        "outboundTag": "api",
        "type": "field"
      },
      {
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked",
        "type": "field"
      },
      {
        "outboundTag": "blocked",
        "protocol": [
          "bittorrent"
        ],
        "type": "field"
      },
      {
        "network": "UDP",
        "outboundTag": "blocked",
        "port": "443",
        "type": "field"
      },
      {
        "outboundTag": "blocked",
        "type": "field",
        "user": [
          "user2"
        ]
      },
      {
        "outboundTag": "blocked",
        "type": "field",
        "user": [
          "quota"
        ]
      },
      {
        "domain": [
          "geosite:apple",
          "geosite:meta",
          "geosite:google",
          "geosite:openai",
          "geosite:spotify",
          "geosite:netflix",
          "geosite:reddit"
        ],
        "outboundTag": "warp",
        "type": "field"
      },
      {
        "outboundTag": "direct",
        "port": "1-65535",
        "type": "field"
      },
      {
        "outboundTag": "warp",
        "type": "field",
        "user": [
          "user1"
        ]
      },
      {
        "inboundTag": [
          "default"
        ],
        "outboundTag": "warp",
        "type": "field"
      }
    ]
  },
  "stats": {}
}
EOF

    # Nginx Config
    print_info "Menulis konfigurasi Nginx Xray (xray.conf)..."
    cat << EOF > /etc/nginx/conf.d/xray.conf
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

upstream vmess_ws { server 127.0.0.1:${PORT_VMESS_WS}; keepalive 16; }
upstream vless_ws { server 127.0.0.1:${PORT_VLESS_WS}; keepalive 16; }
upstream trojan_ws { server 127.0.0.1:${PORT_TROJAN_WS}; keepalive 16; }
upstream http_ws { server 127.0.0.1:${PORT_HTTP_WS}; keepalive 16; }
upstream shadowsocks_ws { server 127.0.0.1:${PORT_SHADOWSOCKS_WS}; keepalive 16; }
upstream socks_ws { server 127.0.0.1:${PORT_SOCKS_WS}; keepalive 16; }

map \$uri \$xray_upstream {
    /${RANDOM_PATH_VMESS_WS}    vmess_ws;
    /${RANDOM_PATH_VLESS_WS}    vless_ws;
    /${RANDOM_PATH_TROJAN_WS}   trojan_ws;
    /${RANDOM_PATH_HTTP_WS}       http_ws;
    /${RANDOM_PATH_SHADOWSOCKS_WS}   shadowsocks_ws;
    /${RANDOM_PATH_SOCKS_WS}   socks_ws;
    default   vmess_ws;
}

map \$uri \$xray_ws_path {
    /${RANDOM_PATH_VMESS_WS}    /vmess-ws;
    /${RANDOM_PATH_VLESS_WS}    /vless-ws;
    /${RANDOM_PATH_TROJAN_WS}   /trojan-ws;
    /${RANDOM_PATH_HTTP_WS}       /http-ws;
    /${RANDOM_PATH_SHADOWSOCKS_WS}   /shadowsocks-ws;
    /${RANDOM_PATH_SOCKS_WS}   /socks-ws;
    default   /vmess-ws;
}

server {
    listen 80;
    listen [::]:80;
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;

    server_name ${DOMAIN};

    ssl_certificate /usr/local/etc/xray/fullchain.pem;
    ssl_certificate_key /usr/local/etc/xray/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY_1305_SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM_SHA384';
    ssl_prefer_server_ciphers on;

    location ~ ^/(${RANDOM_PATH_VMESS_WS}|${RANDOM_PATH_VLESS_WS}|${RANDOM_PATH_TROJAN_WS}|${RANDOM_PATH_HTTP_WS}|${RANDOM_PATH_SHADOWSOCKS_WS}|${RANDOM_PATH_SOCKS_WS})$ {
        proxy_set_header Host   \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP  \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout  3600s;
        proxy_send_timeout  3600s;
        proxy_buffering         off;
        proxy_request_buffering off;
        proxy_pass http://\$xray_upstream\$xray_ws_path;
    }

    location / {
        return 404;
    }
}
EOF
    print_info "Semua file konfigurasi berhasil ditulis."
}

# --- 11. Start Services ---
start_services() {
    run_task "Restart Nginx" "systemctl restart nginx"
    run_task "Restart/Start Wireproxy" "systemctl restart wireproxy"
    run_task "Restart Xray" "systemctl restart xray"
}

# ==========================================================
# FITUR BARU: Install Menu Script & Sinkronisasi Config
# ==========================================================
install_menu_script() {
    print_header "Langkah 11: Instalasi Skrip Menu"

    # 1. Cek apakah URL sudah diganti
    if [[ "$MENU_URL" == *"username/repo"* ]]; then
        print_warn "Variabel MENU_URL belum diubah di script installer!"
        print_warn "Melewati download menu. Silakan download manual nanti."
        return
    fi

    # 2. Download Script dengan Spinner (Hidden Output)
    # Menggunakan 'curl -sL' agar silent, output error tetap tertangkap log via run_task
    if run_task "Mengunduh skrip menu dari repository" "curl -sL -o /usr/local/bin/menu \"$MENU_URL\""; then
        
        run_task "Mengatur izin eksekusi" "chmod +x /usr/local/bin/menu"
        
        # 3. Sinkronisasi Config
        print_info "Melakukan sinkronisasi konfigurasi ke menu..."
        
        # Sinkronisasi Token Cloudflare
        sed -i "s|CF_TOKEN=\".*\"|CF_TOKEN=\"$CF_TOKEN\"|g" /usr/local/bin/menu
        
        # Sinkronisasi Domain Tersedia
        local new_domains="(\"$DOMAIN_OPT_1\" \"$DOMAIN_OPT_2\" \"$DOMAIN_OPT_3\" \"$DOMAIN_OPT_4\")"
        sed -i "s|AVAILABLE_DOMAINS=(.*)|AVAILABLE_DOMAINS=$new_domains|g" /usr/local/bin/menu
        
        print_info "Menu berhasil disinkronisasi dan siap digunakan."
    else
        print_error "Gagal mengunduh skrip menu. Cek koneksi atau URL (lihat log)."
    fi
}

# ==========================================================
# FITUR BARU: Install Auto-Delete Expired Accounts (xp)
# ==========================================================
install_autoxp() {
    print_header "Langkah 12: Setup Auto-Delete (XP)"
    
    print_info "Membuat script pembersih otomatis (/usr/local/bin/xp)..."

cat << 'EOF' > /usr/local/bin/xp
#!/bin/bash
# Xray Auto Delete Expired Account Script
# Dijalankan oleh Cron setiap malam

CONFIG="/usr/local/etc/xray/config.json"
ACCOUNTS_DIR="/usr/local/etc/xray/accounts"
LOG_FILE="/var/log/xray/xp.log"

# Fungsi Hapus Client Standar (VMess/VLESS/Trojan/SS)
del_client_std() { 
    local proto="$1"
    local user="$2"
    local tmp="$CONFIG.tmp.$$"
    # Hapus berdasarkan email
    if jq --arg p "$proto" --arg user "$user" \
       '(.inbounds[] | select(.protocol==$p) | .settings.clients) |= ( [ .[] | select(.email != $user) ] )' \
       "$CONFIG" > "$tmp"; then
       mv "$tmp" "$CONFIG"
    else
       rm -f "$tmp"
    fi
}

# Fungsi Hapus Client Akun (HTTP/SOCKS)
del_client_acct() { 
    local proto="$1"
    local user="$2"
    local tmp="$CONFIG.tmp.$$"
    # Hapus berdasarkan user
    if jq --arg p "$proto" --arg user "$user" \
       '(.inbounds[] | select(.protocol==$p) | .settings.accounts) |= ( [ .[] | select(.user != $user) ] )' \
       "$CONFIG" > "$tmp"; then
       mv "$tmp" "$CONFIG"
    else
       rm -f "$tmp"
    fi
}

# Log Function
log_xp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# --- MAIN LOGIC ---
RESTART_NEEDED=0
TODAY_TS=$(date +%s)

# Loop semua protokol
for proto in vmess vless trojan shadowsocks http socks; do
    DB_FILE="$ACCOUNTS_DIR/$proto.db"
    
    if [[ -f "$DB_FILE" ]]; then
        # Baca file DB line by line
        # Format: user|secret|expired|created
        while IFS='|' read -r user secret exp created; do
            if [[ -z "$user" ]]; then continue; fi
            
            # Convert Expired Date ke Timestamp
            EXP_TS=$(date -d "$exp" +%s 2>/dev/null)
            
            # Jika tanggal tidak valid, skip (atau anggap expired, tergantung kebijakan)
            if [[ -z "$EXP_TS" ]]; then continue; fi

            # Cek apakah Expired < Hari Ini
            if [[ $EXP_TS -lt $TODAY_TS ]]; then
                log_xp "Menghapus akun EXPIRED: $user ($proto) - Exp: $exp"
                
                # 1. Hapus dari Config JSON
                case "$proto" in
                    vmess|vless|trojan|shadowsocks) del_client_std "$proto" "$user" ;;
                    http|socks) del_client_acct "$proto" "$user" ;;
                esac
                
                # 2. Hapus file detail (.txt)
                rm -f "$ACCOUNTS_DIR/$proto/$user-$proto.txt"
                
                # 3. Tandai user untuk dihapus dari DB (nanti diproses sed)
                # Kita tidak bisa hapus baris saat sedang membaca file yang sama dalam loop
                # Jadi kita simpan user ke array atau file temp, 
                # TAPI cara simpel: grep -v langsung ke file tmp untuk db
                
                # Flag restart
                RESTART_NEEDED=1
            fi
        done < "$DB_FILE"

        # Pembersihan DB Fisik (Menghapus baris expired dari file DB)
        # Logic: Baca ulang, keep hanya yang EXP >= TODAY
        cat "$DB_FILE" | while IFS='|' read -r u s e c; do
            ets=$(date -d "$e" +%s 2>/dev/null)
            if [[ -n "$ets" && $ets -ge $TODAY_TS ]]; then
                echo "$u|$s|$e|$c"
            fi
        done > "$DB_FILE.tmp"
        mv "$DB_FILE.tmp" "$DB_FILE"
    fi
done

# Restart Service jika ada perubahan
if [[ $RESTART_NEEDED -eq 1 ]]; then
    log_xp "Merestart layanan Xray..."
    systemctl restart xray
    log_xp "Pembersihan selesai."
else
    # Optional: log jika tidak ada aktivitas
    # log_xp "Tidak ada akun expired hari ini."
    :
fi
EOF

    run_task "Set permission script XP" "chmod +x /usr/local/bin/xp"
    
    print_info "Menambahkan Cronjob (Jalan setiap jam 00:00)..."
    # Hapus cron lama jika ada, lalu tambah yang baru
    (crontab -l 2>/dev/null | grep -v "/usr/local/bin/xp"; echo "0 0 * * * /usr/local/bin/xp") | crontab -
    
    run_task "Restart service cron" "systemctl restart cron"
    print_info "Auto-delete berhasil dijadwalkan."
}

# --- 12. Ringkasan ---
show_summary() {
    echo -e "\n"
    print_line "=" "$B_GREEN"
    echo -e "\n"
    print_center "INSTALASI SELESAI" "$B_GREEN"
    echo -e "\n"
    print_line "-" "$GREEN"
    
    echo -e "  ${B_WHITE}Domain:${RESET} ${B_GREEN}${DOMAIN}${RESET}\n"
    echo -e "  ${B_WHITE}Protokol Terinstal (Path Publik):${RESET}"
    echo -e "    - ${CYAN}VMess WS:${RESET}       /${RANDOM_PATH_VMESS_WS}"
    echo -e "    - ${CYAN}VLess WS:${RESET}       /${RANDOM_PATH_VLESS_WS}"
    echo -e "    - ${CYAN}Trojan WS:${RESET}      /${RANDOM_PATH_TROJAN_WS}"
    echo -e "    - ${CYAN}HTTP WS:${RESET}        /${RANDOM_PATH_HTTP_WS}"
    echo -e "    - ${CYAN}Shadowsocks WS:${RESET} /${RANDOM_PATH_SHADOWSOCKS_WS}"
    echo -e "    - ${CYAN}SOCKS WS:${RESET}       /${RANDOM_PATH_SOCKS_WS}"
    echo -e "\n"
    print_line "-" "$GREEN"
    echo -e "  ${B_YELLOW}Integrasi WARP (WireProxy) telah diaktifkan.${RESET}"
    echo -e "  ${B_WHITE}Semua koneksi menggunakan port ${B_GREEN}443 (SSL/TLS)${RESET} ${B_WHITE}dan${B_WHITE} ${B_GREEN}80 (HTTP)${RESET}."
    print_line "-" "$GREEN"
    
    echo -e "  ${B_WHITE}Akses Menu:${RESET}"
    if [[ -x /usr/local/bin/menu ]]; then
        echo -e "    - Ketik perintah ${B_GREEN}menu${RESET} untuk mengelola akun & domain."
    else
        echo -e "    - Script menu belum terunduh (cek URL di installer)."
    fi
    
    echo -e "  ${B_WHITE}Auto-Delete (XP):${RESET}"
    echo -e "    - Berjalan otomatis setiap jam ${B_GREEN}00:00${RESET}."
    echo -e "    - Log aktivitas: ${B_YELLOW}/var/log/xray/xp.log${RESET}"
    
    print_line "=" "$B_GREEN"
}


# --- Fungsi Main ---
main() {
    print_banner
    check_root
    validate_os
    
    # --- NEW: Cleanup Step ---
    print_header "Langkah Awal: Pembersihan Sistem"
    cleanup_previous_state
    # -------------------------
    
    print_header "Langkah 1: Instalasi Dependensi Sistem"
    install_dependencies
    
    get_domain_menu
    
    print_header "Langkah 3: Pembuatan Path & Port Acak"
    generate_random_paths_and_ports
    
    print_header "Langkah 4: Instalasi Nginx"
    install_nginx
    
    print_header "Langkah 5: Penerbitan Sertifikat SSL"
    issue_certificate
    
    print_header "Langkah 6: Instalasi Xray-Core"
    install_xray
    
    print_header "Langkah 7: Instalasi WARP Tools (wgcf, wireproxy)"
    install_warp_tools
    
    print_header "Langkah 8: Konfigurasi WireProxy (WARP)"
    setup_wireproxy_config
    setup_wireproxy_service
    
    print_header "Langkah 9: Pembuatan Konfigurasi Xray & Nginx"
    generate_configs
    
    print_header "Langkah 10: Menjalankan Layanan"
    start_services
    
    # LANGKAH MENU
    install_menu_script
    
    # LANGKAH AUTO-DELETE (XP)
    install_autoxp
    
    show_summary

    echo -e "\n${B_GREEN}Semua langkah telah selesai!${RESET}\n"
}

# Jalankan fungsi main
main

