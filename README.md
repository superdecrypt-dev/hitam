# Xray Multi-Protocol Auto Installer & Manager

Script auto-installer untuk membangun server Xray dengan dukungan multi-protokol, integrasi Cloudflare otomatis, dan routing WARP.

## 🌟 Fitur Utama
* **Core:** Xray-core + Nginx (Reverse Proxy).
* **Protokol:** VMess, VLESS, Trojan, Shadowsocks (2022), HTTP, SOCKS.
* **Koneksi:** WebSocket (WS) pada Port 443 (SSL/TLS) dan Port 80 (Non-TLS).
* **Keamanan:** Auto SSL via Acme.sh (LetsEncrypt/ZeroSSL).
* **Routing:** Integrasi **Cloudflare WARP** (via Wireproxy) untuk bypass limitasi/IP.
* **Manajemen:** Menu CLI (`menu`) untuk buat, hapus, perpanjang akun, dll.
* **Domain:** Mendukung Domain Sendiri atau Auto-Subdomain (menggunakan API Cloudflare).

## 📋 Persyaratan Sistem
* **OS:** Ubuntu 22.04+ atau Debian 11+.
* **Akses:** Root (Wajib).
* **Koneksi:** IP Publik Statis.

## 🚀 Cara Install

Jalankan perintah berikut di terminal VPS Anda sebagai **root**:

```bash
apt update && apt install -y wget curl && wget -q https://raw.githubusercontent.com/superdecrypt-dev/hitam/main/setup.sh && chmod +x setup.sh && ./setup.sh
```
**_Catatan: fitur auto expired belum tersedia, jadi hapus akun manual yang sudah expired_**

## 📸 Screenshots

![1](images/menu.png)
![2](images/menu.png)
![3](images/menu.png)
![4](images/menu.png)
![5](images/menu.png)
![6](images/menu.png)
![7](images/menu.png)
