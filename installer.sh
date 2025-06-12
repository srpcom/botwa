#!/bin/bash

# Script Installer Bot WhatsApp untuk Ubuntu 24
# Author: Gemini

# Pastikan hanya root atau user dengan sudo privileges yang bisa menjalankan script ini
if [[ $EUID -ne 0 ]]; then
   echo "Script ini memerlukan hak akses root (sudo)."
   echo "Silakan jalankan dengan: sudo bash installer.sh"
   exit 1
fi

echo "Memulai instalasi bot WhatsApp..."

# --- 1. Update dan Upgrade Sistem ---
echo "Mengupdate dan mengupgrade paket sistem..."
apt update -y
apt upgrade -y

# --- 2. Instal Dependensi untuk Node.js ---
echo "Menginstal dependensi yang diperlukan untuk Node.js..."
apt install -y ca-certificates curl gnupg

# --- 3. Tambahkan NodeSource APT Repository (untuk Node.js 20.x) ---
echo "Menambahkan NodeSource APT repository untuk Node.js 20.x..."
mkdir -p /etc/apt/keyrings
# Unduh kunci GPG dan dearmor untuk NodeSource
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.run | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
# Tambahkan sumber repository Node.js
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list > /dev/null

# Update daftar paket setelah menambahkan repository
echo "Mengupdate daftar paket lagi..."
apt update -y

# --- 4. Instal Node.js dan npm ---
echo "Menginstal Node.js dan npm..."
apt install -y nodejs

# --- 5. Instal Git ---
echo "Menginstal Git..."
apt install -y git

# --- 6. Instal PM2 (Process Manager) ---
echo "Menginstal PM2 secara global..."
npm install -g pm2

# --- 7. Buat Direktori Bot dan Masuk ke dalamnya ---
BOT_DIR="/opt/whatsapp-bot"
echo "Membuat direktori bot di $BOT_DIR..."
mkdir -p $BOT_DIR
cd $BOT_DIR || { echo "Gagal masuk ke direktori bot. Pastikan direktori dapat dibuat."; exit 1; }

# --- 8. Membuat File placeholder untuk Bot (bot.js) ---
echo "Membuat file placeholder untuk bot (bot.js)..."
# Menggunakan 'EOF_BOT_JS' untuk mencegah ekspansi variabel di dalam sini
cat << 'EOF_BOT_JS' > bot.js
// bot.js - Kode Bot WhatsApp Placeholder
// Anda bisa mengembangkan bot ini lebih lanjut sesuai kebutuhan.

const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');
const fs = require('fs'); // Diperlukan untuk manajemen sesi

// Inisialisasi klien WhatsApp
// LocalAuth akan menyimpan sesi secara lokal di direktori .wwebjs_auth
const client = new Client({
    authStrategy: new LocalAuth({
        clientId: 'whatsapp-bot' // ID unik untuk sesi bot ini
    }),
    puppeteer: {
        args: ['--no-sandbox', '--disable-setuid-sandbox'], // Penting untuk VPS tanpa tampilan GUI
    }
});

// Event: Ketika QR Code dibutuhkan untuk autentikasi
client.on('qr', qr => {
    qrcode.generate(qr, { small: true });
    console.log('Pindai QR Code ini dengan aplikasi WhatsApp Anda (Pengaturan > Perangkat Tertaut).');
});

// Event: Ketika bot siap digunakan
client.on('ready', () => {
    console.log('Klien WhatsApp sudah siap dan terhubung!');
});

// Event: Ketika autentikasi berhasil (sesi disimpan)
client.on('authenticated', (session) => {
    console.log('Autentikasi berhasil! Sesi telah disimpan.');
    // whatsapp-web.js's LocalAuth secara otomatis menangani penyimpanan sesi.
});

// Event: Ketika autentikasi gagal
client.on('auth_failure', msg => {
    console.error('Autentikasi gagal!', msg);
    console.error('Silakan hapus folder .wwebjs_auth di direktori bot dan restart bot.');
});

// Event: Ketika bot terputus dari WhatsApp
client.on('disconnected', (reason) => {
    console.log('Klien terputus!', reason);
    // PM2 akan mencoba me-restart bot secara otomatis jika terputus
});

