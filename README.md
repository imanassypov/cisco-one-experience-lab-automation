# Cisco One Experience Lab Automation

Ansible collections that automate the dCloud-delivered **Cisco One Experience** (PseudoCo) lab.

Connect **Cisco Secure Client / AnyConnect** to the dCloud session before any SSH, RDP, or playbook run.

## Development workflow

Playbooks are written on the student laptop. Collection `00` is also run there and fully prepares Kali. Campus and later collections execute on the bootstrapped script server.

```mermaid
flowchart LR
  Laptop["Student laptop: author + run 00"]
  GitHub["GitHub main"]
  Script["Kali: Python, Ansible, SDKs"]
  Laptop -->|"commit and push"| GitHub
  Laptop -->|"00: bootstrap and 02_sync_from_git"| Script
  GitHub -->|"cloned onto Kali by 00"| Script
  Script -->|"01_campus and later ansible-playbook"| Lab["Lab devices"]
```

1. **Develop on the student laptop** in this repo (`ansible-automation/`). Do not author new playbooks on the script server.
2. **Push to GitHub** (`origin` / `main`): https://github.com/imanassypov/cisco-one-experience-lab-automation
3. **Prep the script server from the laptop** (VPN up). Collection `00` is the complete prep — packages, `~/venv`, Ansible, collections, SDKs, DNS, the git checkout, and a copy of the laptop `.vault` (dCloud demo only; change this for production):

   ```bash
   cd ansible-automation
   source .venv/bin/activate
   cd 00_scriptserver_bootstrap
   ansible-playbook playbooks/00_preflight.yml
   ansible-playbook playbooks/01_bootstrap_script_server.yml
   ```

   Later laptop-side refreshes of the Kali tree: `playbooks/02_sync_from_git.yml` (git only). Never run collection `00` on Kali.
4. **Run every later collection on Kali** (SSH as `cisco`). Python, Ansible, collections, and SDKs are already in `~/venv` and on PATH:

   ```bash
   cd ~/cisco-one-experience-lab-automation/ansible-automation/<collection>
   ansible-playbook playbooks/00_....yml
   ```

## Lab references

- [Lab topology diagram](Lab%20Topology/PseudoCo_Lab_Topology.png)
- [Lab access lookup](Lab%20Topology/PseudoCo_Lab_Access_Lookup.md) — host and URL index. Credentials for all playbooks are vault-encrypted in [lab_access.yml](Lab%20Topology/lab_access.yml)

## Collection layout

Playbooks live under `ansible-automation/`. Numbered folders follow lab-build order. Each folder is a self-contained collection.

| Folder | Lab section | Status |
| --- | --- | --- |
| [00_scriptserver_bootstrap](ansible-automation/00_scriptserver_bootstrap/) | Kali Linux script server (`198.18.134.12`) | Implemented |
| [01_campus](ansible-automation/01_campus/) | Campus — [sda](ansible-automation/01_campus/sda/) stub, [evpn](ansible-automation/01_campus/evpn/) in progress | In progress |
| [02_data_center](ansible-automation/02_data_center/) | HQ data center services | Stub |
| [03_dmz](ansible-automation/03_dmz/) | DMZ and Secure Access connector | Stub |
| [04_remote_dc](ansible-automation/04_remote_dc/) | Remote DC / Nexus fabric | Stub |
| [05_sdwan](ansible-automation/05_sdwan/) | SD-WAN fabric and controllers | Stub |
| [06_secure_access](ansible-automation/06_secure_access/) | Cloud SSE / ZTNA / Secure Access | Stub |

## First step — bootstrap the script server

Use a **project-local virtualenv** on the Mac (do not install Ansible system-wide):

```bash
cd ansible-automation
./setup-local-venv.sh
source .venv/bin/activate
cd 00_scriptserver_bootstrap
ansible-playbook playbooks/00_preflight.yml
ansible-playbook playbooks/01_bootstrap_script_server.yml
```

See [00_scriptserver_bootstrap/README.md](ansible-automation/00_scriptserver_bootstrap/README.md) for details.
