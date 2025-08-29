// server.js

// --- 1. Impor Modul yang Dibutuhkan ---
const express = require('express');
const axios = require('axios');
const fs = require('fs'); // Modul File System untuk membaca/menulis file

// --- 2. Inisialisasi Aplikasi Express ---
const app = express();
app.use(express.json());

// --- 3. Konfigurasi & Inisialisasi Bot ---
const ADMIN_NUMBER = '6281330639240@c.us'; // GANTI dengan nomor admin Anda
const DB_FILE = './knowledge.json'; // File untuk menyimpan data kata kunci

// Ganti URL ini menjadi localhost karena bot dan WAHA berjalan di mesin yang sama
const WAHA_API_URL = 'http://localhost:3000/api/sendText';

// Muat knowledgeBase dari file, atau buat baru jika tidak ada.
let knowledgeBase = [];
try {
    if (fs.existsSync(DB_FILE)) {
        const data = fs.readFileSync(DB_FILE, 'utf8');
        knowledgeBase = JSON.parse(data);
        console.log('Knowledge base berhasil dimuat dari file.');
    } else {
        // Data default jika file knowledge.json tidak ditemukan
        knowledgeBase = [
            { keywords: ['halo', 'hai', 'pagi', 'siang', 'sore', 'malam'], reply: 'Halo {nama}! Ada yang bisa saya bantu?' },
            { keywords: ['harga', 'berapa', 'price', 'biaya'], reply: 'Harga produk kami mulai dari Rp 50.000.' },
            { keywords: ['lokasi', 'alamat', 'tempat', 'dimana'], reply: 'Kantor pusat kami berlokasi di Jl. Merdeka No. 123, Jakarta.' },
            { keywords: ['terima kasih', 'makasih', 'thanks'], reply: 'Sama-sama, {nama}! Senang bisa membantu.' }
        ];
        fs.writeFileSync(DB_FILE, JSON.stringify(knowledgeBase, null, 2));
        console.log('File knowledge base baru telah dibuat dengan data default.');
    }
} catch (error) {
    console.error('Gagal memuat atau membuat knowledge base:', error);
    process.exit(1); // Hentikan aplikasi jika DB gagal dimuat
}

// Fungsi untuk menyimpan perubahan ke file JSON
function saveKnowledgeBase() {
    try {
        fs.writeFileSync(DB_FILE, JSON.stringify(knowledgeBase, null, 2), 'utf8');
        console.log('Knowledge base berhasil disimpan ke file.');
    } catch (error) {
        console.error('Gagal menyimpan knowledge base:', error);
    }
}

// **PERBAIKAN**: Logika pencocokan diubah menjadi 'includes' agar lebih fleksibel
function getBotReply(message, senderName) {
    if (typeof message !== 'string') return null;
    const cleanedMessage = message.trim().toLowerCase();
    
    // Cari item yang salah satu kata kuncinya terkandung dalam pesan
    const foundItem = knowledgeBase.find(item =>
        item.keywords.some(keyword => cleanedMessage.includes(keyword.toLowerCase()))
    );

    if (foundItem) {
        // Ganti placeholder {nama} dengan nama pengirim
        return foundItem.reply.replace(/{nama}/g, senderName);
    }
    return null; // Kembalikan null jika tidak ada yang cocok
}


// Variabel status bot dan untuk mencegah pesan ganda
let isBotActive = true;
const processedMessages = new Set();

// Fungsi untuk mengirim pesan balasan melalui WAHA
async function sendReply(session, chatId, text) {
    try {
        await axios.post(WAHA_API_URL, { session, chatId, text });
        console.log(`Balasan berhasil dikirim ke: ${chatId}`);
    } catch (error) {
        console.error('Gagal mengirim balasan ke WAHA:', error.response ? error.response.data : error.message);
    }
}

