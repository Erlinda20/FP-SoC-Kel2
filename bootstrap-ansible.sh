#!/bin/bash
# ============================================================
# SOAR Ansible Bootstrap Script
# Jalankan di WSL: bash bootstrap-ansible.sh
# Akan membuat struktur folder + semua file ansible di ~/soar-ansible
# ============================================================

set -e
BASE="$HOME/soar-ansible"

echo "======================================================"
echo " SOAR Ansible Bootstrap"
echo " Target: $BASE"
echo "======================================================"

# Backup folder lama jika ada
if [ -d "$BASE" ]; then
  echo "[INFO] Backup folder lama ke ~/soar-ansible.bak..."
  rm -rf "$HOME/soar-ansible.bak"
  cp -r "$BASE" "$HOME/soar-ansible.bak"
  rm -rf "$BASE"
fi

# Buat struktur folder
mkdir -p "$BASE/inventory"
mkdir -p "$BASE/roles/iptables/tasks"
mkdir -p "$BASE/roles/iptables/defaults"
mkdir -p "$BASE/roles/wazuh/tasks"
mkdir -p "$BASE/roles/docker_stack/tasks"
mkdir -p "$BASE/roles/thehive_init/tasks"
mkdir -p "$BASE/roles/thehive_init/defaults"

echo "[OK] Struktur folder dibuat."

# ──────────────────────────────────────────────
# inventory/hosts.ini
# ──────────────────────────────────────────────
cat > "$BASE/inventory/hosts.ini" << 'EOF'
[manager]
vm-wazuh-manager ansible_host=20.255.112.239 ansible_user=azureuser ansible_ssh_private_key_file=~/.ssh/key-wazuh-manager.pem

[agents]
vm-agent-01 ansible_host=104.208.124.163 ansible_user=azureuser ansible_ssh_private_key_file=~/.ssh/key-wazuh-agent01.pem
vm-agent-02 ansible_host=20.2.49.57      ansible_user=azureuser ansible_ssh_private_key_file=~/.ssh/key-wazuh-agent02.pem

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

# ──────────────────────────────────────────────
# site.yml
# ──────────────────────────────────────────────
cat > "$BASE/site.yml" << 'EOF'
---
- name: Setup iptables persistent di agent-02
  hosts: vm-agent-02
  become: true
  roles:
    - iptables

- name: Setup Wazuh active response di manager
  hosts: manager
  become: true
  roles:
    - wazuh

- name: Pastikan Docker stack jalan di manager
  hosts: manager
  become: true
  roles:
    - docker_stack

- name: Init TheHive user + API key
  hosts: manager
  become: false
  roles:
    - thehive_init
EOF

# ──────────────────────────────────────────────
# roles/iptables/defaults/main.yml
# ──────────────────────────────────────────────
cat > "$BASE/roles/iptables/defaults/main.yml" << 'EOF'
---
victim_port: 80
log_prefix: "FIREWALL_DDOS_ALERT: "
rate_limit: "50/s"
rate_burst: 100
EOF

# ──────────────────────────────────────────────
# roles/iptables/tasks/main.yml
# ──────────────────────────────────────────────
cat > "$BASE/roles/iptables/tasks/main.yml" << 'EOF'
---
- name: Install iptables-persistent
  apt:
    name: iptables-persistent
    state: present
    update_cache: yes

- name: Cek apakah rule DDOS LOG sudah ada
  command: iptables -L INPUT -n
  register: iptables_rules
  changed_when: false

- name: Pasang iptables LOG rule untuk DDoS detection
  command: >
    iptables -A INPUT -p tcp --syn --dport {{ victim_port }}
    -m limit --limit {{ rate_limit }} --limit-burst {{ rate_burst }}
    -j LOG --log-prefix "{{ log_prefix }}"
  when: log_prefix not in iptables_rules.stdout

- name: Simpan iptables rules supaya persistent
  command: netfilter-persistent save

- name: Pastikan web server berjalan di port 80
  shell: |
    if ! ss -tlnp | grep -q ':80 '; then
      nohup python3 -m http.server 80 > /tmp/http-server.log 2>&1 &
      echo "started"
    else
      echo "already running"
    fi
  register: webserver_result
  changed_when: "'started' in webserver_result.stdout"

- name: Pastikan kern.log dimonitor wazuh-agent
  blockinfile:
    path: /var/ossec/etc/ossec.conf
    marker: "<!-- {mark} ANSIBLE MANAGED - kern.log -->"
    insertbefore: "</ossec_config>"
    block: |
      <localfile>
        <log_format>syslog</log_format>
        <location>/var/log/kern.log</location>
      </localfile>
  notify: restart wazuh-agent

- name: Tambahkan wazuh ke grup adm supaya bisa baca kern.log
  user:
    name: wazuh
    groups: adm
    append: yes
  notify: restart wazuh-agent

