#!/bin/bash

# ==================================================================================
# Skrip Instalasi Otomatis untuk Bot WhatsApp (botwa) & WAHA (WhatsApp API Host)
#
# Deskripsi:
# Skrip ini mengotomatiskan seluruh proses penyiapan server untuk menjalankan
# bot WhatsApp menggunakan repositori 'botwa' dan WAHA (WhatsApp API Host)
# dalam sebuah kontainer Docker.
#
# Repositori Bot: https://github.com/srpcom/botwa
# ==================================================================================

# Hentikan skrip jika terjadi error
set -e

# --- Variabel Konfigurasi ---
GIT_REPO_URL="https://github.com/srpcom/botwa.git"
REPO_DIR="botwa"
PM2_APP_NAME="botwa"
DOCKER_CONTAINER_NAME="waha-plus"

# --- Variabel Warna untuk Output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Fungsi Pembantu ---
print_step() {
    echo -e "\n${BLUE}=====================================================${NC}"
    echo -e "${YELLOW}LANGKAH $1: $2${NC}"
    echo -e "${BLUE}=====================================================${NC}"
}

# --- Fungsi-fungsi Utama ---

check_distro() {
    if ! command -v lsb_release &> /dev/null; then
        echo -e "${YELLOW}Peringatan: Perintah 'lsb_release' tidak ditemukan. Tidak dapat memverifikasi distribusi Linux.${NC}"
        echo "Skrip ini dioptimalkan untuk Ubuntu/Debian."
        read -p "Lanjutkan instalasi? (y/n): " choice
        if [[ "$choice" != "y" ]]; then
            echo "Instalasi dibatalkan."
            exit 1
        fi
    elif [[ "$(lsb_release -is)" != "Ubuntu" && "$(lsb_release -is)" != "Debian" ]]; then
        echo -e "${YELLOW}Peringatan: Distribusi Anda ($(lsb_release -is)) bukan Ubuntu atau Debian.${NC}"
        echo "Skrip mungkin tidak berjalan dengan sempurna."
        read -p "Lanjutkan instalasi? (y/n): " choice
        if [[ "$choice" != "y" ]]; then
            echo "Instalasi dibatalkan."
            exit 1
        fi
    fi
}

update_system() {
    print_step 1 "Memperbarui daftar paket sistem"
    sudo apt-get update
    sudo apt-get upgrade -y
}

install_dependencies() {
    print_step 2 "Menginstall dependensi dasar (git, curl, wget)"
    sudo apt-get install -y git curl wget
}

install_docker() {
    print_step 3 "Menginstall Docker dan Docker Compose"
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}Docker sudah terinstall. Melewati langkah ini.${NC}"
    else
        echo "Mengunduh dan menjalankan skrip instalasi resmi Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        rm get-docker.sh
    fi
    
    echo "Mengonfigurasi Docker agar berjalan tanpa 'sudo'..."
    sudo usermod -aG docker ${USER}
    echo -e "${GREEN}Konfigurasi Docker selesai. Anda perlu logout dan login kembali agar perubahan ini sepenuhnya aktif.${NC}"
}

install_node_nvm() {
    print_step 4 "Menginstall Node.js v20 melalui NVM (Node Version Manager)"
    # Install NVM
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    
    # Source NVM untuk sesi saat ini
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    # Install dan gunakan Node.js v20
    nvm install 20
    nvm use 20
    nvm alias default 20
    echo -e "${GREEN}Node.js v$(node -v) dan npm v$(npm -v) berhasil diinstall.${NC}"
}

install_pm2() {
    print_step 5 "Menginstall PM2 (Process Manager) secara global"
    npm install pm2 -g
    echo -e "${GREEN}PM2 berhasil diinstall.${NC}"
}

setup_bot() {
    print_step 6 "Mengunduh dan menyiapkan kode bot dari GitHub"
    # Hapus direktori lama jika ada untuk instalasi baru
    if [ -d "$HOME/$REPO_DIR" ]; then
        echo -e "${YELLOW}Direktori '$REPO_DIR' sudah ada. Menghapusnya...${NC}"
        rm -rf "$HOME/$REPO_DIR"
    fi
    
    git clone $GIT_REPO_URL "$HOME/$REPO_DIR"
    cd "$HOME/$REPO_DIR"
    
    echo "Menginstall dependensi Node.js untuk bot (express, axios)..."
    # PERBAIKAN: Langsung install paket yang dibutuhkan karena tidak ada package.json
    npm install express axios
    echo -e "${GREEN}Setup bot selesai.${NC}"
}

