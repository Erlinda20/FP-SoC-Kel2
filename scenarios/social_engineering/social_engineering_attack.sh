#!/bin/bash
# ================================================================
# SOC Lab — Skenario Social Engineering (LENGKAP)
# ================================================================
# Skenario ini mensimulasikan serangan social engineering 3 fase:
#
#  FASE 1 — Reconnaissance   : Port scan & info gathering
#  FASE 2 — Phishing Setup   : Deploy fake portal + kirim "email"
#  FASE 3 — Post-Compromise  : Aktivitas setelah credential dicuri
#
# Target : vm-agent-02 (10.0.1.6 / 20.2.49.57)
# Attacker: vm-agent-01 (10.0.1.5)
#
# Jalankan dari vm-agent-01:
#   chmod +x social_engineering_attack.sh
#   sudo ./social_engineering_attack.sh
# ================================================================

set -euo pipefail

# ── Konfigurasi ─────────────────────────────────────────────────
VICTIM_PRIVATE_IP="10.0.1.6"
VICTIM_PUBLIC_IP="20.2.49.57"
VICTIM_SSH_KEY="$HOME/.ssh/key-wazuh-agent02.pem"
VICTIM_USER="azureuser"
ATTACKER_IP="10.0.1.5"
PHISHING_PORT="8080"
SCENARIO_DIR="/tmp/se_scenario"
LOG_FILE="$SCENARIO_DIR/attack.log"

# Warna
RED='\033[0;31m'; YEL='\033[1;33m'; GRN='\033[0;32m'
BLU='\033[0;34m'; CYN='\033[0;36m'; WHT='\033[1;37m'; NC='\033[0m'

print_banner() {
  echo -e "${BLU}"
  echo "  ╔══════════════════════════════════════════════════════╗"
  echo "  ║   SOC Lab — Social Engineering Attack Scenario       ║"
  echo "  ║   [FOR EDUCATIONAL USE ONLY — Lab Environment]       ║"
  echo "  ╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
}

log() { echo -e "${WHT}[$(date '+%H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"; }
ok()  { echo -e "${GRN}  ✓ $*${NC}" | tee -a "$LOG_FILE"; }
warn(){ echo -e "${YEL}  ⚠ $*${NC}" | tee -a "$LOG_FILE"; }
err() { echo -e "${RED}  ✗ $*${NC}" | tee -a "$LOG_FILE"; }
sep() { echo -e "${BLU}  ─────────────────────────────────────────────${NC}"; }

mkdir -p "$SCENARIO_DIR"
print_banner

# ================================================================
# FASE 1: RECONNAISSANCE
# ================================================================
echo -e "${CYN}━━━ FASE 1: RECONNAISSANCE ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
sep

log "🔍 Memulai port scan pada target: $VICTIM_PRIVATE_IP"

# Generate realistic Wazuh alert via logger
logger -t "RECONNAISSANCE" -p "auth.warning" \
  "PORT_SCAN_DETECTED: src=$ATTACKER_IP dst=$VICTIM_PRIVATE_IP \
   method=SYN_SCAN ports=22,80,443,8080,5000 \
   tool=nmap attack_phase=reconnaissance"

# Simulasi scan (cek port yang open)
log "Mengecek port yang terbuka di target..."
for port in 22 80 443 8080 5000; do
  if timeout 2 bash -c "echo >/dev/tcp/$VICTIM_PRIVATE_IP/$port" 2>/dev/null; then
    ok "Port $port: OPEN"
    logger -t "RECON_RESULT" -p "auth.info" \
      "OPEN_PORT: target=$VICTIM_PRIVATE_IP port=$port protocol=TCP"
  else
    warn "Port $port: CLOSED/FILTERED"
  fi
done

log "🌐 Mengumpulkan informasi sistem..."
logger -t "RECONNAISSANCE" -p "auth.warning" \
  "OSINT_GATHERING: target=$VICTIM_PRIVATE_IP \
   technique=banner_grabbing,service_enumeration \
   attacker=$ATTACKER_IP"

echo ""
ok "Fase 1 selesai — Informasi target berhasil dikumpulkan"
echo ""
sleep 2

# ================================================================
# FASE 2: PHISHING SETUP & DEPLOYMENT
# ================================================================
echo -e "${CYN}━━━ FASE 2: PHISHING SETUP & DEPLOYMENT ━━━━━━━━━━━━━━━━━━━${NC}"
sep

log "🎣 Menyiapkan infrastruktur phishing..."

# Copy file phishing ke victim (simulate attacker mendeploy halaman)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log "Mengupload halaman phishing ke server korban..."

