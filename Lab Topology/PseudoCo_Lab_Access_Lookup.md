# PseudoCo Lab Access Lookup

Operator index for the Cisco One Experience / dCloud **PseudoCo** lab.

Credentials are **not** stored in this file. The single vault-encrypted source
for every playbook is [lab_access.yml](lab_access.yml). Unlock it with the same
lab vault password as the repo-root gitignored `.vault`. Schema (no secrets):
[lab_access.yml.example](lab_access.yml.example).

These are lab and demo accounts for this dCloud session only. Do not reuse them
outside the lab. Do not copy passwords into playbooks or unencrypted inventory.

VPN (Cisco Secure Client / AnyConnect) must be connected before any access or automation.

The Linux **script server** used for Ansible bootstrap is `198.18.134.12`
(`lab_access` key `script_server`).

See also [PseudoCo_Lab_Topology.png](PseudoCo_Lab_Topology.png).

## How playbooks look up a row

```yaml
ansible_user: "{{ lab_access[inventory_hostname].username }}"
ansible_password: "{{ lab_access[inventory_hostname].password }}"
# named services:
catc_username: "{{ lab_access['Catalyst Center'].username }}"
```

## Jumphost Access

| Device Hostname / Service | Admin Access |
| --- | --- |
| Jumphost1 | RDP: 198.18.133.36 |
| Jumphost2 | RDP: 198.18.133.37 |
| Jumphost3 | RDP: 198.18.133.38 |

## Management Access

| Device Hostname / Service | Admin Access |
| --- | --- |
| Catalyst Center | https://cat-center.corp.pseudoco.com |
| Identity Services Engine | https://ise.corp.pseudoco.com/admin/login.jsp |
| Catalyst SD-WAN Manager | https://sd-wan.corp.pseudoco.com/ |
| Cisco 9800-WLC | https://wlc.corp.pseudoco.com/webui/ |
| Cisco Nexus Dashboard | https://ndfc.corp.pseudoco.com/ |
| Splunk Enterprise | https://splunk.corp.pseudoco.com:8000/ |
| Secure Network Analytics | https://smc.corp.pseudoco.com/ |
| Cisco Telemetry Broker | https://ctb-m.corp.pseudoco.com/login |

## Pseudoco Users

| User | Role / SGT |
| --- | --- |
| Kit | Production (19) |
| Pat | Production (19) |
| Nik | Main (16) |
| Lee | Contractor |
| PRODUser | Production (19) |
| MainUser | Main (16) |
| IOTUser | IoT (18) |

## Workstation Access

| Device Hostname / Service | Admin Access / Auth / Role / User |
| --- | --- |
| Workstation-1 | RDP: 198.18.133.50 / EAP-TLS / PROD / Pat |
| Workstation-2 | RDP: 198.18.133.51 / EAP-TLS / PROD / Kit |
| Workstation-3 | RDP: 198.18.133.52 / EAP-TLS / Main / Nik |
| Workstation-IOT | RDP: 198.18.133.53 / MAB / IOT |
| RWST-1 | RDP: 198.18.133.55 / ZTNA / Contractor / Lee |
| RWST-2 | RDP: 198.18.133.56 / ZTNA / Production / Kit |

## Infrastructure Access

### HQ Infrastructure

| HQ Infrastructure | Admin Access |
| --- | --- |
| vmanage / SD-WAN Manager | ssh: 198.18.133.10 |
| vbond / SD-WAN Validator | ssh: 198.18.133.11 |
| vsmart / SD-WAN Controller | ssh: 198.18.133.12 |
| inet8kv | ssh: 198.18.133.21 |
| inet-rwkst | ssh: 198.18.134.101 |
| C9800-WLC | ssh: 198.18.5.102 |
| HQ-SITE10-CEDGE8Kv | ssh: 198.18.133.13 |
| AD1 Server | RDP: 198.18.5.102 |
| vFTD | ssh: 198.18.133.39 |
| ISE | ssh: 198.18.5.101 |

### Data Center Infrastructure

| Data Center Infrastructure | Admin Access |
| --- | --- |
| DC-SITE11-CEDGE8Kv | ssh: 198.18.133.14 |
| DC-Leaf1 | ssh: 198.18.128.101 |
| DC-Leaf2 | ssh: 198.18.128.102 |
| DC-Service-Leaf | ssh: 198.18.128.13 |
| DC-SPINE-1 | ssh: 198.18.128.11 |
| DC-SPINE-2 | ssh: 198.18.128.12 |
| MAIN - SERVER1 | ssh: 198.18.133.15 |
| PROD - SERVER1 | ssh: 198.18.133.16 |
| IOT - SERVER1 | ssh: 198.18.133.17 |

### Branch Hardware Infrastructure

| Branch Hardware Infrastructure | Admin Access |
| --- | --- |
| Site_105-Border-Spine | ssh: 198.18.128.24 |
| Site_105-Leaf1 | ssh: 198.18.128.22 |
| Site_105-Leaf2 | ssh: 198.18.128.23 |
| BRANCH-SITE105-SEC-RTR | ssh: 198.18.128.25 |
| HQ-SITE10-CEDGE8Kv | ssh: 198.18.133.13 |
