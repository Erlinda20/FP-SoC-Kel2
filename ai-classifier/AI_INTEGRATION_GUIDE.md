# 🤖 AI Integration Guide — Mini SOC HITL
> Panduan untuk Tim AI mengintegrasikan model klasifikasi ke pipeline SOAR

---

## 📋 Ringkasan Tugas Tim AI

Tim AI bertugas membangun komponen **AI Classifier** yang menjadi "otak" dalam pipeline HITL (Human-in-the-Loop). Model ini memutuskan apakah sebuah alert dari Wazuh adalah ancaman nyata atau false positive.

---

## 🏗️ Arsitektur Lengkap

```
vm-agent-01 (Attacker)
    │ hping3 SYN Flood
    ▼
vm-agent-02 (Victim)
    │ iptables LOG → kern.log
    ▼
wazuh-agent → wazuh-manager
    │ rule 100004 terpicu
    ▼
notify-n8n.sh (active response)
    │ HTTP POST webhook
    ▼
n8n Workflow
    │
    ├── HTTP Request → Flask AI API  ← BAGIAN TIM AI
    │       │
    │       ├── confidence > 0.8 (True Positive)
    │       │     └── SSH → iptables DROP + TheHive Case
    │       │
    │       ├── 0.4 < confidence < 0.8 (Uncertain)
    │       │     └── TheHive Task → SOC Analyst review
    │       │           └── Approve → Block IP
    │       │           └── Reject → Dismiss
    │       │
    │       └── confidence < 0.4 (False Positive)
    │             └── Log saja, tidak diblok
    │
    └── TheHive Case (semua alert tercatat)
```

---

## 📦 Yang Perlu Tim AI Buat

### 1. Model Klasifikasi (`model.pkl`)

Model harus bisa menerima fitur dari alert Wazuh dan mengembalikan prediksi.

**Input fitur:**
```python
{
    "rule_level": 12,          # Level alert Wazuh (1-15)
    "firedtimes": 95,          # Berapa kali rule ini terpicu
    "rule_id": 100004,         # ID rule
    "hour_of_day": 22,         # Jam kejadian (0-23)
    "is_internal_ip": 1,       # 1 jika IP internal (10.x.x.x), 0 jika eksternal
    "packets_per_second": 50,  # Estimasi dari rate limit iptables
    "dst_port": 80             # Port yang diserang
}
```

**Output:**
```python
{
    "label": "true_positive",  # atau "false_positive"
    "confidence": 0.94,        # 0.0 - 1.0
    "action": "block"          # "block", "review", atau "dismiss"
}
```

**Threshold yang disarankan:**
```
confidence > 0.8  → action: "block"   (otomatis diblok)
0.4 - 0.8        → action: "review"  (butuh approval SOC)
confidence < 0.4  → action: "dismiss" (false positive, abaikan)
```

---

### 2. Flask API (`app.py`)

API ini yang dipanggil oleh n8n. Tim AI harus buat file ini.

**Template yang harus diikuti:**

```python
from flask import Flask, request, jsonify
import pickle
import numpy as np
import ipaddress
from datetime import datetime

app = Flask(__name__)

# Load model saat startup
with open('model.pkl', 'rb') as f:
    model = pickle.load(f)

def is_internal_ip(ip_str):
    """Cek apakah IP termasuk range internal Azure VNet"""
    try:
        ip = ipaddress.ip_address(ip_str)
        return int(ip.is_private)
    except:
        return 0

def extract_features(alert_data):
    """Extract fitur dari payload n8n"""
    timestamp = alert_data.get('timestamp', '')
    try:
        dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
        hour = dt.hour
    except:
        hour = 0

    return np.array([[
        int(alert_data.get('rule_level', 0)),
        int(alert_data.get('firedtimes', 1)),
        int(alert_data.get('rule_id', 0)),
        hour,
        is_internal_ip(alert_data.get('attacker_ip', '0.0.0.0')),
        50,  # default packets_per_second (dari rate limit iptables)
        int(alert_data.get('dst_port', 80))
    ]])

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok", "model": "loaded"})

@app.route('/predict', methods=['POST'])
def predict():
    data = request.get_json()
    
    if not data:
        return jsonify({"error": "No data provided"}), 400
    
    try:
        features = extract_features(data)
        
        # Prediksi
        prediction = model.predict(features)[0]
        
        # Confidence score
        if hasattr(model, 'predict_proba'):
            proba = model.predict_proba(features)[0]
            confidence = float(max(proba))
        else:
            confidence = 1.0 if prediction == 1 else 0.0
        
        # Tentukan action berdasarkan confidence
        if confidence > 0.8 and prediction == 1:
            action = "block"
        elif confidence > 0.4:
            action = "review"
        else:
            action = "dismiss"
        
        label = "true_positive" if prediction == 1 else "false_positive"
        
        return jsonify({
            "label": label,
            "confidence": round(confidence, 4),
            "action": action,
            "features_used": {
                "rule_level": int(features[0][0]),
                "firedtimes": int(features[0][1]),
                "rule_id": int(features[0][2]),
                "hour_of_day": int(features[0][3]),
                "is_internal_ip": int(features[0][4])
            }
        })
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
```