// --- 4. Buat Endpoint Webhook ---
app.post('/webhook', async (req, res) => {
    const { body: messageData } = req;
    const { payload, session: sessionName, event } = messageData;
    
    // Validasi dasar payload
    if (event !== 'message' || !payload || !payload.body || payload.fromMe) {
        return res.status(200).send('Event diabaikan (bukan pesan masuk dari orang lain).');
    }
    
    const { id: messageId, from: sender, body: messageText, _data: { notifyName } } = payload;
    const senderName = notifyName || 'Kak';

    // Mencegah pemrosesan pesan duplikat
    if (messageId && processedMessages.has(messageId)) {
        return res.status(200).send('Pesan duplikat diabaikan.');
    }
    if (messageId) {
        processedMessages.add(messageId);
        setTimeout(() => processedMessages.delete(messageId), 60000); // Hapus ID setelah 1 menit
    }
    
    // Langsung kirim respons OK agar tidak timeout
    res.status(200).send('OK');

    const cleanedMessage = messageText.trim().toLowerCase();
    
    // --- LOGIKA PERINTAH ADMIN ---
    if (sender === ADMIN_NUMBER) {
        const commandArgs = (cmd) => messageText.substring(cmd.length).trim();

        if (cleanedMessage === '!menu') {
            let menuText = '📖 *Daftar Kata Kunci & Balasan*\n\n';
            if (knowledgeBase.length === 0) {
                menuText = 'Belum ada kata kunci yang terdaftar.';
            } else {
                knowledgeBase.forEach((item, index) => {
                    menuText += `*${index + 1}. Balasan:*\n_"${item.reply}"_\n`;
                    menuText += `* Kata Kunci:*\n\`${item.keywords.join(', ')}\`\n\n`;
                });
            }
            await sendReply(sessionName, sender, menuText);
            return;
        }

        if (cleanedMessage.startsWith('!tambah_balasan ')) {
            const parts = commandArgs('!tambah_balasan ').split('|');
            if (parts.length !== 2 || !parts[0] || !parts[1]) {
                return sendReply(sessionName, sender, 'Format salah. Gunakan:\n!tambah_balasan <kata kunci>|<balasan baru>');
            }
            const [newKeyword, newReply] = parts.map(p => p.trim());
            knowledgeBase.push({ keywords: [newKeyword.toLowerCase()], reply: newReply });
            saveKnowledgeBase();
            await sendReply(sessionName, sender, `✅ Balasan baru untuk kata kunci "${newKeyword}" berhasil ditambahkan.`);
            return;
        }
        
        if (cleanedMessage.startsWith('!tambah_kata ')) {
            const parts = commandArgs('!tambah_kata ').split('|');
            if (parts.length !== 2 || !parts[0] || !parts[1]) {
                return sendReply(sessionName, sender, 'Format salah. Gunakan:\n!tambah_kata <kata kunci baru>|<balasan yang sudah ada>');
            }
            const [newKeyword, existingReply] = parts.map(p => p.trim());
            const item = knowledgeBase.find(i => i.reply.toLowerCase() === existingReply.toLowerCase());
            if (item) {
                if (!item.keywords.includes(newKeyword.toLowerCase())) {
                    item.keywords.push(newKeyword.toLowerCase());
                    saveKnowledgeBase();
                    await sendReply(sessionName, sender, `✅ Kata kunci "${newKeyword}" berhasil ditambahkan.`);
                } else {
                    await sendReply(sessionName, sender, `⚠️ Kata kunci "${newKeyword}" sudah ada untuk balasan tersebut.`);
                }
            } else {
                await sendReply(sessionName, sender, `❌ Balasan "${existingReply}" tidak ditemukan.`);
            }
            return;
        }
        
        if (cleanedMessage.startsWith('!hapus ')) {
            const keywordToDelete = commandArgs('!hapus ').toLowerCase();
            let foundAndRemoved = false;
            knowledgeBase = knowledgeBase.filter(item => {
                const originalLength = item.keywords.length;
                item.keywords = item.keywords.filter(kw => kw.toLowerCase() !== keywordToDelete);
                if (item.keywords.length < originalLength) {
                    foundAndRemoved = true;
                }
                return item.keywords.length > 0; // Hapus entri jika tidak ada kata kunci tersisa
            });
            if (foundAndRemoved) {
                saveKnowledgeBase();
                await sendReply(sessionName, sender, `🗑️ Kata kunci "${keywordToDelete}" berhasil dihapus.`);
            } else {
                await sendReply(sessionName, sender, `❌ Kata kunci "${keywordToDelete}" tidak ditemukan.`);
            }
            return;
        }

        if (cleanedMessage === '!pause') {
            isBotActive = false;
            console.log('BOT DIPASUSE');
            await sendReply(sessionName, sender, '⏸️ Bot telah dipause.');
            return;
        }

        if (cleanedMessage === '!start') {
            isBotActive = true;
            console.log('BOT DIAKTIFKAN');
            await sendReply(sessionName, sender, '▶️ Bot telah diaktifkan kembali.');
            return;
        }
        
        // **PERINTAH BARU**
        if (cleanedMessage === '!status') {
            const statusText = `📊 *Status Bot Saat Ini* 📊\n\n- Status: ${isBotActive ? '✅ Aktif' : '⏸️ Paused'}\n- Jumlah Data Balasan: ${knowledgeBase.length}`;
            await sendReply(sessionName, sender, statusText);
            return;
        }
    }

    // --- LOGIKA BALASAN OTOMATIS UNTUK PENGGUNA UMUM ---
    if (!isBotActive) {
        console.log('Bot sedang pause, pesan diabaikan.');
        return;
    }
    
    const replyText = getBotReply(messageText, senderName);
    if (replyText) {
        console.log(`Membalas ke ${sender} dengan: "${replyText}"`);
        await sendReply(sessionName, sender, replyText);
    } else {
        console.log(`Tidak ada kata kunci cocok untuk pesan dari ${sender}.`);
    }
});

// --- 5. Jalankan Server ---
const PORT = 5000;
app.listen(PORT, () => {
    console.log(`Server bot berjalan di http://localhost:${PORT}`);
    console.log(`Endpoint webhook siap menerima data di /webhook`);
});
