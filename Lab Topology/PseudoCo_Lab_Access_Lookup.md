# PseudoCo Lab Access Lookup

Operator lookup for the Cisco One Experience / dCloud **PseudoCo** lab.

These are **lab and demo credentials** for this dCloud session only. They are not for production systems. Do not reuse them outside the lab. Playbooks must not read this file; Ansible inventory and roles must not embed these passwords.

VPN (Cisco Secure Client / AnyConnect) must be connected before any access or automation.

The Linux **script server** used for Ansible bootstrap is `198.18.134.12` (user `cisco`). It is not listed in the tables below.

See also [PseudoCo_Lab_Topology.png](PseudoCo_Lab_Topology.png).

## Jumphost Access

| Device Hostname / Service | Admin Access | Username | Password |
| --- | --- | --- | --- |
| Jumphost1 | RDP: 198.18.133.36 | corp.pseudoco.com\demouser | C1sco12345 |
| Jumphost2 | RDP: 198.18.133.37 | corp.pseudoco.com\demouser | C1sco12345 |
| Jumphost3 | RDP: 198.18.133.38 | corp.pseudoco.com\demouser | C1sco12345 |

## Management Access

| Device Hostname / Service | Admin Access | Username | Password |
| --- | --- | --- | --- |
| Catalyst Center | https://cat-center.corp.pseudoco.com | admin | Demo@C!sco |
| Identity Services Engine | https://ise.corp.pseudoco.com/admin/login.jsp | admin | C1sco12345 |
| Catalyst SD-WAN Manager | https://sd-wan.corp.pseudoco.com/ | admin | C1sco12345 |
| Cisco 9800-WLC | https://wlc.corp.pseudoco.com/webui/ | admin | C1sco12345 |
| Cisco Nexus Dashboard | https://ndfc.corp.pseudoco.com/ | admin | C1sco12345 |
| Splunk Enterprise | https://splunk.corp.pseudoco.com:8000/ | admin | C1sco12345 |
| Secure Network Analytics | https://smc.corp.pseudoco.com/ | admin | C1sco12345 |
| Cisco Telemetry Broker | https://ctb-m.corp.pseudoco.com/login | admin | C1sco12345 |

## Pseudoco Users

| User | Role / SGT | Username | Password |
| --- | --- | --- | --- |
| Kit | Production (19) | Kit | C1sco12345 |
| Pat | Production (19) | Pat | C1sco12345 |
| Nik | Main (16) | Nik | C1sco12345 |
| Lee | Contractor | Lee | C1sco12345 |
| PRODUser | Production (19) | PRODUser | C1sco12345 |
| MainUser | Main (16) | MainUser | C1sco12345 |
| IOTUser | IoT (18) | IOTUser | C1sco12345 |

## Workstation Access

| Device Hostname / Service | Admin Access / Auth / Role / User | Username | Password |
| --- | --- | --- | --- |
| Workstation-1 | RDP: 198.18.133.50 / EAP-TLS / PROD / Pat | Pat | C1sco12345 |
| Workstation-2 | RDP: 198.18.133.51 / EAP-TLS / PROD / Kit | Kit | C1sco12345 |
| Workstation-3 | RDP: 198.18.133.52 / EAP-TLS / Main / Nik | Nik | C1sco12345 |
| Workstation-IOT | RDP: 198.18.133.53 / MAB / IOT | — | — |
| RWST-1 | RDP: 198.18.133.55 / ZTNA / Contractor / Lee | Lee | C1sco12345 |
| RWST-2 | RDP: 198.18.133.56 / ZTNA / Production / Kit | Kit | C1sco12345 |

## Infrastructure Access

### HQ Infrastructure

| HQ Infrastructure | Admin Access | Username | Password |
| --- | --- | --- | --- |
| vmanage / SD-WAN Manager | ssh: 198.18.133.10 | admin | C1sco12345 |
| vbond / SD-WAN Validator | ssh: 198.18.133.11 | admin | C1sco12345 |
| vsmart / SD-WAN Controller | ssh: 198.18.133.12 | admin | C1sco12345 |
| inet8kv | ssh: 198.18.133.21 | admin | C1sco12345 |
| inet-rwkst | ssh: 198.18.134.101 | admin | C1sco12345 |
| C9800-WLC | ssh: 198.18.5.102 | admin | C1sco12345 |
| HQ-SITE10-CEDGE8Kv | ssh: 198.18.133.13 | admin | C1sco12345 |
| AD1 Server | RDP: 198.18.5.102 | administrator | C1sco12345 |
| vFTD | ssh: 198.18.133.39 | admin | C1sco12345 |
| ISE | ssh: 198.18.5.101 | admin | C1sco12345 |

### Data Center Infrastructure

| Data Center Infrastructure | Admin Access | Username | Password |
| --- | --- | --- | --- |
| DC-SITE11-CEDGE8Kv | ssh: 198.18.133.14 | admin | C1sco12345 |
| DC-Leaf1 | ssh: 198.18.128.101 | admin | C1sco12345 |
| DC-Leaf2 | ssh: 198.18.128.102 | admin | C1sco12345 |
| DC-Service-Leaf | ssh: 198.18.128.13 | admin | C1sco12345 |
| DC-SPINE-1 | ssh: 198.18.128.11 | admin | C1sco12345 |
| DC-SPINE-2 | ssh: 198.18.128.12 | admin | C1sco12345 |
| MAIN - SERVER1 | ssh: 198.18.133.15 | admin | C1sco12345 |
| PROD - SERVER1 | ssh: 198.18.133.16 | admin | C1sco12345 |
| IOT - SERVER1 | ssh: 198.18.133.17 | admin | C1sco12345 |

### Branch Hardware Infrastructure

| Branch Hardware Infrastructure | Admin Access | Username | Password |
| --- | --- | --- | --- |
| Site_105-Border-Spine | ssh: 198.18.128.24 | admin | C1sco12345 |
| Site_105-Leaf1 | ssh: 198.18.128.22 | admin | C1sco12345 |
| Site_105-Leaf2 | ssh: 198.18.128.23 | admin | C1sco12345 |
| BRANCH-SITE105-SEC-RTR | ssh: 198.18.128.25 | admin | C1sco12345 |
| HQ-SITE10-CEDGE8Kv | ssh: 198.18.133.13 | admin | C1sco12345 |
