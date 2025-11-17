#!/bin/bash

# ======================================================================
# Skrip Reset Kuota Xray
# Dijalankan oleh: Systemd Timer (quota_reset.timer)
# Tujuan: Mereset statistik uplink/downlink semua pengguna
# ======================================================================

# --- Konfigurasi ---
# Path ini harus sesuai dengan yang diatur oleh skrip installer
XRAY_BIN="/usr/local/bin/xray"
XRAY_API_SERVER="127.0.0.1:10000"
# --------------------

# Dapatkan daftar semua email pengguna
# '>>>' TIDAK perlu di-escape di sini karena ini adalah file bash murni,
# bukan string di dalam 'eval'.
user_emails=$("$XRAY_BIN" api statsquery --server="$XRAY_API_SERVER" -pattern "user>>>" 2>/dev/null | awk -F '>>>' '{print $2}' | sort -u)

# Loop untuk setiap email dan reset statistik uplink & downlink
while read -r user_email; do
    if [ -n "$user_email" ]; then
        #
        # --- PERBAIKAN BUG ASLI ---
        # '>>>' di dalam parameter --name HARUS di-escape (\>\>\>)
        # agar shell tidak menganggapnya sebagai 'here string'
        #
        
        # Reset uplink
        "$XRAY_BIN" api stats --server="$XRAY_API_SERVER" --reset=true --name="user\>\>\>${user_email}\>\>\>traffic\>\>\>uplink" > /dev/null 2>&1
        
        # Reset downlink
        "$XRAY_BIN" api stats --server="$XRAY_API_SERVER" --reset=true --name="user\>\>\>${user_email}\>\>\>traffic\>\>\>downlink" > /dev/null 2>&1
    fi
done <<< "$user_emails"

exit 0

