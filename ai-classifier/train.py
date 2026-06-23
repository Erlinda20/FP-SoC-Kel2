import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report
import pickle

# Template training script (Sintetis)
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

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

model = RandomForestClassifier(n_estimators=100, max_depth=10, random_state=42)
model.fit(X_train, y_train)

print("\n=== Classification Report ===")
print(classification_report(y_test, model.predict(X_test), target_names=['False Positive', 'True Positive']))

with open('model.pkl', 'wb') as f:
    pickle.dump(model, f)

print("Model sintetis disimpan ke model.pkl")