---

### 3. Training Script (`train.py`)

**Opsi A — Pakai data real dari Wazuh:**

```python
import json
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report
import pickle
import ipaddress
from datetime import datetime

def parse_alerts(alerts_file):
    """Parse alerts.json dari Wazuh"""
    records = []
    
    with open(alerts_file) as f:
        for line in f:
            try:
                alert = json.loads(line.strip())
                
                rule_id = int(alert.get('rule', {}).get('id', 0))
                rule_level = int(alert.get('rule', {}).get('level', 0))
                firedtimes = int(alert.get('rule', {}).get('firedtimes', 1))
                srcip = alert.get('data', {}).get('srcip', '0.0.0.0')
                timestamp = alert.get('timestamp', '')
                
                # Parse jam
                try:
                    dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
                    hour = dt.hour
                except:
                    hour = 0
                
                # Cek IP internal
                try:
                    ip = ipaddress.ip_address(srcip)
                    is_internal = int(ip.is_private)
                except:
                    is_internal = 0
                
                # Label: rule 100004 = True Positive (DDoS nyata)
                # Rule lain bisa jadi false positive tergantung konteks
                label = 1 if rule_id == 100004 else 0
                
                records.append({
                    'rule_level': rule_level,
                    'firedtimes': firedtimes,
                    'rule_id': rule_id,
                    'hour_of_day': hour,
                    'is_internal_ip': is_internal,
                    'packets_per_second': 50,
                    'dst_port': 80,
                    'label': label
                })
            except:
                continue
    
    return pd.DataFrame(records)

# Load data
df = parse_alerts('/var/ossec/logs/alerts/alerts.json')
print(f"Total alerts: {len(df)}")
print(f"True Positive: {df['label'].sum()}")
print(f"False Positive: {len(df) - df['label'].sum()}")

# Features dan label
X = df[['rule_level', 'firedtimes', 'rule_id', 
        'hour_of_day', 'is_internal_ip', 'packets_per_second', 'dst_port']]
y = df['label']

# Split
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)

# Train Random Forest
model = RandomForestClassifier(
    n_estimators=100,
    max_depth=10,
    random_state=42
)
model.fit(X_train, y_train)

# Evaluasi
y_pred = model.predict(X_test)
print("\n=== Classification Report ===")
print(classification_report(y_test, y_pred, 
      target_names=['False Positive', 'True Positive']))

# Simpan model
with open('model.pkl', 'wb') as f:
    pickle.dump(model, f)

print("\nModel disimpan ke model.pkl")
```

**Opsi B — Dataset Sintetis (jika data real kurang):**

```python
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
import pickle

np.random.seed(42)
n_samples = 10000

# True Positive (DDoS nyata) — 30% dari dataset
n_tp = int(n_samples * 0.3)
tp = pd.DataFrame({
    'rule_level': np.random.randint(10, 15, n_tp),
    'firedtimes': np.random.randint(50, 500, n_tp),
    'rule_id': np.random.choice([100004], n_tp),
    'hour_of_day': np.random.randint(0, 24, n_tp),
    'is_internal_ip': np.random.choice([0, 1], n_tp, p=[0.7, 0.3]),
    'packets_per_second': np.random.randint(40, 100, n_tp),
    'dst_port': np.random.choice([80, 443, 8080], n_tp),
    'label': 1
})

# False Positive — 70% dari dataset
n_fp = n_samples - n_tp
fp = pd.DataFrame({
    'rule_level': np.random.randint(1, 8, n_fp),
    'firedtimes': np.random.randint(1, 20, n_fp),
    'rule_id': np.random.choice([5710, 5501, 5502, 1002], n_fp),
    'hour_of_day': np.random.randint(0, 24, n_fp),
    'is_internal_ip': np.random.choice([0, 1], n_fp, p=[0.3, 0.7]),
    'packets_per_second': np.random.randint(1, 20, n_fp),
    'dst_port': np.random.choice([22, 80, 443], n_fp),
    'label': 0
})

df = pd.concat([tp, fp]).sample(frac=1).reset_index(drop=True)

X = df.drop('label', axis=1)
y = df['label']

model = RandomForestClassifier(n_estimators=100, random_state=42)
model.fit(X, y)

with open('model.pkl', 'wb') as f:
    pickle.dump(model, f)

print("Model sintetis disimpan ke model.pkl")
```

