// bot.js - Kode Bot WhatsApp Placeholder
// Ini adalah kode bot dasar yang dibuat oleh script installer.
// Anda dapat mengedit dan mengembangkannya lebih lanjut sesuai kebutuhan Anda.

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
            // Untuk contoh ini, kita hanya akan membalas
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
