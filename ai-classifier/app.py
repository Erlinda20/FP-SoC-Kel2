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