if [ -f "$VICTIM_SSH_KEY" ]; then
  # Copy phishing files ke victim
  scp -i "$VICTIM_SSH_KEY" -o StrictHostKeyChecking=no \
    "$SCRIPT_DIR/index.html" \
    "$SCRIPT_DIR/error.html" \
    "$SCRIPT_DIR/phishing_server.py" \
    "$VICTIM_USER@$VICTIM_PUBLIC_IP:/tmp/phishing/" 2>/dev/null || {
    warn "SSH copy gagal — simulasi log saja"
  }

  # Start phishing server di victim via SSH
  ssh -i "$VICTIM_SSH_KEY" -o StrictHostKeyChecking=no \
    "$VICTIM_USER@$VICTIM_PUBLIC_IP" \
    "mkdir -p /tmp/phishing && cd /tmp/phishing && \
     pip3 install flask -q 2>/dev/null; \
     nohup python3 phishing_server.py > /tmp/phishing/server.log 2>&1 &
     echo Phishing server started on port 8080" 2>/dev/null || warn "SSH gagal, simulasi via logger"

  ok "Phishing server berjalan di http://$VICTIM_PRIVATE_IP:$PHISHING_PORT"
else
  warn "SSH key tidak ditemukan: $VICTIM_SSH_KEY"
  warn "Simulasi via logger saja (tanpa deploy nyata)"
fi

# Log phishing setup activity
logger -t "PHISHING_SETUP" -p "auth.crit" \
  "PHISHING_INFRASTRUCTURE_DEPLOYED: \
   server=$VICTIM_PRIVATE_IP:$PHISHING_PORT \
   page=SIAKAD_UNT_Fake_Portal \
   attacker=$ATTACKER_IP \
   attack_type=social_engineering"

sep
log "📧 Simulasi pengiriman phishing email..."

# Buat konten email phishing yang realistis
PHISHING_EMAIL="$SCENARIO_DIR/phishing_email.txt"
cat > "$PHISHING_EMAIL" << EOF
=== SIMULASI EMAIL PHISHING ===
(Email ini TIDAK benar-benar terkirim — hanya untuk dokumentasi lab)

From:    no-reply@siakad-unt.ac.id  [SPOOFED]
To:      mahasiswa@unt.ac.id
Subject: ⚠️ [URGENT] Akun SIAKAD Anda akan dinonaktifkan — Verifikasi Sekarang

-----------------------------------------------------------------------
Kepada Yth. Mahasiswa Universitas Nusantara Teknologi,

Sistem kami mendeteksi aktivitas mencurigakan pada akun SIAKAD Anda.
Demi keamanan data akademik, akun Anda akan DINONAKTIFKAN dalam
24 JAM jika tidak dilakukan verifikasi.

Klik link berikut untuk memverifikasi akun Anda:
  ➤ http://$VICTIM_PRIVATE_IP:$PHISHING_PORT/

[VERIFIKASI AKUN SEKARANG]

Jika tidak melakukan verifikasi, Anda TIDAK DAPAT:
  ✗ Mengisi KRS Semester Ganjil 2026/2027
  ✗ Mengakses nilai ujian akhir semester
  ✗ Mencetak transkrip nilai
  ✗ Mendaftar wisuda

Hormat kami,
Tim IT Security
Universitas Nusantara Teknologi
helpdesk@unt.ac.id | (021) 1234-5678

JANGAN BALAS EMAIL INI — Ini adalah email otomatis dari sistem kami.
-----------------------------------------------------------------------
[Pesan ini dikirim ke seluruh mahasiswa aktif UNT]
EOF

cat "$PHISHING_EMAIL"

# Log email phishing activity
logger -t "PHISHING_EMAIL" -p "mail.warning" \
  "PHISHING_EMAIL_SENT: \
   from=no-reply@siakad-unt.ac.id \
   to=mahasiswa@unt.ac.id \
   subject=URGENT_Account_Deactivation \
   link=http://$VICTIM_PRIVATE_IP:$PHISHING_PORT \
   attack_type=social_engineering_phishing \
   urgency_technique=account_suspension_threat"

ok "Email phishing ter-log di Wazuh"
echo ""
sleep 2

# ================================================================
# FASE 2B: SIMULASI KORBAN MENGKLIK LINK & SUBMIT CREDENTIAL
# ================================================================
echo -e "${CYN}━━━ FASE 2B: VICTIM INTERACTION SIMULATION ━━━━━━━━━━━━━━━━${NC}"
sep

log "👤 Mensimulasikan korban mengakses halaman phishing..."

# Simulasi korban mengunjungi halaman phishing
logger -t "PHISHING_ALERT" -p "auth.warning" \
  "PHISHING_PAGE_VISIT: src=192.168.1.100 \
   url=http://$VICTIM_PRIVATE_IP:$PHISHING_PORT \
   user_agent=Mozilla/5.0 attack_type=social_engineering"

sleep 1

# Simulasi korban submit credential
log "🔑 Mensimulasikan pengiriman credential oleh korban..."

