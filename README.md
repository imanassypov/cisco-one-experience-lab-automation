# Cisco One Experience Lab Automation

Ansible collections that automate the dCloud-delivered **Cisco One Experience** (PseudoCo) lab.

Connect **Cisco Secure Client / AnyConnect** to the dCloud session before any SSH, RDP, or playbook run.

## Lab references

- [Lab topology diagram](Lab%20Topology/PseudoCo_Lab_Topology.png)
- [Lab access lookup](Lab%20Topology/PseudoCo_Lab_Access_Lookup.md) — jumphosts, management GUIs, users, workstations, and infrastructure (lab/demo credentials only)

## Collection layout

Playbooks live under `ansible-automation/`. Numbered folders follow lab-build order. Each folder is a self-contained collection.

| Folder | Lab section | Status |
| --- | --- | --- |
| [00_scriptserver_bootstrap](ansible-automation/00_scriptserver_bootstrap/) | Kali Linux script server (`198.18.134.12`) | Implemented |
| [01_campus](ansible-automation/01_campus/) | Campus fabric and workstations | Stub |
| [02_data_center](ansible-automation/02_data_center/) | HQ data center services | Stub |
| [03_dmz](ansible-automation/03_dmz/) | DMZ and Secure Access connector | Stub |
| [04_remote_dc](ansible-automation/04_remote_dc/) | Remote DC / Nexus fabric | Stub |
| [05_sdwan](ansible-automation/05_sdwan/) | SD-WAN fabric and controllers | Stub |
| [06_secure_access](ansible-automation/06_secure_access/) | Cloud SSE / ZTNA / Secure Access | Stub |

## First step — bootstrap the script server

Use a **project-local virtualenv** on the Mac (do not install Ansible system-wide):

```bash
cd ansible-automation/00_scriptserver_bootstrap
./setup-local-venv.sh
source .venv/bin/activate
ansible-playbook playbooks/00_preflight.yml
ansible-playbook playbooks/01_bootstrap_script_server.yml
```

See [00_scriptserver_bootstrap/README.md](ansible-automation/00_scriptserver_bootstrap/README.md) for details.