- name: Pastikan wazuh-agent berjalan
  systemd:
    name: wazuh-agent
    state: started
    enabled: yes

handlers:
  - name: restart wazuh-agent
    systemd:
      name: wazuh-agent
      state: restarted
EOF

# ──────────────────────────────────────────────
# roles/wazuh/tasks/main.yml
# ──────────────────────────────────────────────
cat > "$BASE/roles/wazuh/tasks/main.yml" << 'EOF'
---
- name: Tulis local_rules.xml
  copy:
    dest: /var/ossec/rules/local_rules.xml
    content: |
      <group name="local,ddos,syslog,">
        <rule id="100001" level="3">
          <match>FIREWALL_DDOS_ALERT</match>
          <description>iptables: DDoS log entry terdeteksi</description>
        </rule>
        <rule id="100004" level="12" frequency="10" timeframe="5">
          <if_matched_sid>100001</if_matched_sid>
          <match>SYN</match>
          <description>Massive SYN Flood Traffic Detected by Network Firewall</description>
          <group>attack,ddos,</group>
        </rule>
        <rule id="100005" level="10">
          <if_sid>100001</if_sid>
          <description>DDoS Alert dari iptables (non-SYN variant)</description>
          <group>attack,ddos,</group>
        </rule>
      </group>
    owner: root
    group: wazuh
    mode: '0640'
  notify: restart wazuh-manager