setup_waha() {
    print_step 7 "Membuat file docker-compose.yml dan menjalankan WAHA"
    cd "$HOME/$REPO_DIR"
    
    # Buat file docker-compose.yml
    cat <<EOF > docker-compose.yml
version: '3.8'
services:
  waha:
    image: devlikeapro/waha-plus:latest
    container_name: ${DOCKER_CONTAINER_NAME}
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - ./waha-sessions:/usr/src/app/sessions
    environment:
      # Konfigurasi dasar, lihat dokumentasi WAHA untuk opsi lainnya
      - WHA_LOG_LEVEL=info
EOF

    echo "Menjalankan kontainer WAHA dengan Docker Compose..."
    # Gunakan sudo karena grup docker mungkin belum aktif untuk user saat ini
    sudo docker compose up -d
    echo -e "${GREEN}Kontainer WAHA berhasil dijalankan.${NC}"
}

start_services() {
    print_step 8 "Menjalankan bot dengan PM2 dan mengaturnya untuk startup"
    cd "$HOME/$REPO_DIR"
    
    # Jalankan bot dengan PM2. File utamanya adalah index.js
    pm2 start index.js --name "$PM2_APP_NAME"
    
    # Konfigurasi PM2 untuk berjalan saat boot
    echo "Mengonfigurasi PM2 startup script..."
    # Dapatkan path nvm dan node untuk digunakan oleh user root
    NVM_NODE_PATH=$(which node)
    PM2_PATH=$(which pm2)
    
    # Jalankan perintah startup yang dihasilkan oleh pm2
    STARTUP_CMD=$(pm2 startup | tail -n 1)
    if [[ -n "$STARTUP_CMD" ]]; then
        echo "Menjalankan perintah berikut dengan sudo:"
        echo "$STARTUP_CMD"
        # Menjalankan perintah startup dengan path yang benar
        sudo env PATH=$PATH:$NVM_DIR/versions/node/$(nvm version)/bin $STARTUP_CMD
    else
        echo -e "${YELLOW}Tidak dapat mengonfigurasi PM2 startup secara otomatis.${NC}"
    fi

    pm2 save
    echo -e "${GREEN}Bot telah dijalankan dengan PM2.${NC}"
}

show_summary() {
    # Dapatkan IP Publik server
    PUBLIC_IP=$(curl -s ifconfig.me)

    echo -e "\n${GREEN}=====================================================${NC}"
    echo -e "${GREEN}         🎉 INSTALASI SELESAI! 🎉                  ${NC}"
    echo -e "${GREEN}=====================================================${NC}"
    echo -e "\n${YELLOW}Langkah Selanjutnya:${NC}"
    echo -e "1. Buka browser dan akses URL Swagger UI WAHA:"
    echo -e "   ${GREEN}http://${PUBLIC_IP}:3000${NC}"
    echo -e "2. Gunakan endpoint untuk membuat sesi baru dan pindai QR code."
    echo -e "3. Setelah terhubung, bot Anda akan aktif dan siap menerima perintah."
    echo -e "\n${YELLOW}Perintah Penting:${NC}"
    echo -e "- Melihat log bot:             ${GREEN}pm2 logs ${PM2_APP_NAME}${NC}"
    echo -e "- Merestart bot:               ${GREEN}pm2 restart ${PM2_APP_NAME}${NC}"
    echo -e "- Melihat status kontainer WAHA: ${GREEN}sudo docker ps${NC}"
    echo -e "- Melihat log kontainer WAHA:    ${GREEN}sudo docker logs ${DOCKER_CONTAINER_NAME}${NC}"
    echo -e "\n${YELLOW}Catatan:${NC} Jika Anda mendapatkan error 'permission denied' saat menjalankan perintah 'docker' tanpa 'sudo', silakan logout dan login kembali ke server Anda."
}


# --- Eksekusi Skrip ---
main() {
    echo -e "${GREEN}=====================================================${NC}"
    echo -e "${YELLOW} Memulai Instalasi Otomatis Bot WhatsApp & WAHA ${NC}"
    echo -e "${GREEN}=====================================================${NC}"
    
    check_distro
    update_system
    install_dependencies
    install_docker
    install_node_nvm
    install_pm2
    setup_bot
    setup_waha
    start_services
    show_summary
}

main