// Event: Ketika pesan baru diterima
client.on('message', async msg => {
    console.log(`Pesan diterima dari ${msg.from}: ${msg.body}`);

    const chat = await msg.getChat();
    const contact = await msg.getContact();
    const isGroup = chat.isGroup;

    // Abaikan pesan dari bot sendiri
    if (msg.fromMe) return;

    // --- Contoh Perintah Dasar ---
    if (msg.body === '!ping') {
        msg.reply('Pong!');
    }

    // --- FITUR GROUP ADMIN (Contoh Implementasi) ---
    // Logika di bawah ini adalah contoh dan perlu diperluas/disempurnakan.
    // Pastikan bot adalah admin di grup yang ingin Anda jaga agar fitur ini berfungsi.

    if (isGroup) {
        const groupAdmins = chat.participants.filter(p => p.isAdmin).map(p => p.id._serialized);
        const isBotAdmin = groupAdmins.includes(client.info.wid._serialized);
        const isSenderAdmin = groupAdmins.includes(contact.id._serialized);

        // Jika bot bukan admin, sebagian besar fitur admin grup tidak akan berfungsi
        if (!isBotAdmin) {
            // console.log(`Bot bukan admin di grup: ${chat.name}. Beberapa fitur mungkin tidak berfungsi.`);
            // msg.reply(`Maaf, saya perlu menjadi admin di grup ini untuk dapat menggunakan fitur penjaga grup.`);
            return; // Keluar jika bot bukan admin
        }

        // Contoh: Anti-link untuk non-admin
        // Regex yang lebih ketat untuk mendeteksi berbagai jenis tautan
        const linkRegex = /(https?:\/\/[^\s]+|\bwww\.[^\s]+\b|\b\S+\.(com|org|net|id|co\.id|go\.id)\b)/gi;
        if (msg.body.match(linkRegex) && !isSenderAdmin) {
            console.log(`[GROUP SECURITY] Link terdeteksi dari non-admin: ${contact.pushname} - ${msg.body}`);
            try {
                await msg.delete(true); // Hapus pesan link
                msg.reply(`@${contact.id.user} Link terdeteksi! Hanya admin yang diizinkan mengirim link di grup ini.`);
            } catch (e) {
                console.error('Gagal menghapus pesan atau membalas (anti-link):', e);
                msg.reply(`Peringatan: Link terdeteksi dari @${contact.id.user}. Bot gagal menghapus pesan (izin?).`);
            }
        }

        // Contoh: Perintah !kick (hanya admin grup yang bisa)
        if (msg.body.startsWith('!kick') && isSenderAdmin) {
            const mentioned = msg.mentionedIds;
            if (mentioned.length > 0) {
                try {
                    await chat.removeParticipants(mentioned);
                    msg.reply(`Berhasil mengeluarkan ${mentioned.length} anggota.`);
                } catch (e) {
                    console.error('Gagal mengeluarkan anggota (kick):', e);
                    msg.reply('Gagal mengeluarkan anggota. Pastikan saya memiliki izin admin yang cukup.');
                }
            } else {
                msg.reply('Sebutkan anggota yang ingin di-kick. Contoh: !kick @user');
            }
        }

        // Contoh: Perintah !setwelcome [pesan] (hanya admin grup yang bisa)
        if (msg.body.startsWith('!setwelcome ') && isSenderAdmin) {
            const welcomeMessage = msg.body.substring('!setwelcome '.length).trim();
            // Di sini Anda bisa menyimpan 'welcomeMessage' ke database atau file konfigurasi
            msg.reply(`Pesan sambutan telah diatur menjadi: "${welcomeMessage}". (Ini contoh, Anda perlu mengimplementasikan penyimpanan).`);
            console.log(`[GROUP SETTINGS] Pesan sambutan diatur oleh ${contact.pushname}: ${welcomeMessage}`);
        }
    }
});

// Event: Ketika anggota baru bergabung ke grup
client.on('group_join', async (notification) => {
    console.log('Anggota baru bergabung:', notification.id.participant);
    const chat = await notification.getChat();
    if (chat.isGroup) {
        const newMemberContact = await client.getContactById(notification.id.participant);
        // Anda dapat mengambil pesan sambutan yang telah diatur (misalnya dari database) di sini
        const defaultWelcomeMessage = "Selamat datang di grup! Pastikan untuk membaca peraturan dan bersikap sopan.";
        chat.sendMessage(`Halo @${newMemberContact.id.user}, ${defaultWelcomeMessage}`, {
            mentions: [newMemberContact] // Tag anggota baru
        });
    }
});

// Mulai inisialisasi bot
client.initialize();
EOF_BOT_JS

# --- 9. Membuat File package.json ---
echo "Membuat file package.json..."
cat << 'EOF_PACKAGE_JSON' > package.json
{
  "name": "whatsapp-bot",
  "version": "1.0.0",
  "description": "Bot WhatsApp Sederhana yang dapat dikembangkan",
  "main": "bot.js",
  "scripts": {
    "start": "node bot.js"
  },
  "keywords": ["whatsapp-bot", "node.js", "whatsapp-web.js", "ubuntu"],
  "author": "Your Name",
  "license": "MIT",
  "dependencies": {
    "whatsapp-web.js": "^1.23.0",
    "qrcode-terminal": "^0.12.0"
  }
}
EOF_PACKAGE_JSON

# --- 10. Instal Dependensi Node.js Bot ---
echo "Menginstal dependensi bot dari package.json..."
npm install --prefix $BOT_DIR

# --- 11. Memulai Bot dengan PM2 ---
echo "Memulai bot dengan PM2..."
pm2 start $BOT_DIR/bot.js --name "whatsapp-bot"
pm2 save # Menyimpan konfigurasi PM2 agar bot otomatis restart saat VPS reboot

echo "Instalasi selesai!"
echo "---------------------------------------------------------"
echo "Silakan lihat file readme.txt untuk petunjuk penggunaan selanjutnya."
echo "Anda bisa mengaksesnya di: /opt/whatsapp-bot/readme.txt setelah Anda menyalinnya ke VPS."
echo "Untuk melihat status bot: pm2 status"
echo "Untuk melihat log bot: pm2 logs whatsapp-bot --lines 50"
echo "Jika QR code tidak muncul atau bot tidak berjalan, pastikan Anda melihat log!"
echo "---------------------------------------------------------"

