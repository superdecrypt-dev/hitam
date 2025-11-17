#!/bin/bash

# ======================================================================
# Xray Quota Monitor & Auto Reset
# Dijalankan oleh: Systemd Timer
# ======================================================================

PATH_ACCOUNTS="/usr/local/etc/xray/accounts"
CONFIG_FILE="/usr/local/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"
XRAY_API_SERVER="127.0.0.1:10000"
LOG_FILE="/var/log/xray/quota_monitor.log"

# Fungsi Logging
log_msg() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"; }

# ============================================================
# 1. FITUR AUTO RESET SETIAP TANGGAL 1
# ============================================================
TODAY=$(date +%d)
LAST_RESET_FILE="/usr/local/etc/xray/last_reset_date"

if [[ "$TODAY" == "01" ]]; then
    # Cek apakah sudah di-reset hari ini agar tidak looping reset
    if [[ ! -f "$LAST_RESET_FILE" ]] || [[ "$(cat $LAST_RESET_FILE)" != "$(date +%Y-%m)" ]]; then
        log_msg "Menditeksi Tanggal 1. Memulai Reset Kuota Bulanan..."
        
        # Reset Statistik API
        user_emails=$("$XRAY_BIN" api statsquery --server="$XRAY_API_SERVER" -pattern "user>>>" 2>/dev/null | awk -F '>>>' '{print $2}' | sort -u)
        while read -r user; do
            if [[ -n "$user" ]]; then
                "$XRAY_BIN" api stats --server="$XRAY_API_SERVER" --reset=true --name="user\>\>\>${user}\>\>\>traffic\>\>\>uplink" > /dev/null 2>&1
                "$XRAY_BIN" api stats --server="$XRAY_API_SERVER" --reset=true --name="user\>\>\>${user}\>\>\>traffic\>\>\>downlink" > /dev/null 2>&1
            fi
        done <<< "$user_emails"

        # Buka Semua Blokir di Config (Hapus rule blocked user)
        # Kita hapus list user di rule 'blocked'
        jq '(.routing.rules[] | select(.outboundTag == "blocked" and .user != null) | .user) = []' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        
        # Restart Xray untuk menerapkan unblock
        systemctl restart xray
        
        # Simpan penanda bahwa bulan ini sudah direset
        echo "$(date +%Y-%m)" > "$LAST_RESET_FILE"
        log_msg "Reset Bulanan Selesai. Semua kuota kembali 0 dan user di-unblock."
        exit 0
    fi
fi

# ============================================================
# 2. FITUR MONITOR KUOTA (AUTO BLOCK)
# ============================================================
NEEDS_RESTART=0

# Loop semua protokol
for proto in vmess vless trojan http socks shadowsocks; do
    db_file="$PATH_ACCOUNTS/$proto.db"
    
    if [[ -f "$db_file" ]]; then
        while IFS='|' read -r user secret exp created quota_gb; do
            # Skip jika user kosong atau quota 0 (unlimited)
            if [[ -z "$user" ]] || [[ -z "$quota_gb" ]] || [[ "$quota_gb" == "0" ]]; then
                continue
            fi

            # Hitung Limit dalam Bytes
            quota_limit=$((quota_gb * 1024 * 1024 * 1024))

            # Ambil Usage dari API
            up=$("$XRAY_BIN" api statsquery --server="$XRAY_API_SERVER" --name="user>>>${user}>>>traffic>>>uplink" 2>/dev/null | jq -r '.stat.value // 0')
            down=$("$XRAY_BIN" api statsquery --server="$XRAY_API_SERVER" --name="user>>>${user}>>>traffic>>>downlink" 2>/dev/null | jq -r '.stat.value // 0')
            total_usage=$((up + down))

            # Cek apakah melebihi kuota
            if [[ "$total_usage" -ge "$quota_limit" ]]; then
                
                # Cek apakah user SUDAH diblokir di config.json (agar tidak restart terus menerus)
                is_blocked=$(jq -r --arg u "$user" '(.routing.rules[] | select(.outboundTag == "blocked" and .user != null) | .user) | index($u)' "$CONFIG_FILE")

                if [[ "$is_blocked" == "null" ]]; then
                    log_msg "User $user ($proto) MELEBIHI KUOTA ($quota_gb GB). Memblokir..."
                    
                    # Tambahkan user ke rule blocked
                    # Pastikan rule blocked user ada, jika tidak buat strukturnya (biasanya sudah ada dari installer)
                    jq --arg u "$user" '(.routing.rules[] | select(.outboundTag == "blocked" and .user != null) | .user) += [$u]' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                    
                    NEEDS_RESTART=1
                fi
            fi

        done < "$db_file"
    fi
done

# Restart Xray hanya jika ada user baru yang diblokir
if [[ "$NEEDS_RESTART" -eq 1 ]]; then
    systemctl restart xray
    log_msg "Xray direstart untuk menerapkan pemblokiran."
fi