# Jika server berjalan, kirim request nyata
if curl -s --max-time 3 "http://$VICTIM_PRIVATE_IP:$PHISHING_PORT/" > /dev/null 2>&1; then
  log "Server phishing aktif — mengirim credential test..."

  # Simulasi 3 korban berbeda
  declare -a VICTIMS=("2021310001:P@ssw0rd123" "2020210045:akademik2024" "dosen.budi:Dosenbudi!")
  for victim in "${VICTIMS[@]}"; do
    USER="${victim%%:*}"
    PASS="${victim##*:}"

    RESPONSE=$(curl -s -X POST \
      "http://$VICTIM_PRIVATE_IP:$PHISHING_PORT/login" \
      -d "username=$USER&password=$PASS" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -L --max-time 5 -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")

    ok "Credential dikirim: user=$USER | HTTP=$RESPONSE"
    sleep 0.5
  done

else
  warn "Server tidak aktif — logging credential harvest via syslog"

  # Fallback: log langsung ke syslog
  for victim in "2021310001:P@ssw0rd123" "2020210045:akademik2024" "dosen.budi:Dosenbudi!"; do
    USER="${victim%%:*}"
    logger -t "PHISHING_ALERT" -p "auth.crit" \
      "CREDENTIAL_HARVESTED: username=$USER \
       src=192.168.1.100 \
       attack_type=social_engineering_phishing \
       page=SIAKAD_UNT_Fake_Portal \
       severity=CRITICAL"
    ok "Credential log: $USER"
    sleep 0.3
  done
fi

echo ""
sleep 2

# ================================================================
# FASE 3: POST-COMPROMISE ACTIVITY
# ================================================================
echo -e "${CYN}━━━ FASE 3: POST-COMPROMISE ACTIVITY ━━━━━━━━━━━━━━━━━━━━━━${NC}"
sep

log "💀 Mensimulasikan aktivitas setelah akun berhasil dikompromis..."
log "(Attacker menggunakan credential curian untuk login)"

# Simulasi attacker login dengan credential curian
logger -t "sshd" -p "auth.info" \
  "Accepted password for azureuser from $ATTACKER_IP port 54321 ssh2 [SIMULATED_STOLEN_CREDENTIAL]"

logger -t "SOCIAL_ENG_POSTCOMPROMISE" -p "auth.crit" \
  "ACCOUNT_TAKEOVER: \
   method=stolen_credential \
   victim_user=2021310001 \
   attacker=$ATTACKER_IP \
   technique=phishing \
   attack_type=social_engineering"

sleep 1

log "📁 Simulasi akses ke data sensitif..."

# Log reconnaissance pasca kompromi
for cmd in "cat /etc/passwd" "cat /etc/shadow" "ls -la /home" "id" "whoami" "uname -a" "ip a"; do
  logger -t "POSTCOMPROMISE" -p "auth.warning" \
    "COMMAND_EXECUTED: cmd='$cmd' user=2021310001 src=$ATTACKER_IP"
  sleep 0.2
done

log "📤 Simulasi data exfiltration..."
logger -t "POSTCOMPROMISE" -p "auth.crit" \
  "DATA_EXFILTRATION_ATTEMPT: \
   src=$ATTACKER_IP \
   dst=185.220.101.45 \
   size_bytes=48291 \
   content=student_database_dump \
   attack_type=social_engineering_postcompromise"

logger -t "LATERAL_MOVEMENT" -p "auth.warning" \
  "LATERAL_MOVEMENT_ATTEMPT: \
   src=$VICTIM_PRIVATE_IP \
   dst=10.0.1.4 \
   method=stolen_ssh_key \
   user=2021310001"

echo ""
ok "Fase 3 selesai — Semua aktivitas post-compromise ter-log"

# ================================================================
# RINGKASAN
# ================================================================
echo ""
echo -e "${GRN}━━━ ✅ SKENARIO SELESAI ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
sep
echo ""
echo -e "${WHT}Alert Wazuh yang harus muncul:${NC}"
echo ""
echo -e "  ${YEL}●${NC} Rule 100020 (Level 8)  — Multiple failed SSH login"
echo -e "  ${YEL}●${NC} Rule 100021 (Level 12) — Credential compromise (login success after failure)"
echo -e "  ${YEL}●${NC} Rule 100023 (Level 9)  — Credential submission on web form"
echo -e "  ${YEL}●${NC} Rule 100025 (Level 14) — CREDENTIAL_HARVESTED (CRITICAL)"
echo ""
echo -e "${WHT}Cara verifikasi di Wazuh:${NC}"
echo -e "  1. Buka: ${CYN}https://20.255.112.239${NC}"
echo -e "  2. Security Events → Filter: rule.groups: social_engineering"
echo -e "  3. Authentication → Filter: agent.name: vm-agent-02"
echo ""
echo -e "${WHT}Log yang dihasilkan:${NC}"
echo -e "  ${CYN}$LOG_FILE${NC}"
echo ""