---

### 4. Requirements (`requirements.txt`)

```
flask==3.0.0
scikit-learn==1.4.0
numpy==1.26.0
pandas==2.1.0
gunicorn==21.2.0
```

---

### 5. Systemd Service (`ai-classifier.service`)

File ini nanti dipakai Ansible untuk auto-start model saat VM restart:

```ini
[Unit]
Description=SOAR AI Classifier Service
After=network.target

[Service]
Type=simple
User=azureuser
WorkingDirectory=/home/azureuser/ai-classifier
ExecStart=/home/azureuser/ai-classifier/venv/bin/gunicorn \
    --workers 2 \
    --bind 0.0.0.0:5000 \
    app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

---

## 📁 Struktur Folder yang Harus Tim AI Buat

```
ai-classifier/
├── app.py              # Flask API (template sudah ada di atas)
├── train.py            # Script training
├── model.pkl           # Model hasil training (generate dulu)
├── requirements.txt    # Dependencies
├── ai-classifier.service  # Systemd service
└── README.md           # Dokumentasi model
```

---

## 🔗 Format Payload dari n8n ke Flask

n8n akan kirim HTTP POST ke `http://10.0.1.4:5000/predict` dengan body:

```json
{
    "alert_level": "12",
    "rule_id": "100004",
    "attacker_ip": "10.0.1.5",
    "victim_ip": "10.0.1.6",
    "attack_type": "DDoS SYN Flood",
    "victim_agent": "agent-server-02",
    "timestamp": "2026-06-22T00:00:00Z",
    "firedtimes": "95",
    "dst_port": "80"
}
```

Flask akan reply:

```json
{
    "label": "true_positive",
    "confidence": 0.94,
    "action": "block"
}
```

n8n kemudian putuskan:
- `action: "block"` → jalankan SSH block IP + buat TheHive case
- `action: "review"` → buat TheHive task untuk SOC analyst
- `action: "dismiss"` → log saja, tidak ada aksi

---

## ✅ Checklist Tim AI

```
[ ] 1. Pilih dataset: real / sintetis / hybrid
[ ] 2. Jalankan train.py → generate model.pkl
[ ] 3. Buat app.py (pakai template di atas)
[ ] 4. Test lokal: python app.py
[ ] 5. Test endpoint: curl -X POST http://localhost:5000/predict -H "Content-Type: application/json" -d '{"alert_level":"12","rule_id":"100004","attacker_ip":"10.0.1.5","firedtimes":"95"}'
[ ] 6. Upload ke GitHub: folder ai-classifier/
[ ] 7. Kabari tim SOAR untuk integrasi ke n8n dan Ansible
```

---

## 📊 Metrics yang Harus Dilaporkan

Sesuai requirement tugas:

| Metric | Penjelasan |
|---|---|
| **Precision** | Dari yang diprediksi TP, berapa yang benar TP |
| **Recall** | Dari semua TP nyata, berapa yang berhasil dideteksi |
| **F1-Score** | Harmonic mean precision & recall |
| **False Positive Rate** | Berapa % alert normal yang salah diklasifikasi sebagai ancaman |
| **False Negative Rate** | Berapa % ancaman nyata yang lolos |

Target minimal:
- Precision ≥ 0.85
- Recall ≥ 0.90 (jangan sampai ancaman nyata lolos)
- FPR ≤ 0.10

---

## 🤝 Koordinasi dengan Tim SOAR

Setelah model selesai, tim AI perlu kabari tim SOAR untuk:

1. **Upload `model.pkl` + `app.py`** ke manager VM di path `/home/azureuser/ai-classifier/`
2. **Tim SOAR akan tambahkan** Ansible role `ai_service` yang install dependencies dan start Flask sebagai service
3. **Tim SOAR akan update** n8n workflow untuk panggil `/predict` sebelum block IP
4. **Test bersama** dengan simulasi serangan

---

*Dokumen ini dibuat untuk koordinasi antara Tim AI dan Tim SOAR pada proyek Mini SOC HITL — MIKS Lab Kelompok K1*