- name: Deploy notify-n8n.sh active response script
  copy:
    dest: /var/ossec/active-response/bin/notify-n8n.sh
    content: |
      #!/bin/bash
      LOG_FILE="/var/log/wazuh-n8n-webhook.log"
      N8N_URL="http://localhost:5678/webhook/wazuh-ddos-alert"
      INPUT_JSON=$(cat)
      ATTACKER_IP=$(echo "$INPUT_JSON" | python3 -c "
      import sys, json
      try:
          d = json.load(sys.stdin)
          ip = (d.get('parameters', {}).get('alert', {}).get('data', {}).get('srcip')
             or d.get('parameters', {}).get('alert', {}).get('data', {}).get('src_ip')
             or d.get('data', {}).get('srcip')
             or 'unknown')
          print(ip)
      except:
          print('unknown')
      " 2>/dev/null)
      RULE_ID=$(echo "$INPUT_JSON" | python3 -c "
      import sys, json
      try:
          d = json.load(sys.stdin)
          print(d.get('parameters', {}).get('alert', {}).get('rule', {}).get('id', 'unknown'))
      except:
          print('unknown')
      " 2>/dev/null)
      ALERT_LEVEL=$(echo "$INPUT_JSON" | python3 -c "
      import sys, json
      try:
          d = json.load(sys.stdin)
          print(d.get('parameters', {}).get('alert', {}).get('rule', {}).get('level', 'unknown'))
      except:
          print('unknown')
      " 2>/dev/null)
      TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      echo "$(date '+%Y-%m-%dT%H:%M:%S') [INFO] Active Response triggered. Rule=$RULE_ID Level=$ALERT_LEVEL AttackerIP=$ATTACKER_IP" >> "$LOG_FILE"
      PAYLOAD="{\"alert_level\":\"$ALERT_LEVEL\",\"rule_id\":\"$RULE_ID\",\"attacker_ip\":\"$ATTACKER_IP\",\"victim_ip\":\"10.0.1.6\",\"attack_type\":\"DDoS SYN Flood\",\"victim_agent\":\"agent-server-02\",\"timestamp\":\"$TIMESTAMP\"}"
      HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$PAYLOAD" --connect-timeout 5 --max-time 10 "$N8N_URL" 2>/dev/null)
      echo "$(date '+%Y-%m-%dT%H:%M:%S') [OK] Webhook sent. HTTP=$HTTP_STATUS Rule=$RULE_ID AttackerIP=$ATTACKER_IP" >> "$LOG_FILE"
      exit 0
    owner: root
    group: wazuh
    mode: '0750'
  notify: restart wazuh-manager

- name: Buat webhook log file
  file:
    path: /var/log/wazuh-n8n-webhook.log
    state: touch
    owner: root
    group: wazuh
    mode: '0664'

- name: Tambahkan active-response config ke ossec.conf
  blockinfile:
    path: /var/ossec/etc/ossec.conf
    marker: "<!-- {mark} ANSIBLE MANAGED - active-response -->"
    insertbefore: "</ossec_config>"
    block: |
      <command>
        <name>notify-n8n</name>
        <executable>notify-n8n.sh</executable>
        <timeout_allowed>no</timeout_allowed>
      </command>
      <active-response>
        <command>notify-n8n</command>
        <location>server</location>
        <rules_id>100004</rules_id>
        <timeout>60</timeout>
      </active-response>
  notify: restart wazuh-manager

- name: Pastikan wazuh-manager berjalan
  systemd:
    name: wazuh-manager
    state: started
    enabled: yes

handlers:
  - name: restart wazuh-manager
    systemd:
      name: wazuh-manager
      state: restarted
EOF

# ──────────────────────────────────────────────
# roles/docker_stack/tasks/main.yml
# ──────────────────────────────────────────────
cat > "$BASE/roles/docker_stack/tasks/main.yml" << 'EOF'
---
- name: Pastikan direktori soar-stack ada
  file:
    path: "{{ item }}"
    state: directory
    mode: '0755'
  loop:
    - /home/azureuser/soar-stack
    - /home/azureuser/soar-stack/thehive/data
    - /home/azureuser/soar-stack/thehive/logs
    - /home/azureuser/soar-stack/elasticsearch/data
    - /home/azureuser/soar-stack/n8n/data

- name: Set vm.max_map_count untuk Elasticsearch
  sysctl:
    name: vm.max_map_count
    value: '262144'
    state: present
    reload: yes

- name: Start docker stack jika belum jalan
  command: docker compose -f /home/azureuser/soar-stack/docker-compose.yml up -d
  become_user: azureuser
  register: docker_up
  changed_when: "'Started' in docker_up.stdout or 'Created' in docker_up.stdout"

- name: Tunggu n8n siap
  uri:
    url: http://localhost:5678
    status_code: 200
  register: n8n_check
  retries: 15
  delay: 10
  until: n8n_check.status == 200
  failed_when: false

- name: Tunggu TheHive siap
  uri:
    url: http://localhost:9000/api/v1/status
    status_code: [200, 401]
  register: thehive_check
  retries: 20
  delay: 10
  until: thehive_check.status in [200, 401]
  failed_when: false
EOF

# ──────────────────────────────────────────────
# roles/thehive_init/defaults/main.yml
# ──────────────────────────────────────────────
cat > "$BASE/roles/thehive_init/defaults/main.yml" << 'EOF'
---
thehive_url: "http://localhost:9000"
thehive_admin_user: "admin@thehive.local"
thehive_admin_pass: "secret"
thehive_api_key_file: "/home/azureuser/.thehive_api_key"
EOF

# ──────────────────────────────────────────────
# roles/thehive_init/tasks/main.yml
# ──────────────────────────────────────────────
cat > "$BASE/roles/thehive_init/tasks/main.yml" << 'EOF'
---
- name: Cek apakah API key sudah tersimpan
  stat:
    path: "{{ thehive_api_key_file }}"
  register: api_key_file

- name: Generate API key jika belum ada
  uri:
    url: "{{ thehive_url }}/api/v1/user/admin@thehive.local/key/renew"
    method: POST
    user: "{{ thehive_admin_user }}"
    password: "{{ thehive_admin_pass }}"
    force_basic_auth: yes
    status_code: [200, 201]
    return_content: yes
  register: api_key_result
  when: not api_key_file.stat.exists
  failed_when: false

- name: Simpan API key ke file
  copy:
    content: "{{ api_key_result.content | regex_replace('\"', '') }}"
    dest: "{{ thehive_api_key_file }}"
    mode: '0600'
  when:
    - not api_key_file.stat.exists
    - api_key_result is defined
    - api_key_result.status in [200, 201]

- name: Baca dan tampilkan API key
  slurp:
    src: "{{ thehive_api_key_file }}"
  register: stored_key
  failed_when: false

- name: Info API key TheHive
  debug:
    msg: "TheHive API Key: {{ stored_key.content | b64decode | trim }}"
  when: stored_key.content is defined
EOF

# ──────────────────────────────────────────────
# .gitignore
# ──────────────────────────────────────────────
cat > "$BASE/.gitignore" << 'EOF'
*.pem
*.key
.thehive_api_key
*.retry
__pycache__/
.env
*:Zone.Identifier
EOF

# ──────────────────────────────────────────────
# README.md
# ──────────────────────────────────────────────
cat > "$BASE/README.md" << 'EOF'
# SOAR Auto-Recovery Ansible Playbook

Otomatis memulihkan seluruh stack SOAR setelah VM restart.

## Cara Pakai

```bash
# Test koneksi
ansible all -i inventory/hosts.ini -m ping

# Jalankan semua
ansible-playbook -i inventory/hosts.ini site.yml
```

## Setelah VM Restart
Cukup jalankan satu command di atas — semua kembali normal dalam ~2 menit.
EOF

echo ""
echo "======================================================"
echo " Bootstrap selesai! Struktur:"
find "$BASE" -not -path '*/\.*' | sort | sed 's|'"$BASE"'||' | sed 's|^/||' | awk '{print "  " $0}'
echo ""
echo " Langkah berikutnya:"
echo "   cd ~/soar-ansible"
echo "   ansible all -i inventory/hosts.ini -m ping"
echo "======================================================"
