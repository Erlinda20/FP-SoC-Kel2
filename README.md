# Final Project Security Operation Center

**Kelompok:** 2  
**Anggota Tim:**
1. [Anggota 1]
2. [Anggota 2]
3. [Anggota 3]
4. [Anggota 4]
5. [Anggota 5]
6. [Anggota 6]
7. [Anggota 7] *(Opsional)*
8. [Anggota 8] *(Opsional)*

---

## Reducing SOC False Alarms through a Human-AI Collaboration Model

### Background
The high rate of false positives in the Security Operations Center (SOC) is often caused by the *"Better Safe Than Sorry"* philosophy, which prioritizes recall to ensure no threats are missed. This increases system sensitivity but also triggers excessive alerts, leading to burnout for the SOC team. Furthermore, the dynamic nature of cyber threats makes it difficult to manually differentiate between safe and malicious activity.

### Project Task
Develop a Human-AI Collaboration SOC system that reduces false alarms without compromising detection accuracy.

---

## Project Specifications

1. **Architecture:** The system configuration integrates a Wazuh Manager unit, a SOAR platform, and several Wazuh Agents, all operated on the Azure free-tier student server infrastructure.
2. **Scenario:** The scenario includes DDoS, Malware, and Social Engineering attacks.
3. **Analysis:** Independently define the criteria for false alarms based on data from Wazuh.
4. **AI Integration:** Integrate an AI model into the Wazuh architecture to reduce false alarms. The development of the AI model must be done independently, and the use of third-party API services is not permitted.
5. **SOAR:** Use SOAR to prove that the architecture is still capable of responding effectively to attacks.

---

## Deliverables & Documentation

### 1. Architecture Details
Proyek ini di-deploy secara otomatis menggunakan **Infrastructure as Code (IaC) via Ansible Playbook** untuk menjamin *idempotency*, stabilitas, dan kemudahan replikasi.

- **Wazuh Manager:** Bertindak sebagai SIEM sentral (`vm-wazuh-manager`).
- **Wazuh Agents:** Dideploy di node endpoints (`vm-agent-01`, `vm-agent-02`).
- **SOAR Platform:** Menggunakan **n8n** (Automasi Workflow) dan **TheHive 5** (Incident Management), berjalan via Docker Stack di Manager.

### 2. Panduan Setup & Menjalankan Lingkungan (How to Run)

Proyek ini telah dibungkus dalam Ansible Playbook yang *idempotent* dan sepenuhnya otomatis. Ikuti panduan ini untuk membangun lingkungan dari nol:

**Langkah 1: Persiapan Server & Ansible**
1. Clone repositori ini ke mesin *control node* (misal: WSL atau mesin lokal Linux).
2. Sesuaikan file `inventory/hosts.ini` dengan IP publik Azure VM Anda dan pastikan *path* kunci SSH `.pem` sudah benar.
3. Jalankan instalasi awal stack Ansible:
   ```bash
   ansible-playbook -i inventory/hosts.ini site.yml
   ```
   *(Tunggu hingga proses selesai. Playbook ini akan menginstal Wazuh, mengonfigurasi iptables korban, dan menjalankan kontainer Docker n8n + TheHive di Manager).*

**Langkah 2: Menyiapkan Akses API n8n**
Agar Ansible bisa memasukkan *workflow* ke dalam n8n secara otomatis, kita butuh API Key dari n8n:
1. Buka browser dan akses n8n di: `http://<IP_Manager>:5678`
2. Buat akun admin n8n (untuk pertama kali setup).
3. Masuk ke **Settings > n8n API**, lalu klik **Create API Key**.
4. *Copy* API Key tersebut.
5. Kembali ke terminal Server Manager (`vm-wazuh-manager`), simpan key tersebut ke dalam file:
   ```bash
   echo "Masukkan_API_Key_n8n_Disini" > ~/.n8n_api_key
   ```

**Langkah 3: Finalisasi Konfigurasi (Run Kedua)**
Jalankan ulang playbook agar Ansible bisa membaca API Key n8n dan memasukkan semua *workflow* SOAR serta melakukan inisialisasi TheHive:
```bash
ansible-playbook -i inventory/hosts.ini site.yml
```

### 3. Simulasi Serangan & Pertahanan (Attack & Defense)

Sistem SIEM diuji untuk mendeteksi tiga vektor serangan utama. Berikut adalah panduan *direct* untuk melakukan simulasi serangan DDoS dan melihat respons otomatis SOAR:

**A. Melakukan Serangan (Dari vm-agent-01 / Attacker)**
1. SSH ke dalam mesin penyerang (`vm-agent-01`).
2. Jalankan perintah `hping3` untuk melakukan **SYN Flood** ke IP privat mesin korban (`vm-agent-02` - misal: 10.0.1.6):
   ```bash
   sudo hping3 -S --flood -V -p 80 10.0.1.6
   ```
   *(Biarkan perintah ini berjalan selama 5-10 detik, lalu hentikan dengan `Ctrl+C`)*.

**B. Memantau Deteksi & Respons (Defense Validation)**
Setelah serangan diluncurkan, periksa 3 lapisan pertahanan berikut untuk membuktikan SOAR berjalan:
1. **Verifikasi Wazuh Alert:** Buka Dashboard Wazuh di `https://<IP_Manager>`. Cek halaman *Security Events*. Pastikan **Rule Level 12 (Massive SYN Flood Traffic)** muncul merah.
2. **Verifikasi Blokir IP di Korban:** SSH ke mesin korban (`vm-agent-02`) dan cek `iptables`. IP penyerang harus berada di aturan `DROP`:
   ```bash
   sudo iptables -L INPUT -n -v | grep DROP
   ```
3. **Verifikasi Insiden TheHive:** Buka TheHive di `http://<IP_Manager>:9000` (Login: `admin@thehive.local` / `secret`). Cek tab **Cases**. Sebuah insiden baru otomatis terbuat berisi IP penyerang sebagai *Observable*.

*(Untuk Malware dan Social Engineering, silakan tambahkan langkah eksploitasi dan deteksinya di bawah ini)*

- **Malware:** *[Tulis langkah simulasi eksekusi dan deteksi malware di sini]*
- **Social Engineering:** *[Tulis langkah simulasi eksekusi dan deteksi social engineering di sini]*

**Grafik dan Alert SIEM:**
- ![Alert Dashboard Wazuh](assets/06_Grafik_Alert_Level12.png)
- ![Detail Log Serangan](assets/07_Detail_Log_Serangan.png)

### 4. SOAR Integration & Response

Kami membuktikan arsitektur tidak hanya bisa mendeteksi, tapi juga **merespons serangan secara efektif dan seketika**. Ketika *Active Response* Wazuh mendeteksi aktivitas berbahaya (contoh: DDoS):
1. Wazuh memicu skrip lokal `notify-n8n.sh` dan mengirimkan JSON log menuju *webhook* n8n.
2. Workflow n8n memproses payload dan mengekstrak IP penyerang.
3. n8n mengeksekusi *remote SSH command* ke agen korban untuk memblokir IP tersebut di level firewall (`iptables DROP`).
4. Pada saat bersamaan, n8n menghubungi TheHive API untuk membuat *Incident Case* baru dan mendaftarkan *Observable* (IP penyerang) agar tim SOC memiliki rekam jejak forensik.

**Dokumentasi Eksekusi SOAR:**
- **Stack SOAR Aktif:** ![Docker Stack](assets/08_Docker_Stack_Running.png)
- **Workflow n8n:** ![N8N Workflow](assets/10_N8N_Workflow.png)
- **Insiden Tercatat di TheHive:** ![TheHive Cases](assets/13_TheHive_Cases.png)

### 5. AI Integration & Analysis (False Alarm Reduction)

*(Bagian di bawah ini adalah placeholder untuk laporan integrasi model AI buatan kelompok. Silakan dilengkapi sesuai progres pengembangan model AI Anda)*

- **Analisis Kriteria False Alarm:**
  *[Jelaskan secara mandiri kriteria false alarm yang berhasil Anda petakan berdasarkan observasi dari data/event log Wazuh]*

- **Penjelasan Model AI:**
  *[Jelaskan arsitektur model AI yang telah dikembangkan secara independen (tanpa layanan API pihak ketiga), algoritma yang dipilih, serta dataset pelatihan]*

- **Metode Integrasi:**
  *[Jelaskan alur bagaimana model AI tersebut diintegrasikan ke dalam arsitektur Wazuh untuk menyaring atau memberi bobot ulang pada alert]*

- **Benchmark Metrics:**
  *[Tampilkan hasil evaluasi model: misal Confusion Matrix, Accuracy, Precision, Recall]*

- **Analisis Dampak (Human-AI Collaboration):**
  *[Berikan simpulan mengenai efektivitas model ini. Seberapa banyak false alarm yang berkurang? Apakah ini membantu menurunkan tingkat kelelahan tim SOC?]*
