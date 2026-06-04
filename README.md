# SOAR Auto-Recovery Ansible Playbook

Playbook ini otomatis memulihkan seluruh stack SOAR setelah VM restart.

## Yang Diotomatisin

| Role | Target | Yang Dilakukan |
|------|--------|----------------|
| `iptables` | agent-02 | Pasang iptables LOG rule, persistent, monitor kern.log |
| `wazuh` | manager | Deploy rules, notify-n8n.sh, active-response config |
| `docker_stack` | manager | Start TheHive + ES + n8n jika mati |
| `thehive_init` | manager | Generate + simpan API key TheHive |

## Cara Pakai

### 1. Pastikan Ansible terinstall di WSL
```bash
ansible --version
```

### 2. Sesuaikan inventory jika IP berubah
```bash
nano inventory/hosts.ini
```

### 3. Test koneksi ke semua VM
```bash
ansible all -i inventory/hosts.ini -m ping
```

### 4. Jalankan playbook
```bash
ansible-playbook -i inventory/hosts.ini site.yml
```

### 5. Jalankan hanya role tertentu (pakai tag)
```bash
# Hanya fix iptables di agent-02
ansible-playbook -i inventory/hosts.ini site.yml --limit vm-agent-02

# Hanya fix wazuh di manager
ansible-playbook -i inventory/hosts.ini site.yml --tags wazuh

# Hanya restart docker stack
ansible-playbook -i inventory/hosts.ini site.yml --tags docker
```

## Setelah VM Restart

Cukup jalankan:
```bash
ansible-playbook -i inventory/hosts.ini site.yml
```

Semua akan kembali normal dalam ~2 menit.

## Struktur

```
soar-ansible/
├── site.yml                    # Main playbook
├── inventory/
│   └── hosts.ini               # IP dan SSH key semua VM
└── roles/
    ├── iptables/               # Setup agent-02
    ├── wazuh/                  # Setup manager (rules + script)
    ├── docker_stack/           # Start Docker containers
    └── thehive_init/           # Generate API key TheHive
```
