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

### 2. Cara Menjalankan (How to Run) via IaC Ansible

Proyek ini telah dibungkus dalam Ansible Playbook yang *idempotent* dan sepenuhnya otomatis, meminimalisir konfigurasi manual.

**Persiapan:**
1. Clone repositori ini ke *control node* (misal: WSL atau mesin lokal Linux).
2. Pastikan `ansible` sudah terinstal di sistem Anda.
3. Sesuaikan `inventory/hosts.ini` dengan IP publik Azure VM Anda dan path menuju kunci SSH `.pem`.
4. Untuk automasi n8n, buat API Key secara manual melalui UI n8n, lalu simpan kuncinya di file manager VM: 
   ```bash
   echo "YOUR_API_KEY" > ~/.n8n_api_key
   ```

**Eksekusi Deployment:**
Jalankan perintah berikut di root repositori:
```bash
ansible-playbook -i inventory/hosts.ini site.yml
```

**Apa yang dilakukan playbook?**
- Mempersiapkan konfigurasi jaringan, `iptables`, dan *systemd webserver* di agen korban.
- Melakukan sinkronisasi Wazuh Manager, menginjeksi aturan deteksi kustom, dan mengkonfigurasi *Active Response* secara dinamis tanpa merusak file asli.
- Memastikan Docker Stack SOAR (Elasticsearch, n8n, TheHive) berjalan sempurna.
- Menginisialisasi TheHive secara otomatis via REST API (membuat Organisasi, mendaftarkan User, dan meregenerasi API Key).
- Melakukan automasi penuh di n8n via API (merakit *credentials* TheHive/SSH, mengimpor alur kerja respon otomatis, dan mem-publish-nya).

### 3. Scenario & SIEM Detection

Sistem SIEM diuji untuk mendeteksi tiga vektor serangan utama:

- **DDoS (SYN Flood):** Disimulasikan menggunakan `hping3` dari agen penyerang. Agen korban mencatat trafik berlebih menggunakan batas log `iptables` (dibatasi 50 baris/detik untuk mencegah disk penuh), yang kemudian ditangkap Wazuh untuk memicu *Rule Level 12* (Massive SYN Flood Traffic).
- **Malware:** *[Tulis detail eksekusi dan deteksi malware di sini]*
- **Social Engineering:** *[Tulis detail eksekusi dan deteksi social engineering di sini]*

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
